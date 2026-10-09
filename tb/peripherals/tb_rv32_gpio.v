`timescale 1ns/1ps
`default_nettype none

module tb_rv32_gpio #(parameter integer LED_WIDTH=8);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, req = 0, we = 0;
    reg [11:0] addr=0;
    reg [3:0] strb=0;
    reg [31:0] data = 0;
    reg [9:0] switches = 10'h2A5;
    wire [LED_WIDTH-1:0] leds;
    wire [31:0] rdata;
    wire ready, err;
    integer mask;
    reg [31:0] expected;

    soc_gpio #(.GPIO_LED_WIDTH(LED_WIDTH)) dut (.clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we),
        .addr_i(addr), .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata),
        .ready_o(ready), .err_o(err), .switches_i(switches), .leds_o(leds));

    task write_led;
        input [31:0] value;
        input [3:0] enables;
        begin
            @(negedge clk); req = 1; we = 1; addr = 0; data = value; strb = enables;
            #1; if (!ready || err) $fatal(1, "GPIO write handshake");
            @(negedge clk); req = 0; we = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        if (leds !== 0 || ready || err) $fatal(1, "GPIO reset");
        rst = 0;
        for (mask = 0; mask < 16; mask = mask + 1) begin
            write_led(32'h155, 15);
            expected = 10'h155;
            if (mask & 1) expected[7:0] = 8'hAA;
            if (mask & 2) expected[9:8] = 2'b10;
            expected = expected & ((32'd1 << LED_WIDTH)-1);
            write_led(32'hFFFFFEAA, mask[3:0]);
            if (leds !== expected) $fatal(1, "GPIO byte enables %b got %h", mask[3:0], leds);
        end
        req = 1; addr = 4; #1;
        if (rdata !== {22'd0, switches} || !ready || err) $fatal(1, "GPIO switches");
        we = 1; #1;
        if (!ready || !err) $fatal(1, "GPIO RO write");
        @(negedge clk);
        if (leds !== expected) $fatal(1, "GPIO failed write changed LEDs");
        addr = 8; #1;
        if (!ready || !err) $fatal(1, "GPIO reserved offset");
        addr=12'h100; #1;
        if (!ready || !err) $fatal(1,"GPIO page offset must not alias LED");
        req = 0; #1;
        if (ready || err) $fatal(1, "GPIO idle");
        rst = 1; req = 1; addr = 0; strb = 15;
        @(negedge clk);
        if (leds !== 0 || ready || err) $fatal(1, "GPIO reset wins write");
        $display("PASS tb_rv32_gpio: all 16 byte masks, RO/fault/reset");
        $finish;
    end
    initial begin #10000; $fatal(1, "GPIO timeout"); end
endmodule

`default_nettype wire
