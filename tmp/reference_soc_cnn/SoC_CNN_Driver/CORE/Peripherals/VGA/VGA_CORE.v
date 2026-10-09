// ===========================================================
// Moduel VGA_CORE
// Intel MAX10 / DE10-Lite
//
// ----------------------------------------------------------
// Memory Map
// BASE = 0x3000_0000
// + 0x3000_0000 ~ 0x3000_257F -- Text RAM (2400 words x 16bit, 4-byte stride = 9600 bytes)
// + 0x3000_4000               -- VGA_CTRL
// + 0x3000_4004               -- VGA_STATUS
//
// ----------------------------------------------------------
// Full VGA Text Display Subsystem
// + PLL 50 MHz --> 25MHz
// + VGA timing 640x480@60Hz
// + Text mode 80x30
// + Font 8x16
// + Map Memory I/O Control Register
//
// -----------------------------------------------------------
// VGA OUTPUT
// + VGA_HS
// + VGA_VS
// + VGA_R
// + VGA_G
// + VGA_B
// ===========================================================

module VGA_CORE (

    input clk_cpu,
    input reset,
    
    // ======================================================
    // REGISTER INTERFACE
    // ======================================================

    // ----------------------------
    // TEXT RAM CPU PORT
    // ----------------------------
    input         text_we,
    input [11:0]  text_addr_cpu,
    input [15:0]  text_data_cpu,

    // ----------------------------
    // CONTROL REGISTER
    // ----------------------------
    input         ctrl_we,
    input [31:0]  ctrl_data,

    // ----------------------------
    // READBACK
    // ----------------------------
    output [31:0] ctrl_rd_data,
    output [31:0] stat_rd_data,

    // ======================================================
    // VGA OUTPUT
    // ======================================================
    output VGA_HS,
    output VGA_VS,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B
);

    // =============== PLL 50MHz --> 25MHz ===============
    wire clk_vga;
    wire pll_locked;

    pll u_pll (
        
        // Input
        .areset     (~reset),
        .inclk0     (clk_cpu),

        // Output 
        .c0         (clk_vga),
        .locked     (pll_locked)
    );

    wire reset_sys = reset & pll_locked;

    // =============== VGA CONTROL TIMING ===============
    wire [9:0] x;
    wire [9:0] y;
    
    wire video_on;
    wire vsync_int;

    VGA_Control vga_control (

        // Input
        .clk_vga        (clk_vga),
        .reset          (reset_sys),

        // Output
        .hsync          (VGA_HS),
        .vsync          (vsync_int),

        .video_on       (video_on),
        .x              (x),
        .y              (y)
    );

    assign VGA_VS = vsync_int;

    // =============== CONTROL REGISTER ===============
    wire [6:0] cursor_x;
    wire [4:0] cursor_y;

    wire [4:0] row_offset;

    wire buffer_sel;

    VGA_CTRL_REG ctrl_reg (

        // Input
        .clk_cpu        (clk_cpu),
        .reset          (reset_sys),
        .we             (ctrl_we),
        .data_in        (ctrl_data),
        .vsync          (vsync_int),

        // Output
        .cursor_x       (cursor_x),
        .cursor_y       (cursor_y),
        .row_offset     (row_offset),
        .buffer_sel     (buffer_sel)
    );

    // =============== VGA RAM ===============
    wire [11:0] text_addr;
    wire [15:0] text_data;

    VGA_RAM vga_ram (

        // CPU PORT
        .clk_cpu        (clk_cpu),
        .we_cpu         (text_we),
        .addr_cpu       (text_addr_cpu),
        .data_in_cpu    (text_data_cpu),

        // VGA PORT
        .clk_vga        (clk_vga),
        .addr_vga       (text_addr),
        .data_out_vga   (text_data),

        .buffer_sel     (buffer_sel)
    );

    // =============== FONT ROM ===============
    wire [11:0] font_addr;
    wire [7:0] font_data;

    Font_ROM font (

        // Input
        .clk_vga        (clk_vga),
        .addr           (font_addr),

        // Output
        .data           (font_data)
    );

    // =============== VGA TEXT ===============
    VGA_Text vga_text (

        // Input
        .clk_vga        (clk_vga),
        .reset          (reset_sys),

        .video_on       (video_on),
        .x              (x),
        .y              (y),

        // VGA RAM
        .text_data      (text_data),
        .text_addr      (text_addr),

        // FONT ROM
        .font_data      (font_data),
        .font_addr      (font_addr),

        // VGA CONTROL REGISTER
        .cursor_x       (cursor_x),
        .cursor_y       (cursor_y),
        .row_offset     (row_offset),

        // Output
        .R              (VGA_R),
        .G              (VGA_G),
        .B              (VGA_B)
    );

    // ===========================================
    // READ BACK
    // + CPU đọc ngược lại trạng thái của VGA
    //  * VGA đang ở trạng thái gì ?
    //  * Cursor đang ở đâu ?
    //  * Buffer nào đang active
    //  * PLL lock chưa ?
    // ===========================================

    // ======================================================
    // READBACK : CONTROL REGISTER
    // ======================================================
    assign ctrl_rd_data = {14'd0, buffer_sel, row_offset, cursor_x, cursor_y};

    // ======================================================
    // READBACK : STATUS REGISTER
    // ======================================================
    assign stat_rd_data = {31'd0, pll_locked};

endmodule