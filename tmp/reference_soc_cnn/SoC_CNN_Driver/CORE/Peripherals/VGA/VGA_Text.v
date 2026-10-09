// ============================================================
// Module VGA_Text (Production-grade rewrite)
//
// Pipeline 4-stage — tổng latency = 4 clock VGA:
//   Stage 1  (T+0): text_addr → VGA_RAM, x/y/col/row/video propagate
//   Stage 1b (T+1): chờ VGA_RAM registered output (1 cycle), propagate
//   Stage 2  (T+2): text_data valid → capture + font_addr → Font_ROM
//   Stage 2b (T+3): chờ Font_ROM registered output (1 cycle), propagate
//   Output   (T+4): font_data valid → RGB
//
// Tất cả nhánh pipeline có độ trễ bằng nhau → không lệch pixel
// ============================================================

module VGA_Text (

    input clk_vga,
    input reset,

    input video_on,
    input [9:0] x,
    input [9:0] y,

    // VGA RAM
    input  [15:0] text_data,
    output reg [11:0] text_addr,

    // FONT ROM
    input  [7:0]  font_data,
    output reg [11:0] font_addr,

    // VGA CONTROL REGISTER (CPU domain — cần 2-FF sync)
    input [6:0] cursor_x,
    input [4:0] cursor_y,
    input [4:0] row_offset,

    output reg [3:0] R,
    output reg [3:0] G,
    output reg [3:0] B
);

    // =============== CDC: cursor (CPU 50MHz → VGA 25MHz) ===============
    reg [6:0] cursor_x_s1, cursor_x_vga;
    reg [4:0] cursor_y_s1, cursor_y_vga;

    always @(posedge clk_vga) begin
        cursor_x_s1  <= cursor_x;     
        cursor_x_vga <= cursor_x_s1;

        cursor_y_s1  <= cursor_y;     
        cursor_y_vga <= cursor_y_s1;
    end

    // =============== STAGE 0: COMBINATIONAL ===============
    wire [6:0] col     = x[9:3];
    wire [4:0] row_raw = y[8:4];

    // 6-bit tránh overflow khi row_raw + row_offset > 31
    wire [5:0] row_sum  = {1'b0, row_raw} + {1'b0, row_offset};
    wire [4:0] row_wrap = (row_sum >= 6'd30) ? (row_sum - 6'd30) : row_sum[4:0];

    // row * 80 = row * (64 + 16)
    wire [11:0] row_base       = (row_wrap << 6) + (row_wrap << 4);
    wire [11:0] text_addr_next = row_base + {5'b0, col};

    // =============== STAGE 1: text_addr → VGA_RAM ===============
    reg [2:0] x_s1;
    reg [3:0] y_s1;
    reg [6:0] col_s1;
    reg [4:0] row_s1;
    reg       video_on_s1;

    always @(posedge clk_vga) begin
        if (!reset) begin
            text_addr   <= 0;
            x_s1        <= 0;
            y_s1        <= 0;
            col_s1      <= 0;
            row_s1      <= 0;
            video_on_s1 <= 0;
        end
        else begin
            text_addr   <= text_addr_next;
            x_s1        <= x[2:0];
            y_s1        <= y[3:0];
            col_s1      <= col;
            row_s1      <= row_wrap;
            video_on_s1 <= video_on;
        end
    end

    // =============== STAGE 1b: chờ VGA_RAM registered output ===============
    reg [2:0] x_s1b;
    reg [3:0] y_s1b;
    reg [6:0] col_s1b;
    reg [4:0] row_s1b;
    reg       video_on_s1b;

    always @(posedge clk_vga) begin
        if (!reset) begin
            x_s1b        <= 0;
            y_s1b        <= 0;
            col_s1b      <= 0;
            row_s1b      <= 0;
            video_on_s1b <= 0;
        end
        else begin
            x_s1b        <= x_s1;
            y_s1b        <= y_s1;
            col_s1b      <= col_s1;
            row_s1b      <= row_s1;
            video_on_s1b <= video_on_s1;
        end
    end

    // =============== STAGE 2: text_data valid → capture + font_addr → Font_ROM ===============
    // text_data là registered output của VGA_RAM, valid từ sau posedge Stage 1b
    reg [2:0]  x_s2;
    reg [6:0]  col_s2;
    reg [4:0]  row_s2;
    reg        video_on_s2;
    reg [15:0] text_s2;

    always @(posedge clk_vga) begin
        if (!reset) begin
            font_addr   <= 0;
            x_s2        <= 0;
            col_s2      <= 0;
            row_s2      <= 0;
            video_on_s2 <= 0;
            text_s2     <= 0;
        end
        else begin
            font_addr   <= {text_data[7:0], y_s1b};  // char_code * 16 + pixel_row ✓
            x_s2        <= x_s1b;
            col_s2      <= col_s1b;
            row_s2      <= row_s1b;
            video_on_s2 <= video_on_s1b;
            text_s2     <= text_data;                 // valid tại đây ✓
        end
    end

    // =============== STAGE 2b: chờ Font_ROM registered output ===============
    reg [2:0]  x_s2b;
    reg [6:0]  col_s2b;
    reg [4:0]  row_s2b;
    reg        video_on_s2b;
    reg [15:0] text_s2b;

    always @(posedge clk_vga) begin
        if (!reset) begin
            x_s2b        <= 0;
            col_s2b      <= 0;
            row_s2b      <= 0;
            video_on_s2b <= 0;
            text_s2b     <= 0;
        end
        else begin
            x_s2b        <= x_s2;
            col_s2b      <= col_s2;
            row_s2b      <= row_s2;
            video_on_s2b <= video_on_s2;
            text_s2b     <= text_s2;
        end
    end

    // =============== CURSOR BLINK (~1.5Hz @ 25MHz) ===============
    reg [23:0] blink_cnt;
    reg        blink;

    always @(posedge clk_vga) begin
        if (!reset) begin
            blink_cnt <= 0;
            blink     <= 0;
        end
        else begin
            blink_cnt <= blink_cnt + 1'b1;
            blink     <= blink_cnt[23];
        end
    end

    // =============== OUTPUT: font_data valid → RGB ===============
    // font_data là registered output của Font_ROM, valid từ sau posedge Stage 2b
    wire pixel       = font_data[7 - x_s2b];
    wire cursor_hit  = (col_s2b == cursor_x_vga) && (row_s2b == cursor_y_vga);
    wire pixel_final = (cursor_hit && blink) ? ~pixel : pixel;

    wire [3:0] bg = text_s2b[15:12];
    wire [3:0] fg = text_s2b[11:8];

    wire [3:0] color_sel;

    assign color_sel = pixel_final ? fg : bg;

    wire [3:0] r_val = color_sel[2] ? (color_sel[3] ? 4'hF : 4'h8) : 4'h0;
    wire [3:0] g_val = color_sel[1] ? (color_sel[3] ? 4'hF : 4'h8) : 4'h0;
    wire [3:0] b_val = color_sel[0] ? (color_sel[3] ? 4'hF : 4'h8) : 4'h0;

    always @(posedge clk_vga) begin
        if (!reset) begin
            R <= 0;
            G <= 0;
            B <= 0;
        end
        else begin
            if (video_on_s2b) begin
                R <= r_val;
                G <= g_val;
                B <= b_val;
            end
            else begin
                R <= 0;
                G <= 0;
                B <= 0;
            end
        end
    end

endmodule
