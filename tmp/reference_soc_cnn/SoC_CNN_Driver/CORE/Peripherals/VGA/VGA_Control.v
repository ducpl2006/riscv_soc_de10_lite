// =============================================================
// Module VGA_Control
// + Điều khiển các tín hiệu xuất hình ảnh VGA
// =============================================================

module VGA_Control (

    input clk_vga,             // Clock VGA (clk_vga) 25MHz
    input reset,

    output reg hsync,          // Tín hiệu báo hết một dòng của màn hình (Quay về vị trí đầu tiên của dòng tiếp theo)
    output reg vsync,          // Tín hiệu báo truyền hết một farme, quay về vị trí (0, 0)
    output reg video_on,       // Tín hiệu báo đang trong vùng hiển thị hình ảnh

    output reg [9:0] x,        // Vị trí pixel theo hàng ngang
    output reg [9:0] y         // Vị trí pixel theo hàng dọc
);

    // =====================================
    // Kích thước một farme màn hình
    // + Kích thước màn hình: 640 x 480
    // + Tần số quét: 60Hz
    // =====================================

    parameter H_VISIBLE = 640;
    parameter H_FRONT   = 16;
    parameter H_SYNC    = 96;
    parameter H_BACK    = 48;
    parameter H_TOTAL   = 800;

    parameter V_VISIBLE = 480;
    parameter V_FRONT   = 10;
    parameter V_SYNC    = 2;
    parameter V_BACK    = 33;
    parameter V_TOTAL   = 525;

    // =============== COUNTER PIXEL ===============

    always @(posedge clk_vga) begin
        
        if (!reset) begin
            x <= 0;
            y <= 0;
        end

        else begin
            // Horizonal counter
            if (x == H_TOTAL - 1) begin
                x <= 0;

                // Verical counter
                if (y == V_TOTAL - 1) begin
                    y <= 0;
                end
                else begin
                    y <= y + 1;
                end
            end
            else begin
                x <= x + 1;
            end
        end

    end

    // =============== HSYNC ACTIVE LOW ===============
    always @(posedge clk_vga) begin
        if (!reset)
            hsync <= 1'b1;
        else
            hsync <= ~(x >= (H_VISIBLE + H_FRONT) &&
                       x <  (H_VISIBLE + H_FRONT + H_SYNC));
    end

    // =============== VSYNC ACTIVE LOW ===============
    always @(posedge clk_vga) begin
        if (!reset)
            vsync <= 1'b1;
        else
            vsync <= ~(y >= (V_VISIBLE + V_FRONT) &&
                       y <  (V_VISIBLE + V_FRONT + V_SYNC));
    end

    // =============== VIDEO ON (registered — align với hsync/vsync pipeline) ===============
    always @(posedge clk_vga) begin
        if (!reset)
            video_on <= 1'b0;
        else
            video_on <= (x < H_VISIBLE) && (y < V_VISIBLE);
    end

endmodule