// =============================================================
// Module VGA CONTROL REGISTER
// + Thanh ghi điều khiển VGA dạng Memory Mapping I/O
// + Điều khiển:
//     * Vị trí Cursor (Cursor blink giống terminal)
//     * Scroll màn hình
//     * Select buffer (double buffer)
//
// -------------------------------------------------------------
// Kiến trúc pending / active (vsync-synchronized):
// + CPU ghi vào pending registers bất kỳ lúc nào
// + Active registers chỉ được cập nhật tại vsync boundary
// --> Đảm bảo buffer swap không gây tearing
// --> Đảm bảo cursor/scroll ổn định trong suốt 1 frame
// =============================================================

module VGA_CTRL_REG (

    input clk_cpu,                  // Clock 50MHz
    input reset,
    input we,                       // CPU ghi đúng địa chỉ MMIO --> we = 1
    input [31:0] data_in,           // Word 32-bit từ CPU

    input vsync,                    // Từ VGA_Control, active-low

    output reg [6:0] cursor_x,      // Vị trí cột cursor  (active, stable trong frame)
    output reg [4:0] cursor_y,      // Vị trí hàng cursor (active, stable trong frame)
    output reg [4:0] row_offset,    // Scroll hardware     (active, stable trong frame)
    output reg       buffer_sel     // Double buffer select (active, stable trong frame)
);

    // =============== 2-FF SYNC: vsync (VGA domain) → CPU domain ===============
    reg vsync_s1, vsync_s2, vsync_s3;
    always @(posedge clk_cpu) begin
        vsync_s1 <= vsync;
        vsync_s2 <= vsync_s1;
        vsync_s3 <= vsync_s2;
    end

    // Falling edge vsync = bắt đầu vsync pulse = frame boundary an toàn
    wire vsync_fall_cpu = vsync_s3 & ~vsync_s2;

    // =============== PENDING REGISTERS (CPU domain — ghi bất kỳ lúc nào) ===============
    reg [6:0] pend_cursor_x;
    reg [4:0] pend_cursor_y;
    reg [4:0] pend_row_offset;
    reg       pend_buffer_sel;

    always @(posedge clk_cpu) begin
        if (!reset) begin
            pend_cursor_x   <= 7'd0;
            pend_cursor_y   <= 5'd0;
            pend_row_offset <= 5'd0;
            pend_buffer_sel <= 1'b0;
        end
        else if (we) begin
            pend_cursor_x   <= data_in[6:0];
            pend_cursor_y   <= data_in[11:7];
            pend_row_offset <= data_in[16:12];
            pend_buffer_sel <= data_in[17];
        end
    end

    // =============== ACTIVE REGISTERS (apply tại vsync boundary + bounds clamp) ===============
    always @(posedge clk_cpu) begin
        if (!reset) begin
            cursor_x   <= 7'd0;
            cursor_y   <= 5'd0;
            row_offset <= 5'd0;
            buffer_sel <= 1'b0;
        end
        else if (vsync_fall_cpu) begin
            cursor_x   <= (pend_cursor_x   < 7'd80) ? pend_cursor_x   : 7'd79;
            cursor_y   <= (pend_cursor_y   < 5'd30) ? pend_cursor_y   : 5'd29;
            row_offset <= (pend_row_offset < 5'd30) ? pend_row_offset : 5'd29;
            buffer_sel <= pend_buffer_sel;
        end
    end

endmodule
