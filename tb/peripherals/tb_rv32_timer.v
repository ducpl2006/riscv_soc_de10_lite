`timescale 1ns/1ps
`default_nettype none

module tb_rv32_timer;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, req = 0, we = 0;
    reg [11:0] addr=0;
    reg [3:0] strb=0;
    reg [31:0] data = 0;
    wire [31:0] rdata;
    wire ready, err, irq;
    reg [63:0] expected;
    reg [31:0] low_word;
    integer mask, lane;
    soc_timer dut (.clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we),
        .addr_i(addr), .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata),
        .ready_o(ready), .err_o(err), .irq_o(irq));

    task write_compare;
        input [11:0] offset;
        input [31:0] value;
        input [3:0] enables;
        begin
            @(negedge clk); req = 1; we = 1; addr = offset; data = value; strb = enables;
            #1; if (!ready || err) $fatal(1, "Timer compare write");
            @(negedge clk); req = 0; we = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst = 0;
        if (irq) $fatal(1, "Timer IRQ reset");
        expected = 64'hFFFFFFFFFFFFFFFF;
        for (mask = 0; mask < 16; mask = mask + 1) begin
            write_compare(8, 32'h12345678 ^ mask, mask[3:0]);
            data = 32'h12345678 ^ mask;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (mask & (1 << lane)) expected[lane*8 +: 8] = data[lane*8 +: 8];
            req = 1; addr = 8; #1;
            if (rdata !== expected[31:0]) $fatal(1, "Timer CMP_LO mask %0d", mask);
            req = 0;
            write_compare(12, 32'h89ABCDEF ^ mask, mask[3:0]);
            data = 32'h89ABCDEF ^ mask;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (mask & (1 << lane)) expected[32+lane*8 +: 8] = data[lane*8 +: 8];
            req = 1; addr = 12; #1;
            if (rdata !== expected[63:32]) $fatal(1, "Timer CMP_HI mask %0d", mask);
            req = 0;
        end
        // Deposit only to reach a 2^32-cycle boundary in a short simulation.
        @(negedge clk); dut.time_q = 64'h00000012_FFFFFFFF;
        req = 1; we = 0; addr = 0; #1; low_word = rdata;
        @(negedge clk); addr = 4; #1;
        if (low_word !== 32'hFFFFFFFF || rdata !== 32'h12)
            $fatal(1, "Timer torn LO/HI snapshot");
        @(negedge clk); addr = 0;
        @(negedge clk); addr = 4; #1;
        if (rdata !== 32'h13) $fatal(1, "Timer snapshot refresh");
        req = 0;
        write_compare(12, 0, 15);
        write_compare(8, 0, 15);
        if (!irq) $fatal(1, "Timer compare IRQ");
        write_compare(8, 32'hFFFFFFFF, 15);
        write_compare(12, 32'hFFFFFFFF, 15);
        @(negedge clk); dut.time_q = 64'hFFFFFFFFFFFFFFFF; #1;
        if (irq) $fatal(1, "Timer disabled sentinel at maximum count");
        @(negedge clk);
        if (dut.time_q !== 0) $fatal(1, "Timer 64-bit wrap");
        req = 1; we = 1; addr = 0; data = 32'hDEADBEEF; #1;
        if (!ready || !err) $fatal(1, "Timer RO write error");
        addr = 2; #1;
        if (!ready || !err) $fatal(1, "Timer unaligned error");
        rst = 1;
        @(negedge clk);
        if (irq || ready || err || dut.time_q !== 0) $fatal(1, "Timer reset");
        $display("PASS tb_rv32_timer: byte masks, snapshot rollover, IRQ, wrap, faults/reset");
        $finish;
    end
    initial begin #20000; $fatal(1, "Timer timeout"); end
endmodule

`default_nettype wire
