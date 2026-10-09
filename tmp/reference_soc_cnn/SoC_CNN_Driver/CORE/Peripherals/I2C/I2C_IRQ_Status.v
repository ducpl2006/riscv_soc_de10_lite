// ============================================================================
// Module I2C_IRQ_Status
// ----------------------------------------------------------------------------
// Gom INTERRUPT + ERROR sticky (mục H của plan). Thay cho Interrupt_Ctrl:
// STATUS (live) đọc thẳng từ Master; module này chỉ quản INT_STATUS và
// ERROR_STATUS (sticky, HW set / SW write-1-to-clear) + áp mask -> irq.
//
// INT_STATUS / INT_ENABLE bit (0x24 / 0x20):
//   0 TX_DONE  1 RX_DONE  2 NACK  3 ARB_LOST  4 TX_EMPTY  5 RX_FULL
//   6 TIMEOUT  7 STOP_DET
// ERROR_STATUS bit (0x34):
//   0 NACK_ADDR  1 NACK_DATA  2 ARB_LOST  3 SCL_TIMEOUT  4 SDA_STUCK
//
// Sticky: bit <= (bit & ~clr) | set. Set THẮNG clear cùng chu kỳ -> không mất
// sự kiện.
//
// Reset: active-low.
// ============================================================================
module I2C_IRQ_Status (
    input           clk,
    input           reset,          // active-low

    // HW set (pulse) từ các block
    input  [7:0]    int_set,
    input  [4:0]    err_set,

    // SW write-1-to-clear (pulse từ Register_IF)
    input  [7:0]    int_clr,
    input  [4:0]    err_clr,

    // mask
    input  [7:0]    int_enable,

    // giá trị đọc
    output [7:0]    int_status,
    output [4:0]    err_status,

    // ngắt tổng
    output          irq
);

    reg [7:0]   ints;
    reg [4:0]   errs;

    always @(posedge clk) begin
        if (!reset) begin
            ints <= 8'd0;
            errs <= 5'd0;
        end
        else begin
            ints <= (ints & ~int_clr) | int_set;   // set thắng clear
            errs <= (errs & ~err_clr) | err_set;
        end
    end

    assign int_status = ints;
    assign err_status = errs;
    assign irq        = |(ints & int_enable);

endmodule
