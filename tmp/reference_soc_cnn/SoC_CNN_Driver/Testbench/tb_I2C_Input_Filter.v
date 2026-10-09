`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Input_Filter
// Kiểm tra: đồng bộ 2-FF, nuốt glitch ngắn (< SPIKE_LEN), chấp nhận thay đổi
//           ổn định (>= SPIKE_LEN).
// ============================================================================
module tb_I2C_Input_Filter;

    localparam SYNC   = 2;
    localparam SPKLEN = 3;

    reg  clk = 0;
    reg  reset;
    reg  line_async;
    wire line_clean;

    integer errors = 0;

    I2C_Input_Filter #(.SYNC_STAGES(SYNC), .SPIKE_LEN(SPKLEN)) dut (
        .clk(clk), .reset(reset),
        .line_async(line_async), .line_clean(line_clean)
    );

    always #5 clk = ~clk;

    initial begin
        reset      = 0;
        line_async = 1'b1;          // idle high
        #23 reset  = 1;

        // Sau reset, line_clean phải = 1 (idle high)
        #20;
        if (line_clean !== 1'b1) begin
            $display("  [ERR] sau reset line_clean=%b, expect 1", line_clean);
            errors = errors + 1;
        end

        // ---- Glitch ngắn: kéo xuống 0 chỉ 2 chu kỳ (< SPIKE_LEN=3) ----
        @(negedge clk); line_async = 1'b0;
        repeat (2) @(negedge clk);
        line_async = 1'b1;          // trở lại high
        repeat (8) @(negedge clk);
        if (line_clean !== 1'b1) begin
            $display("  [ERR] glitch ngan (2 cyc) da lot qua filter (line_clean=%b)", line_clean);
            errors = errors + 1;
        end

        // ---- Thay đổi ổn định: kéo xuống 0 và giữ lâu ----
        @(negedge clk); line_async = 1'b0;
        repeat (10) @(negedge clk);
        if (line_clean !== 1'b0) begin
            $display("  [ERR] thay doi on dinh khong duoc chap nhan (line_clean=%b)", line_clean);
            errors = errors + 1;
        end

        // ---- Trở lại high ổn định ----
        @(negedge clk); line_async = 1'b1;
        repeat (10) @(negedge clk);
        if (line_clean !== 1'b1) begin
            $display("  [ERR] khong tro lai high (line_clean=%b)", line_clean);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: I2C_Input_Filter");
        else             $display("FAIL: I2C_Input_Filter (%0d errors)", errors);
        $finish;
    end

endmodule
