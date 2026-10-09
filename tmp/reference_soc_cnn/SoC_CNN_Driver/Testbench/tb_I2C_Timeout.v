`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Timeout — SCL kẹt low quá timeout_val -> 1 xung; SCL cao -> reset;
// timeout_val=0 -> tắt.
// ============================================================================
module tb_I2C_Timeout;

    reg         clk = 0;
    reg         reset, core_en, scl_in;
    reg  [23:0] timeout_val;
    wire        timeout;

    integer errors = 0, fire_cnt = 0;

    always #5 clk = ~clk;

    I2C_Timeout dut (.clk(clk), .reset(reset), .core_en(core_en),
        .scl_in(scl_in), .timeout_val(timeout_val), .timeout(timeout));

    always @(posedge clk) if (timeout) fire_cnt = fire_cnt + 1;

    initial begin
        reset=0; core_en=0; scl_in=1; timeout_val=24'd10;
        #12 reset=1; @(negedge clk) core_en=1;

        // SCL low quá 10 chu kỳ -> fire đúng 1 lần
        fire_cnt=0;
        @(negedge clk); scl_in=0;
        repeat(20) @(negedge clk);
        if (fire_cnt !== 1) begin $display("  [ERR] fire_cnt=%0d expect 1 (stuck low)", fire_cnt); errors=errors+1; end

        // SCL cao -> reset; low lại -> fire lần nữa
        @(negedge clk); scl_in=1; repeat(3) @(negedge clk);
        fire_cnt=0;
        scl_in=0; repeat(20) @(negedge clk);
        if (fire_cnt !== 1) begin $display("  [ERR] fire_cnt=%0d expect 1 (re-arm)", fire_cnt); errors=errors+1; end

        // SCL toggle bình thường (low ngắn < 10) -> khong fire
        fire_cnt=0;
        repeat(8) begin @(negedge clk); scl_in=~scl_in; end
        if (fire_cnt !== 0) begin $display("  [ERR] fire_cnt=%0d expect 0 (toggle)", fire_cnt); errors=errors+1; end

        // timeout_val=0 -> tat
        scl_in=1; @(negedge clk); timeout_val=24'd0; @(negedge clk);
        fire_cnt=0; scl_in=0; repeat(30) @(negedge clk);
        if (fire_cnt !== 0) begin $display("  [ERR] fire_cnt=%0d expect 0 (disabled)", fire_cnt); errors=errors+1; end

        if (errors==0) $display("PASS: I2C_Timeout");
        else           $display("FAIL: I2C_Timeout (%0d errors)", errors);
        $finish;
    end

endmodule
