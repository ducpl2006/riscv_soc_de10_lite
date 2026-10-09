`timescale 1ns/1ps
`default_nettype none

// Monitor kiểm tra waveform theo FIFO các byte đã được bus nhận, không đọc RAM DUT.
module tb_rv32_uart_fifo #(
    parameter integer DIV = 4,
    parameter integer DEPTH = 4
);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, req = 0, we = 0;
    reg [3:0] addr = 0, strb = 1;
    reg [31:0] data = 0;
    wire [31:0] rdata;
    wire ready, err, tx, busy;
    reg [7:0] expected [0:255];
    integer accepted = 0, received = 0, phase = 0, bit_clocks = 0;
    integer i, waits = 0, simultaneous = 0;
    reg [9:0] frame;
    soc_uart_tx #(.CLOCK_HZ(DIV*10), .BAUD(10), .FIFO_DEPTH(DEPTH)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we), .addr_i(addr),
        .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata), .ready_o(ready),
        .err_o(err), .tx_o(tx), .busy_o(busy));

    always @(posedge clk) begin
        if (rst) begin
            accepted = 0; received = 0; phase = 0; bit_clocks = 0;
        end
        else begin
            if (req && ready && !err && we && addr == 0 && strb[0]) begin
                expected[accepted] = data[7:0];
                accepted = accepted + 1;
            end
            if (req && !ready) waits = waits + 1;
            if (dut.fifo_pop && dut.fifo_push) simultaneous = simultaneous + 1;
        end
        #1;
        if (!rst) begin
            if (phase == 0 && tx == 0) begin
                if (received >= accepted) $fatal(1, "UART sent unaccepted byte");
                frame = {1'b1, expected[received], 1'b0};
                phase = 1; bit_clocks = 0;
            end
            if (phase != 0) begin
                if (!busy || tx !== frame[phase-1])
                    $fatal(1, "UART FIFO frame %0d bit %0d: tx=%b", received, phase-1, tx);
                bit_clocks = bit_clocks + 1;
                if (bit_clocks == DIV) begin
                    bit_clocks = 0;
                    if (phase == 10) begin received = received + 1; phase = 0; end
                    else phase = phase + 1;
                end
            end
        end
    end

    task write_byte;
        input [7:0] value;
        begin
            @(negedge clk); req=1; we=1; addr=0; strb=1; data=value;
            #1;
            while (!ready) begin @(negedge clk); #1; end
            if (err) $fatal(1, "UART FIFO rejected valid write");
            @(negedge clk); req=0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst=0;
        // Ghi quá DEPTH: kiểm tra đầy, chờ, push/pop đồng thời và nhiều vòng con trỏ.
        for (i=0; i<3*DEPTH+9; i=i+1) write_byte((i*37)^8'hA5);
        while (busy) @(negedge clk);
        repeat (3) @(negedge clk);
        if (received != accepted || received != 3*DEPTH+9 || waits == 0 || simultaneous == 0)
            $fatal(1, "UART FIFO coverage/count: accepted=%0d received=%0d wait=%0d simultaneous=%0d",
                   accepted, received, waits, simultaneous);
        req=1; we=0; addr=4; #1;
        if (rdata !== 1 || !ready || err) $fatal(1, "UART FIFO idle status");
        @(negedge clk); req=0;
        // Nạp lại rồi kiểm tra no-op/lỗi vẫn hoàn tất khi bộ phát đang bận.
        for (i=0; i<=DEPTH; i=i+1) write_byte(8'h55+i);
        if (!busy) $fatal(1, "UART FIFO should be busy");
        req=1; we=1; addr=0; strb=0; #1;
        if (!ready || err) $fatal(1, "UART FIFO zero strobe must not wait");
        @(negedge clk); strb=14; #1;
        if (!ready || err) $fatal(1, "UART FIFO upper lanes must not wait");
        @(negedge clk); addr=4; #1;
        if (!ready || !err) $fatal(1, "UART FIFO RO error while busy");
        @(negedge clk); rst=1; #1;
        if (ready || err) $fatal(1, "UART FIFO reset handshake");
        @(negedge clk); req=0; rst=0;
        repeat (12*DIV) @(negedge clk);
        if (busy || !tx || accepted != 0 || received != 0)
            $fatal(1, "UART FIFO reset must discard queued bytes");
        write_byte(8'hC3);
        while (busy) @(negedge clk);
        if (received != 1) $fatal(1, "UART FIFO restart after reset");
        $display("PASS tb_rv32_uart_fifo: DIV=%0d DEPTH=%0d waveform, wrap, backpressure, strobes, reset", DIV, DEPTH);
        $finish;
    end
    initial begin #1000000; $fatal(1, "UART FIFO timeout"); end
endmodule
`default_nettype wire
