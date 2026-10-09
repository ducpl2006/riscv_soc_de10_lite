// =====================================================
// Module Font_ROM
// + Bộ Font ASCII cho VGA
// + Kích thước font chữ 8x16 pixel
// -----------------------------------------------------
// + 640 / 8 = 80 cột
// + 480 / 16 = 30 hàng
// ==> Màn hình hiển thị được 30 hàng, 80 ký tự/hàng
// =====================================================

module Font_ROM (

    input clk_vga,              // Clock 25MHz
    input [11:0] addr,

    output reg [7:0] data
);

    (* ramstyle = "M9K" *)
    reg [7:0] rom [0:4095];

    initial begin
        $readmemh("font8x16.hex", rom);
    end

    always @(posedge clk_vga) begin
        
        data <= rom[addr];

    end

endmodule