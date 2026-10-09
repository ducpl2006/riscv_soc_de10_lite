// =============================================================
// Module VGA_RAM (DEBUG VERSION)
// -------------------------------------------------------------
// SINGLE BUFFER MODE
// + CPU ghi đâu VGA đọc đó
// + Xác minh CPU -> MMIO -> RAM -> VGA_Text
//
// 80 x 30 = 2400 cells
// mỗi cell = 16-bit
//
// [15:12] FG
// [11:8]  BG
// [7:0]   ASCII
// =============================================================

module VGA_RAM (

    // ================= CPU PORT =================
    input clk_cpu,
    input we_cpu,
    input [11:0] addr_cpu,
    input [15:0] data_in_cpu,

    // ================= VGA PORT =================
    input clk_vga,
    input [11:0] addr_vga,
    output reg [15:0] data_out_vga,

    // giữ chân để tương thích top-level
    input buffer_sel
);

    // =========================================================
    // 2400 words x 16-bit
    // =========================================================
    (* ramstyle = "M9K" *)
    reg [15:0] mem [0:2399];

    // =========================================================
    // Reset VGA_RAM
    // =========================================================
    integer i;

    initial begin
        for(i = 0; i < 2400; i = i + 1)
            mem[i] = 16'h0000;
    end

    // =========================================================
    // CPU WRITE
    // =========================================================
    always @(posedge clk_cpu) begin
        if (we_cpu) begin
            if (addr_cpu < 12'd2400)
                mem[addr_cpu] <= data_in_cpu;
        end
    end

    // =========================================================
    // VGA READ (sync read)
    // =========================================================
    always @(posedge clk_vga) begin
        if (addr_vga < 12'd2400)
            data_out_vga <= mem[addr_vga];
        else
            data_out_vga <= 16'h0000;
    end

endmodule