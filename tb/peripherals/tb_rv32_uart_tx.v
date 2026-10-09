`timescale 1ns/1ps
`default_nettype none

module tb_rv32_uart_tx #(
    parameter integer DIV = 4
);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, req = 0, we = 0;
    reg [3:0] addr = 0, strb = 0;
    reg [31:0] data = 0;
    wire [31:0] rdata;
    wire ready, err, tx, busy;
    integer bit_index, cycle;
    reg [9:0] frame;
    // Giữ coverage chế độ không FIFO; tb_rv32_uart_fifo kiểm tra chế độ mặc định.
    soc_uart_tx #(.CLOCK_HZ(DIV*10), .BAUD(10), .FIFO_DEPTH(0)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we), .addr_i(addr),
        .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata), .ready_o(ready),
        .err_o(err), .tx_o(tx), .busy_o(busy));

    task check_frame;
        input [7:0] value;
        begin
            frame = {1'b1, value, 1'b0};
            for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1)
                for (cycle = 0; cycle < DIV; cycle = cycle + 1) begin
                    if (!busy || tx !== frame[bit_index])
                        $fatal(1, "UART bit %0d cycle %0d tx=%b", bit_index, cycle, tx);
                    @(negedge clk);
                end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst = 0;
        if (!tx || busy) $fatal(1, "UART idle");
        req = 1; we = 1; strb = 1; data = 32'hA5; #1;
        if (!ready || err) $fatal(1, "UART first write");
        @(negedge clk);
        // Keep a second request pending through the complete first frame.
        data = 32'h3C; #1;
        if (ready || err) $fatal(1, "UART busy must wait");
        check_frame(8'hA5);
        #1;
        if (busy || !ready || !tx) $fatal(1, "UART end of stop / queued write");
        @(negedge clk); req = 0; we = 0;
        check_frame(8'h3C);
        if (busy || !tx) $fatal(1, "UART duplicate transmission");
        // Other lanes and zero enables are successful no-ops.
        req = 1; we = 1; strb = 14; #1;
        if (!ready || err) $fatal(1, "UART no-op strobe");
        @(negedge clk);
        if (busy) $fatal(1, "UART wrong byte transmitted");
        addr = 4; #1;
        if (!ready || !err) $fatal(1, "UART RO error must complete");
        we = 0; #1;
        if (rdata !== 1 || !ready || err) $fatal(1, "UART STATUS");
        addr = 8; #1;
        if (!ready || !err) $fatal(1, "UART address error must complete");
        addr = 0; we = 1; strb = 1;
        @(negedge clk); rst = 1; #1;
        if (ready || err) $fatal(1, "UART reset handshake");
        @(negedge clk);
        if (busy || !tx) $fatal(1, "UART reset abort");
        $display("PASS tb_rv32_uart_tx: 8N1 timing, pending write, strobes, faults, reset");
        $finish;
    end
    initial begin #20000; $fatal(1, "UART timeout"); end
endmodule

`default_nettype wire
