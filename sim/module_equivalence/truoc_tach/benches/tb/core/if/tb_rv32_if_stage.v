`timescale 1ns/1ps
`default_nettype none

module tb_rv32_if_stage;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst;
    reg halted;
    reg wb_trap;
    reg mem_fault;
    reg ex_fault;
    reg ex_redirect;
    reg id_exception;
    reg [31:0] redirect_target;
    reg ifid_consumed;

    wire imem_req;
    wire [31:0] imem_addr;
    reg gnt_enable;
    wire imem_gnt = gnt_enable && !rst;
    reg imem_rvalid;
    reg [31:0] imem_rdata;
    reg imem_err;
    reg inject_stale;
    reg fault_enable;
    reg [31:0] fault_addr;
    reg manual_mode, manual_valid, manual_err;
    reg [31:0] manual_data;

    wire [31:0] debug_fetch_pc;
    wire ifid_valid;
    wire [31:0] ifid_pc;
    wire [31:0] ifid_instr;
    wire ifid_exc_valid;
    wire [4:0] ifid_exc_cause;

    integer checks;
    integer timeout;
    integer n;
    reg [31:0] expected_pc;
    reg [31:0] held_addr;

    rv32_if_stage dut (
        .clk_i(clk), .rst_i(rst), .halted_i(halted),
        .wb_trap_event_i(wb_trap), .mem_fault_event_i(mem_fault),
        .ex_fault_event_i(ex_fault), .ex_redirect_event_i(ex_redirect),
        .id_exception_event_i(id_exception),
        .ex_control_target_i(redirect_target),
        .ifid_consumed_i(ifid_consumed), .imem_gnt_i(imem_gnt),
        .imem_rvalid_i(imem_rvalid), .imem_rdata_i(imem_rdata),
        .imem_err_i(imem_err), .imem_req_o(imem_req),
        .imem_addr_o(imem_addr), .debug_fetch_pc_o(debug_fetch_pc),
        .ifid_valid_o(ifid_valid), .ifid_pc_o(ifid_pc),
        .ifid_instr_o(ifid_instr), .ifid_exc_valid_o(ifid_exc_valid),
        .ifid_exc_cause_o(ifid_exc_cause));

    function [31:0] instruction_for;
        input [31:0] address;
        begin instruction_for = 32'hA0000000 | address; end
    endfunction

    // One-cycle, fully pipelined instruction memory. inject_stale creates a
    // response without a matching post-reset request for the reset-abort case.
    always @(posedge clk) begin
        if (rst) begin
            imem_rvalid <= 1'b0;
            imem_rdata <= 32'b0;
            imem_err <= 1'b0;
        end
        else if (manual_mode) begin
            imem_rvalid <= manual_valid;
            imem_rdata <= manual_data;
            imem_err <= manual_err;
        end
        else if (inject_stale) begin
            imem_rvalid <= 1'b1;
            imem_rdata <= 32'hDEAD_BEEF;
            imem_err <= 1'b0;
        end
        else begin
            imem_rvalid <= imem_req && imem_gnt;
            imem_rdata <= instruction_for(imem_addr);
            imem_err <= imem_req && imem_gnt && fault_enable &&
                        (imem_addr == fault_addr);
        end
    end

    task reset_frontend;
        begin
            rst = 1;
            halted = 0;
            wb_trap = 0;
            mem_fault = 0;
            ex_fault = 0;
            ex_redirect = 0;
            id_exception = 0;
            redirect_target = 0;
            ifid_consumed = 0;
            gnt_enable = 1;
            inject_stale = 0;
            fault_enable = 0;
            fault_addr = 0;
            manual_mode = 0;
            manual_valid = 0;
            manual_err = 0;
            manual_data = 0;
            repeat (3) @(negedge clk);
            rst = 0;
        end
    endtask

    task expect_head;
        input [31:0] pc;
        input expected_exc;
        begin
            timeout = 0;
            while (!ifid_valid && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!ifid_valid || ifid_pc !== pc)
                $fatal(1, "Expected IF head pc=%h, got valid=%b pc=%h",
                       pc, ifid_valid, ifid_pc);
            if (ifid_exc_valid !== expected_exc)
                $fatal(1, "IF exception mismatch at pc=%h", pc);
            if (!expected_exc && ifid_instr !== instruction_for(pc))
                $fatal(1, "IF instruction mismatch at pc=%h", pc);
            if (expected_exc && ifid_exc_cause !== 5'd1)
                $fatal(1, "IF access-fault cause mismatch");
            checks = checks + 1;
            @(negedge clk);
        end
    endtask

    initial begin
        checks = 0;
        imem_rvalid = 0;
        imem_rdata = 0;
        imem_err = 0;

        // Continuous fetch: after initial fill, ID receives one instruction
        // on every cycle and request addresses are consecutive.
        reset_frontend();
        ifid_consumed = 1;
        expected_pc = 0;
        for (n = 0; n < 8; n = n + 1) begin
            if (n > 0 && !ifid_valid)
                $fatal(1, "Mandatory bubble in continuous fetch");
            expect_head(expected_pc, 0);
            expected_pc = expected_pc + 4;
        end

        // A request must remain stable until gnt, then the two-entry FIFO must
        // absorb responses while ID is stalled.
        reset_frontend();
        gnt_enable = 0;
        @(negedge clk);
        if (!imem_req) $fatal(1, "Missing request while gnt is low");
        held_addr = imem_addr;
        repeat (3) begin
            @(negedge clk);
            if (!imem_req || imem_addr !== held_addr)
                $fatal(1, "Request changed before gnt");
        end
        gnt_enable = 1;
        repeat (6) @(negedge clk);
        if (!ifid_valid || ifid_pc !== 0 || imem_req)
            $fatal(1, "FIFO did not fill/back-pressure fetch");
        ifid_consumed = 1;
        expect_head(0, 0);
        expect_head(4, 0);

        // Redirect flushes both buffered instructions and drains wrong-path
        // responses before exposing the target instruction.
        reset_frontend();
        repeat (5) @(negedge clk);
        ex_redirect = 1;
        redirect_target = 32'h0000_0100;
        @(negedge clk);
        ex_redirect = 0;
        ifid_consumed = 1;
        timeout = 0;
        while ((!ifid_valid || ifid_pc != 32'h0000_0100) && timeout < 20) begin
            if (ifid_valid && ifid_pc < 32'h0000_0100)
                $fatal(1, "Wrong-path instruction survived redirect: %h", ifid_pc);
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!ifid_valid || ifid_pc !== 32'h0000_0100)
            $fatal(1, "Redirect target was not fetched");
        checks = checks + 1;

        // Reset while a request is ungranted, then inject an old response. It
        // must not become an instruction after reset.
        reset_frontend();
        gnt_enable = 0;
        repeat (2) @(negedge clk);
        rst = 1;
        @(negedge clk);
        rst = 0;
        inject_stale = 1;
        @(negedge clk);
        inject_stale = 0;
        repeat (2) @(negedge clk);
        if (ifid_valid) $fatal(1, "Stale pre-reset response was committed");
        gnt_enable = 1;
        ifid_consumed = 1;
        expect_head(0, 0);

        // An instruction access error enters the FIFO once, stops new fetches,
        // and reports the architectural cause with the matching PC.
        reset_frontend();
        fault_enable = 1;
        fault_addr = 8;
        ifid_consumed = 1;
        expect_head(0, 0);
        expect_head(4, 0);
        expect_head(8, 1);
        repeat (3) @(negedge clk);
        if (imem_req) $fatal(1, "Fetch continued after instruction fault");

        // Hai lần redirect trong khi có hai yêu cầu đã nhận chưa trả đáp ứng.
        // Cả đáp ứng lỗi lẫn đáp ứng dữ liệu cũ phải tiếp tục bị hủy.
        reset_frontend();
        manual_mode = 1;
        repeat (2) @(negedge clk);
        gnt_enable = 0;
        ex_redirect = 1; redirect_target = 32'h100;
        @(negedge clk);
        redirect_target = 32'h200;
        @(negedge clk);
        ex_redirect = 0;
        manual_valid = 1; manual_err = 1; manual_data = 32'hDEADBEEF;
        @(negedge clk);
        manual_err = 0;
        @(negedge clk);
        manual_valid = 0;
        @(negedge clk);
        if (ifid_valid) $fatal(1, "Two redirects revived a stale response");
        manual_mode = 0; gnt_enable = 1; ifid_consumed = 1;
        expect_head(32'h200, 0);

        // Hai lần redirect trong khi yêu cầu chưa được grant: giữ địa chỉ cũ
        // tới grant, sau đó bỏ đáp ứng và tiếp tục tại target mới nhất.
        reset_frontend();
        gnt_enable = 0;
        repeat (2) @(negedge clk);
        ex_redirect = 1; redirect_target = 32'h100;
        @(negedge clk);
        redirect_target = 32'h300;
        @(negedge clk);
        ex_redirect = 0;
        if (!imem_req || imem_addr !== 0)
            $fatal(1, "Redirect changed ungranted request");
        gnt_enable = 1; ifid_consumed = 1;
        expect_head(32'h300, 0);

        // Reset chung khi hai yêu cầu đã được nhận, đang chờ đáp ứng.
        reset_frontend(); manual_mode = 1;
        repeat (2) @(negedge clk);
        reset_frontend(); ifid_consumed = 1;
        expect_head(0, 0);

        $display("PASS tb_rv32_if_stage: %0d checks, throughput/stall/repeated-redirect/reset/fault", checks);
        $finish;
    end

    initial begin #10000; $fatal(1, "IF stage timeout"); end
endmodule

`default_nettype wire
