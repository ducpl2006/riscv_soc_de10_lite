`timescale 1ns/1ps
// ============================================================================
// tb_I2C_IRQ_Status — sticky set, mask->irq, W1C clear, set thắng clear.
// ============================================================================
module tb_I2C_IRQ_Status;

    reg         clk = 0;
    reg         reset;
    reg  [7:0]  int_set, int_clr, int_enable;
    reg  [4:0]  err_set, err_clr;
    wire [7:0]  int_status;
    wire [4:0]  err_status;
    wire        irq;

    integer errors = 0;

    always #5 clk = ~clk;

    I2C_IRQ_Status dut (.clk(clk), .reset(reset),
        .int_set(int_set), .err_set(err_set),
        .int_clr(int_clr), .err_clr(err_clr), .int_enable(int_enable),
        .int_status(int_status), .err_status(err_status), .irq(irq));

    task pulse_int_set; input [7:0] b; begin
        @(negedge clk); int_set=b; @(negedge clk); int_set=0;
    end endtask

    initial begin
        reset=0; int_set=0; int_clr=0; int_enable=0; err_set=0; err_clr=0;
        #12 reset=1; @(negedge clk);

        // set NACK(bit2) + STOP(bit7) -> sticky
        pulse_int_set(8'b1000_0100);
        if (int_status !== 8'b1000_0100) begin $display("  [ERR] int_status=%b expect 84", int_status); errors=errors+1; end

        // mask off -> irq=0
        @(negedge clk); int_enable=8'h00; @(negedge clk);
        if (irq !== 1'b0) begin $display("  [ERR] irq=%b expect 0 (masked)", irq); errors=errors+1; end
        // enable NACK -> irq=1
        @(negedge clk); int_enable=8'b0000_0100; @(negedge clk);
        if (irq !== 1'b1) begin $display("  [ERR] irq=%b expect 1 (NACK en)", irq); errors=errors+1; end

        // W1C clear NACK -> con STOP
        @(negedge clk); int_clr=8'b0000_0100; @(negedge clk); int_clr=0; @(negedge clk);
        if (int_status !== 8'b1000_0000) begin $display("  [ERR] int_status=%b expect 80 after clr", int_status); errors=errors+1; end
        if (irq !== 1'b0) begin $display("  [ERR] irq=%b expect 0 after clr NACK", irq); errors=errors+1; end

        // set thắng clear cùng chu kỳ (bit0)
        @(negedge clk); int_set=8'b0000_0001; int_clr=8'b0000_0001; @(negedge clk); int_set=0; int_clr=0; @(negedge clk);
        if (int_status[0] !== 1'b1) begin $display("  [ERR] set khong thang clear (bit0=%b)", int_status[0]); errors=errors+1; end

        // ERROR sticky + clear
        @(negedge clk); err_set=5'b10001; @(negedge clk); err_set=0; @(negedge clk);
        if (err_status !== 5'b10001) begin $display("  [ERR] err_status=%b expect 11", err_status); errors=errors+1; end
        @(negedge clk); err_clr=5'b00001; @(negedge clk); err_clr=0; @(negedge clk);
        if (err_status !== 5'b10000) begin $display("  [ERR] err_status=%b expect 10 after clr", err_status); errors=errors+1; end

        if (errors==0) $display("PASS: I2C_IRQ_Status");
        else           $display("FAIL: I2C_IRQ_Status (%0d errors)", errors);
        $finish;
    end

endmodule
