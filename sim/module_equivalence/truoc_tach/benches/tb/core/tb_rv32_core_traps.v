`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench ngoại lệ chính xác (precise trap) của rv32_core.
 *
 * Mục tiêu:
 * - Kích hoạt đủ chín cause mà core công bố: 0, 1, 2, 3, 4, 5, 6, 7, 11.
 * - Kiểm tra cause, PC và instruction được chốt tại điểm commit WB.
 * - Xác nhận core dừng bền vững sau trap và instruction gây lỗi không retire.
 *
 * Instruction nhận req/gnt và trả rvalid sau một chu kỳ. Data trả ready ngay
 * trong chu kỳ req; bổ sung cho tb_rv32_core dùng mô hình có wait-state dài.
 */
module tb_rv32_core_traps;

    reg clk;
    reg rst;
    reg [31:0] instruction;
    reg instruction_fault;
    reg data_fault;

    wire        imem_req;
    wire [31:0] imem_addr;
    wire        dmem_req;
    wire        dmem_we;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        halted;
    wire        trap_valid;
    wire [4:0]  trap_cause;
    wire [31:0] trap_pc;
    wire [31:0] trap_instr;
    wire        retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    wire        retire_rd_we;
    wire [4:0]  retire_rd_addr;
    wire [31:0] retire_rd_data;
    wire [31:0] debug_fetch_pc;
    reg  [31:0] imem_rdata;
    wire        imem_gnt;
    reg         imem_rvalid;
    reg         imem_err;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;
    wire        dmem_err;

    integer checks;
    integer retire_count;

    assign imem_gnt   = !rst;
    assign dmem_ready = dmem_req;
    assign dmem_rdata = 32'h1234_5678;
    assign dmem_err   = dmem_req && data_fault;

    rv32_core dut (
        .clk_i(clk), .rst_i(rst),
        .imem_req_o(imem_req), .imem_addr_o(imem_addr),
        .imem_gnt_i(imem_gnt), .imem_rvalid_i(imem_rvalid),
        .imem_rdata_i(imem_rdata),
        .imem_err_i(imem_err),
        .dmem_req_o(dmem_req), .dmem_we_o(dmem_we),
        .dmem_addr_o(dmem_addr), .dmem_wdata_o(dmem_wdata),
        .dmem_wstrb_o(dmem_wstrb), .dmem_rdata_i(dmem_rdata),
        .dmem_ready_i(dmem_ready), .dmem_err_i(dmem_err),
        .halted_o(halted), .trap_valid_o(trap_valid),
        .trap_cause_o(trap_cause), .trap_pc_o(trap_pc),
        .trap_instr_o(trap_instr), .retire_valid_o(retire_valid),
        .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_rd_we_o(retire_rd_we), .retire_rd_addr_o(retire_rd_addr),
        .retire_rd_data_o(retire_rd_data), .debug_fetch_pc_o(debug_fetch_pc)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            imem_rvalid <= 1'b0;
            imem_rdata <= 32'b0;
            imem_err <= 1'b0;
        end
        else begin
            imem_rvalid <= imem_req && imem_gnt;
            imem_rdata <= instruction;
            imem_err <= imem_req && imem_gnt && instruction_fault;
        end
    end

    always @(posedge clk) begin
        if (rst)
            retire_count <= 0;
        else if (retire_valid)
            retire_count <= retire_count + 1;
    end

    task run_trap_case;
        input [8*40-1:0] case_name;
        input [31:0] case_instruction;
        input        case_ifault;
        input        case_dfault;
        input [4:0]  expected_cause;
        input [31:0] expected_trap_instruction;
        integer watchdog;
        begin
            instruction      = case_instruction;
            instruction_fault = case_ifault;
            data_fault        = case_dfault;
            rst = 1'b1;
            repeat (3) @(negedge clk);
            rst = 1'b0;

            watchdog = 0;
            while (!trap_valid && watchdog < 40) begin
                @(posedge clk);
                watchdog = watchdog + 1;
            end

            if (!trap_valid)
                $fatal(1, "Timeout trap: %s", case_name);
            if (!halted || trap_cause !== expected_cause || trap_pc !== 32'd0 ||
                trap_instr !== expected_trap_instruction)
                $fatal(1, "Sai trap %s: halted=%b cause=%0d pc=%08x instr=%08x",
                       case_name, halted, trap_cause, trap_pc, trap_instr);
            if (retire_count != 0)
                $fatal(1, "Instruction gay trap da retire trong case %s", case_name);

            // Trap phải sticky cho tới reset, không tự chạy lại pipeline.
            repeat (3) @(posedge clk);
            if (!trap_valid || !halted || trap_cause !== expected_cause)
                $fatal(1, "Trap khong sticky trong case %s", case_name);
            checks = checks + 4;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        instruction = 32'h0000_0013;
        instruction_fault = 1'b0;
        data_fault = 1'b0;
        checks = 0;
        retire_count = 0;
        imem_rvalid = 1'b0;
        imem_rdata = 32'b0;
        imem_err = 1'b0;

        // JAL x0,+2: target không căn 4 byte khi extension C không được hỗ trợ.
        run_trap_case("instruction address misaligned", 32'h0020_006f, 0, 0, 5'd0, 32'h0020_006f);
        run_trap_case("instruction access fault",      32'h0000_0013, 1, 0, 5'd1, 32'h0000_0000);
        run_trap_case("illegal instruction",           32'hffff_ffff, 0, 0, 5'd2, 32'hffff_ffff);
        run_trap_case("breakpoint",                    32'h0010_0073, 0, 0, 5'd3, 32'h0010_0073);
        run_trap_case("load address misaligned",       32'h0020_2083, 0, 0, 5'd4, 32'h0020_2083);
        run_trap_case("load access fault",             32'h1000_2083, 0, 1, 5'd5, 32'h1000_2083);
        run_trap_case("store address misaligned",      32'h0000_2123, 0, 0, 5'd6, 32'h0000_2123);
        run_trap_case("store access fault",            32'h1000_2023, 0, 1, 5'd7, 32'h1000_2023);
        run_trap_case("ecall machine mode",            32'h0000_0073, 0, 0, 5'd11, 32'h0000_0073);
        run_trap_case("load to x0 still faults",        32'h1000_2003, 0, 1, 5'd5, 32'h1000_2003);
        run_trap_case("JALR target bit 1 misaligned",   32'h0020_00e7, 0, 0, 5'd0, 32'h0020_00e7);

        $display("PASS tb_rv32_core_traps: %0d checks, 9 causes", checks);
        $finish;
    end

endmodule

`default_nettype wire
