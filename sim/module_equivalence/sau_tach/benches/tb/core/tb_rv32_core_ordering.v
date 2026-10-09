`timescale 1ns/1ps
`default_nettype none

// Adversarial instruction/data timing. Scoreboard observes architectural ports.
module tb_rv32_core_ordering;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    integer scenario = 0;
    integer fetch_wait, data_wait, drain_wait;
    wire ireq, dreq, dwe, halted, trap, retired, rd_we;
    wire [31:0] iaddr, daddr, wdata, trap_pc, trap_instr, retire_pc, retire_instr, rd_data;
    wire [4:0] cause, rd;
    wire [3:0] strb;
    reg [31:0] instruction;
    reg i_pending;
    reg [31:0] i_response_addr;
    wire delayed_fetch = (scenario == 1 && i_response_addr == 4);
    wire delayed_drain = (scenario == 1 && i_response_addr == 24);
    wire ignt = !i_pending;
    wire irvalid = i_pending && (!delayed_fetch || fetch_wait == 0) &&
                                 (!delayed_drain || drain_wait == 0);
    wire ierr = irvalid && delayed_fetch;
    wire dready = dreq && data_wait == 0;
    wire derr = dready && scenario == 0;
    integer retires, stores, watchdog;
    reg [31:0] observed [0:31];
    reg held_i, held_d;
    reg [31:0] held_iaddr;
    reg [68:0] held_payload;
    integer k;

    rv32_core dut (
        .clk_i(clk), .rst_i(rst), .imem_req_o(ireq), .imem_addr_o(iaddr),
        .imem_gnt_i(ignt), .imem_rvalid_i(irvalid),
        .imem_rdata_i(instruction), .imem_err_i(ierr),
        .dmem_req_o(dreq), .dmem_we_o(dwe), .dmem_addr_o(daddr),
        .dmem_wdata_o(wdata), .dmem_wstrb_o(strb), .dmem_rdata_i(32'h87654321),
        .dmem_ready_i(dready), .dmem_err_i(derr), .halted_o(halted),
        .trap_valid_o(trap), .trap_cause_o(cause), .trap_pc_o(trap_pc),
        .trap_instr_o(trap_instr), .retire_valid_o(retired), .retire_pc_o(retire_pc),
        .retire_instr_o(retire_instr), .retire_rd_we_o(rd_we), .retire_rd_addr_o(rd),
        .retire_rd_data_o(rd_data), .debug_fetch_pc_o());

    always @* begin
        instruction = 32'h00100073; // EBREAK
        if (scenario == 0) begin
            case (i_response_addr)
                0: instruction = 32'h02A00093; // addi x1,x0,42
                4: instruction = 32'h10002103; // lw x2,256(x0), access fault
                8: instruction = 32'h010001EF; // jal x3,+16, younger than fault
                12: instruction = 32'h00102223; // sw x1,4(x0), must be killed
                24: instruction = 32'h00102423; // wrong target store
                default: instruction = 32'h00100073;
            endcase
        end
        else if (scenario == 1) begin
            case (i_response_addr)
                0: instruction = 32'h010000EF; // jal x1,+16
                4: instruction = 32'hFFFFFFFF; // delayed wrong-path fetch fault
                16: instruction = 32'h00700113; // addi x2,x0,7
                20: instruction = 32'h00100073;
                default: instruction = 32'h00102223;
            endcase
        end
        else begin
            case (i_response_addr)
                0: instruction = 32'h00100093;
                4: instruction = 32'h10102023; // sw x1,256(x0), held until reset
                default: instruction = 32'h00100073;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            fetch_wait <= 12; drain_wait <= 30; data_wait <= 8;
            i_pending <= 0; i_response_addr <= 0;
            retires <= 0; stores <= 0; held_i <= 0; held_d <= 0;
            for (k = 0; k < 32; k = k + 1) observed[k] <= 0;
        end
        else begin
            if (i_pending && delayed_fetch && fetch_wait > 0) fetch_wait <= fetch_wait - 1;
            if (i_pending && delayed_drain && drain_wait > 0) drain_wait <= drain_wait - 1;
            if (!i_pending && ireq && ignt) begin
                i_pending <= 1;
                i_response_addr <= iaddr;
            end
            else if (irvalid) begin
                i_pending <= 0;
            end
            if (dreq && data_wait > 0) data_wait <= data_wait - 1;
            if (dreq && dready && dwe && !derr) stores <= stores + 1;
            if (retired) begin
                retires <= retires + 1;
                if (rd_we) observed[rd] <= rd_data;
            end
            if (held_i && (!ireq || iaddr !== held_iaddr)) $fatal(1, "Fetch request changed before grant");
            if (held_d && (!dreq || {dwe,daddr,wdata,strb} !== held_payload))
                $fatal(1, "Data request was cancelled/changed");
            held_i <= ireq && !ignt; held_iaddr <= iaddr;
            held_d <= dreq && !dready; held_payload <= {dwe,daddr,wdata,strb};
        end
    end

    task reset_case;
        input integer next_case;
        begin
            @(negedge clk); rst = 1; scenario = next_case;
            repeat (3) @(negedge clk);
            if (ireq || dreq || dwe || strb) $fatal(1, "Core requests during reset");
            rst = 0;
        end
    endtask

    task wait_trap;
        input [4:0] expected_cause;
        input [31:0] expected_pc;
        input integer expected_retires;
        begin
            watchdog = 0;
            while (!trap && watchdog < 100) begin @(negedge clk); watchdog = watchdog + 1; end
            if (!trap || !halted || cause !== expected_cause || trap_pc !== expected_pc)
                $fatal(1, "Ordering case %0d trap cause=%0d pc=%h", scenario, cause, trap_pc);
            repeat (40) @(negedge clk);
            if (retires != expected_retires || stores != 0 || ireq || dreq || retired)
                $fatal(1, "Ordering side effect/drain: retires=%0d stores=%0d", retires, stores);
        end
    endtask

    initial begin
        reset_case(0);
        wait_trap(5, 4, 1);
        if (observed[1] !== 42 || observed[2] !== 0 || observed[3] !== 0)
            $fatal(1, "Older load fault did not squash younger branch/writeback");
        reset_case(1);
        wait_trap(3, 20, 2);
        if (observed[1] !== 4 || observed[2] !== 7) $fatal(1, "Wrong-path fault was not discarded");
        reset_case(2);
        wait (dreq && !dready);
        @(negedge clk); rst = 1; #1;
        if (ireq || dreq || dwe || strb) $fatal(1, "Reset did not gate pending store");
        repeat (3) @(negedge clk);
        if (stores != 0) $fatal(1, "Pending store committed during reset");
        $display("PASS tb_rv32_core_ordering: precise fault priority, wrong-path drain, reset abort");
        $finish;
    end
    initial begin #30000; $fatal(1, "Core ordering timeout"); end
endmodule

`default_nettype wire
