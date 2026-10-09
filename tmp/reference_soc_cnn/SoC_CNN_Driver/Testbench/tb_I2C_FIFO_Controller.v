`timescale 1ns/1ps
// ============================================================================
// tb_I2C_FIFO_Controller
// Kiểm tra: push/pop, empty/full, level, threshold IRQ, flush.
// ============================================================================
module tb_I2C_FIFO_Controller;

    localparam TXW = 12, RXW = 8, DEPTH = 16;

    reg              clk = 0;
    reg              reset;
    reg              tx_flush, rx_flush;
    reg              tx_push, tx_pop;
    reg  [TXW-1:0]   tx_wdata;
    wire [TXW-1:0]   tx_rdata;
    wire             tx_empty, tx_full;
    reg              rx_push, rx_pop;
    reg  [RXW-1:0]   rx_wdata;
    wire [RXW-1:0]   rx_rdata;
    wire             rx_empty, rx_full;
    wire [7:0]       tx_level, rx_level;
    reg  [7:0]       tx_thres, rx_thres;
    wire             tx_thres_irq, rx_thres_irq;

    integer errors = 0;
    integer i;

    always #5 clk = ~clk;

    I2C_FIFO_Controller #(.TX_WIDTH(TXW), .RX_WIDTH(RXW), .DEPTH(DEPTH)) dut (
        .clk(clk), .reset(reset), .tx_flush(tx_flush), .rx_flush(rx_flush),
        .tx_push(tx_push), .tx_wdata(tx_wdata), .tx_pop(tx_pop),
        .tx_rdata(tx_rdata), .tx_empty(tx_empty), .tx_full(tx_full),
        .rx_push(rx_push), .rx_wdata(rx_wdata), .rx_pop(rx_pop),
        .rx_rdata(rx_rdata), .rx_empty(rx_empty), .rx_full(rx_full),
        .tx_level(tx_level), .rx_level(rx_level),
        .tx_thres(tx_thres), .rx_thres(rx_thres),
        .tx_thres_irq(tx_thres_irq), .rx_thres_irq(rx_thres_irq)
    );

    task chk; input [31:0] val, exp; input [8*28:1] name; begin
        if (val !== exp) begin
            $display("  [ERR] %0s = %0d, expect %0d", name, val, exp);
            errors = errors + 1;
        end
    end endtask

    task tx_write; input [TXW-1:0] d; begin
        @(negedge clk); tx_push=1; tx_wdata=d; @(negedge clk); tx_push=0;
    end endtask
    task tx_read; begin
        @(negedge clk); tx_pop=1; @(negedge clk); tx_pop=0;
    end endtask

    initial begin
        reset=0; tx_flush=0; rx_flush=0;
        tx_push=0; tx_pop=0; tx_wdata=0;
        rx_push=0; rx_pop=0; rx_wdata=0;
        tx_thres=8'd2; rx_thres=8'd4;
        #12 reset=1; @(negedge clk);

        // empty ban đầu
        chk(tx_empty,1,"tx_empty init"); chk(tx_level,0,"tx_level init");
        chk(tx_thres_irq,1,"tx_thres_irq (level0<=2)");

        // push 4 entry 0x100,0x201,0x302,0x403
        tx_write(12'h100); tx_write(12'h201); tx_write(12'h302); tx_write(12'h403);
        chk(tx_level,4,"tx_level after 4 push"); chk(tx_empty,0,"tx_empty=0");
        chk(tx_thres_irq,0,"tx_thres_irq (4>2)");
        chk(tx_rdata,12'h100,"tx head show-first");

        // pop 2 -> head tiến
        tx_read(); chk(tx_rdata,12'h201,"head after pop1");
        tx_read(); chk(tx_rdata,12'h302,"head after pop2");
        chk(tx_level,2,"tx_level after 2 pop");
        chk(tx_thres_irq,1,"tx_thres_irq (2<=2)");

        // đổ đầy tới DEPTH
        for (i=0; i<20; i=i+1) tx_write(i[TXW-1:0]);   // thừa -> bị bỏ khi full
        chk(tx_full,1,"tx_full"); chk(tx_level,DEPTH,"tx_level=DEPTH");

        // flush TX
        @(negedge clk); tx_flush=1; @(negedge clk); tx_flush=0; @(negedge clk);
        chk(tx_empty,1,"tx_empty after flush"); chk(tx_level,0,"tx_level after flush");
        chk(tx_full,0,"tx_full=0 after flush");

        // ---- RX threshold ----
        chk(rx_thres_irq,0,"rx_thres_irq (0>=4 false)");
        @(negedge clk); rx_push=1; rx_wdata=8'hAA; @(negedge clk);
        rx_wdata=8'hBB; @(negedge clk); rx_wdata=8'hCC; @(negedge clk);
        rx_wdata=8'hDD; @(negedge clk); rx_push=0;
        chk(rx_level,4,"rx_level=4"); chk(rx_thres_irq,1,"rx_thres_irq (4>=4)");
        chk(rx_rdata,8'hAA,"rx head");

        if (errors==0) $display("PASS: I2C_FIFO_Controller");
        else           $display("FAIL: I2C_FIFO_Controller (%0d errors)", errors);
        $finish;
    end

endmodule
