`timescale 1ns/1ps
`default_nettype none

// Đo trên core nối ROM thật: 32 ADDI phụ thuộc liên tiếp phải retire mỗi chu kỳ.
module tb_rv32_core_fetch;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    wire req, gnt, rvalid, err, dreq, retired, rd_we, trap;
    wire [31:0] addr, data, pc, rd_data, trap_pc;
    wire [4:0] rd, cause;
    integer k, cycle = 0, count = 0, previous_cycle = -1;
    rv32_core dut (
        .clk_i(clk), .rst_i(rst), .imem_req_o(req), .imem_addr_o(addr),
        .imem_gnt_i(gnt), .imem_rvalid_i(rvalid), .imem_rdata_i(data),
        .imem_err_i(err), .dmem_req_o(dreq), .dmem_we_o(), .dmem_addr_o(),
        .dmem_wdata_o(), .dmem_wstrb_o(), .dmem_rdata_i(32'b0),
        .dmem_ready_i(1'b1), .dmem_err_i(1'b0), .halted_o(),
        .trap_valid_o(trap), .trap_cause_o(cause), .trap_pc_o(trap_pc),
        .trap_instr_o(), .retire_valid_o(retired), .retire_pc_o(pc),
        .retire_instr_o(), .retire_rd_we_o(rd_we), .retire_rd_addr_o(rd),
        .retire_rd_data_o(rd_data), .debug_fetch_pc_o());
    soc_rom_dp #(.WORDS(64)) rom (
        .clk_i(clk), .rst_i(rst), .i_req_i(req), .i_addr_i(addr),
        .i_gnt_o(gnt), .i_rvalid_o(rvalid), .i_rdata_o(data), .i_err_o(err),
        .d_req_i(1'b0), .d_addr_i(32'b0), .d_rdata_o(), .d_ready_o(), .d_err_o());

    always @(posedge clk) begin
        if (!rst) begin
            cycle = cycle + 1;
            if (dreq) $fatal(1, "Unexpected data request");
            if (retired) begin
                if (count >= 32 || pc !== count * 4 || !rd_we || rd !== 1 ||
                    rd_data !== count + 1)
                    $fatal(1, "Retirement mismatch: pc=%h rd_data=%h count=%0d", pc, rd_data, count);
                if (count > 0 && cycle != previous_cycle + 1)
                    $fatal(1, "ROM/core inserted fetch bubble at pc=%h", pc);
                previous_cycle = cycle;
                count = count + 1;
            end
        end
    end
    initial begin
        for (k = 0; k < 64; k = k + 1) rom.u_storage.mem[k] = 32'h00100073;
        for (k = 0; k < 32; k = k + 1) rom.u_storage.mem[k] = 32'h00108093;
        repeat (3) @(negedge clk); rst = 0;
        wait(trap); @(negedge clk);
        if (count != 32 || cause !== 3 || trap_pc !== 128)
            $fatal(1, "Wrong final trap/count");
        $display("PASS tb_rv32_core_fetch: 32 consecutive retirements, ROM latency=1, CPI=1 in steady state");
        $finish;
    end
    initial begin #5000; $fatal(1, "Core fetch timeout"); end
endmodule
`default_nettype wire
