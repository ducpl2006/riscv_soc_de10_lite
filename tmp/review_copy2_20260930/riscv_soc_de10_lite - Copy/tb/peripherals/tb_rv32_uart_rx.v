`timescale 1ns/1ps
`default_nettype none
// Kiểm tra UART MMIO qua waveform chân RX; không ép data/valid nội bộ DUT.
module tb_rv32_uart_rx #(
    parameter integer DIV=100,
    parameter integer DEPTH=3
);
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, req=0, we=0, rx=1;
    reg [11:0] addr=0;
    reg [3:0] strb=0;
    reg [31:0] data=0;
    wire [31:0] rdata;
    wire ready,err,tx,busy;
    reg [31:0] value;
    integer i, j, rx_count=0, checks=0;
    reg [31:0] random_q=32'hC518A207;
    soc_uart #(.CLOCK_HZ(DIV*100),.BAUD(100),.RX_FIFO_DEPTH(DEPTH)) dut (
        .clk_i(clk),.rst_i(rst),.req_i(req),.we_i(we),.addr_i(addr),
        .wdata_i(data),.wstrb_i(strb),.rdata_o(rdata),.ready_o(ready),.err_o(err),
        .rx_i(rx),.tx_o(tx),.busy_o(busy));
    task mmio;
        input write_access;
        input [11:0] offset;
        input [31:0] write_data;
        input [3:0] mask;
        input expected_err;
        begin
            @(negedge clk); req=1; we=write_access; addr=offset; data=write_data; strb=mask;
            #1;
            if (!ready || err !== expected_err) $fatal(1,"UART MMIO offset=%h err=%b",offset,err);
            value=rdata;
            @(negedge clk); req=0; we=0;
            checks=checks+1;
        end
    endtask
    task send_frame;
        input [7:0] byte_value;
        input integer bit_period;
        input good_stop;
        integer b;
        begin
            rx=0; repeat(bit_period) @(negedge clk);
            for(b=0;b<8;b=b+1) begin rx=byte_value[b]; repeat(bit_period) @(negedge clk); end
            rx=good_stop; repeat(bit_period) @(negedge clk);
        end
    endtask
    task expect_byte;
        input [7:0] expected;
        begin
            mmio(0,8,0,0,0);
            if (value !== {24'd0,expected}) $fatal(1,"RX data expected=%h actual=%h",expected,value);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=0;
        mmio(0,4,0,0,0);
        if (value !== 9) $fatal(1,"UART reset status");
        mmio(0,8,0,0,1); // empty read fault, không pop
        mmio(1,8,32'h55,15,1);
        mmio(1,4,0,0,1);
        mmio(0,12'h100,0,0,1);
        // Back-to-back + full FIFO; byte thừa bị drop-new, cờ overrun sticky.
        for(i=0;i<DEPTH;i=i+1) send_frame(8'h30+i,DIV,1);
        repeat(4) @(negedge clk);
        mmio(0,4,0,0,0);
        if (value[7:2] !== 6'b000101) $fatal(1,"RX full/valid status %h",value);
        send_frame(8'hEE,DIV,1); repeat(4) @(negedge clk);
        mmio(0,4,0,0,0);
        if (!value[5]) $fatal(1,"RX overrun missing");
        for(i=0;i<DEPTH;i=i+1) expect_byte(8'h30+i);
        mmio(0,8,0,0,1);
        mmio(1,12,32'hE0,0,0); mmio(1,12,32'hE0,14,0);
        mmio(0,12,0,0,0);
        if (value !== 32'h20) $fatal(1,"W1C wrong lanes changed errors");
        mmio(1,12,32'h20,1,0);
        mmio(0,12,0,0,0);
        if (value !== 0) $fatal(1,"W1C failed");
        // Xung start quá ngắn: lấy mẫu giữa start phát hiện line đã cao.
        rx=0; repeat(DIV/4) @(negedge clk); rx=1;
        repeat(DIV+5) @(negedge clk);
        mmio(0,4,0,0,0);
        if (!value[7] || !value[3] || value[2]) $fatal(1,"False start accepted as byte");
        send_frame(8'h55,DIV,0); repeat(2*DIV) @(negedge clk); rx=1;
        repeat(DIV) @(negedge clk);
        mmio(0,4,0,0,0);
        if (!value[6] || !value[7] || !value[3]) $fatal(1,"Framing/break handling");
        mmio(1,12,32'h40,1,0); mmio(0,12,0,0,0);
        if (value !== 32'h80) $fatal(1,"Selective W1C must preserve other flags");
        mmio(1,12,32'hE0,1,0);
        // Nhiều pattern, wrap FIFO; DIV lớn thêm sai lệch baud +/-3%.
        for(i=0;i<64;i=i+1) begin
            random_q=random_q^(random_q<<13); random_q=random_q^(random_q>>17); random_q=random_q^(random_q<<5);
            j=DIV;
            if(DIV>=100) j=DIV+(i%3-1)*(DIV*3/100);
            // Đổi pha chân so với cạnh clock trong phạm vi một chu kỳ.
            #2; send_frame(random_q[7:0],j,1);
            repeat(5) @(negedge clk); expect_byte(random_q[7:0]);
        end
        mmio(0,12,0,0,0);
        if (value !== 0) $fatal(1,"Legal frames raised errors");
        // Reset bỏ cả byte đang chờ lẫn frame đang nhận.
        send_frame(8'hA5,DIV,1);
        rx=0; repeat(3*DIV) @(negedge clk); rst=1; rx=1;
        repeat(3) @(negedge clk); rst=0;
        repeat(12*DIV) @(negedge clk);
        mmio(0,4,0,0,0);
        if (value !== 9) $fatal(1,"Reset did not flush RX and flags");
        send_frame(8'hC3,DIV,1); repeat(5) @(negedge clk); expect_byte(8'hC3);
        $display("PASS tb_rv32_uart_rx: DIV=%0d DEPTH=%0d, %0d MMIO checks, frames/errors/mismatch/reset",DIV,DEPTH,checks);
        $finish;
    end
    initial begin #5000000; $fatal(1,"UART RX timeout"); end
endmodule
`default_nettype wire
