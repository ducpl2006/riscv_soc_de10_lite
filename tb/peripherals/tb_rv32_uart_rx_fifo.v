`timescale 1ns/1ps
`default_nettype none
module tb_rv32_uart_rx_fifo #(parameter integer DEPTH=3);
    reg clk=0; always #5 clk=~clk;
    reg rst=1,push=0,pop=0;
    reg [7:0] data=0;
    wire [7:0] head;
    wire empty,full,overrun;
    integer i;
    uart_rx_fifo #(.DEPTH(DEPTH)) dut (.clk_i(clk),.rst_i(rst),.push_i(push),.pop_i(pop),
        .data_i(data),.data_o(head),.empty_o(empty),.full_o(full),.overrun_o(overrun));
    initial begin
        repeat(3) @(negedge clk); rst=0;
        pop=1; @(negedge clk); pop=0;
        if (!empty || overrun) $fatal(1,"Empty pop changed FIFO");
        for(i=0;i<DEPTH;i=i+1) begin push=1; data=i; @(negedge clk); end
        push=0;
        if(!full || head!==0) $fatal(1,"FIFO fill");
        // Full pop+push cùng cạnh phải giữ byte mới, không báo overflow.
        push=1; pop=1; data=8'hA5; @(negedge clk); push=0; pop=0;
        if(!full || overrun) $fatal(1,"Full simultaneous transfer lost byte");
        for(i=1;i<DEPTH;i=i+1) begin
            if(head!==i[7:0]) $fatal(1,"FIFO order");
            pop=1; @(negedge clk); pop=0;
        end
        if(head!==8'hA5) $fatal(1,"FIFO simultaneous push missing");
        pop=1; @(negedge clk); pop=0;
        if(!empty) $fatal(1,"FIFO drain");
        // Empty push+pop không tiêu thụ byte chưa tồn tại trước cạnh.
        push=1; pop=1; data=8'h5A; @(negedge clk); push=0; pop=0;
        if(empty || head!==8'h5A) $fatal(1,"FIFO empty simultaneous behavior");
        rst=1; @(negedge clk);
        if(!empty || overrun) $fatal(1,"FIFO reset");
        $display("PASS tb_rv32_uart_rx_fifo: depth=%0d full/empty simultaneous push/pop",DEPTH);
        $finish;
    end
endmodule
`default_nettype wire
