// =====================================================
// Module Baud Generator
// + Module lấy mẫu bit cho UART
// + Lấy mẫu 16 lần (oversample = 16)
// + Hạ thấp tần số của clock hệ thống
// =====================================================

module Baud_Gen #(

    parameter integer CLK_SYS       = 50_000_000,       // Tần số hệ thống là 50MHz
    parameter integer BAUD_RATE     = 9600,             
    parameter integer OVERSAMPLE    = 16                // Số lần lấy mẫu bit
)
(
    input clk,
    input reset,

    output reg baud_tick        // Xung kích hoạt UART (Tín hiệu enable để UART bắt đầu đếm lấy mẫu)
);

    // ================================================
    // Baud Rate divider
    // + Số chu kỳ clock hệ thống tạo ra 1 baud_tick
    // ================================================
    localparam integer BAUD_DIV = CLK_SYS / (BAUD_RATE * OVERSAMPLE);

    // ================================================
    // Counter width: Số bit của thanh ghi đếm
    // + Đếm số chu kỳ clock
    // ================================================
    localparam integer CNT_W    = (BAUD_DIV - 1) ? $clog2(BAUD_DIV) : 1;

    // Counter
    reg [CNT_W - 1:0] count;

    // =============== Baud Tick ===============
    always @(posedge clk) begin
        
        if (!reset) begin
            count       <= {CNT_W{1'b0}};
            baud_tick   <= 1'b0;
        end

        else begin
            if (count == BAUD_DIV - 1) begin
                count       <= {CNT_W{1'b0}};
                baud_tick   <= 1'b1;
            end

            else begin
                count       <= count + 1'b1;
                baud_tick   <= 1'b0;
            end 
        end

    end

endmodule