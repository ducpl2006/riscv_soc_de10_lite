`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : uart_loopback_top
// Chức năng : Top-level kiểm tra UART loopback trên DE10-Lite.
//
// LUỒNG DỮ LIỆU:
//   GPIO_UART_RX -> UART RX -> ready/valid -> UART TX -> GPIO_UART_TX
//
// ĐẶC TẢ:
//   - CLOCK_50 là clock hệ thống; KEY[0] là reset thô tích cực thấp.
//   - Mặc định UART 115200 8N1, RX oversampling 16 lần.
//   - uart_top cung cấp FIFO TX/RX độc lập, cùng độ sâu FIFO_DEPTH.
//   - Frame hợp lệ được đưa vào TX FIFO để phát lại.
//   - Frame có framing_error được lấy khỏi FIFO ngay nhưng không phát lại.
//   - LEDR[0]: TX đang bận hoặc còn byte chờ.
//   - LEDR[1]: RX FIFO đang có byte.
//   - LEDR[2]: cờ framing error giữ dính, xóa khi reset.
//   - LEDR[3]: cờ receive overrun giữ dính, xóa khi reset.
//   - LEDR[9:4]=0; KEY[1] chưa sử dụng.
//
// RÀNG BUỘC PHẦN CỨNG:
//   - GPIO UART phải dùng mức logic 3,3 V và chung mass với FPGA.
//   - Chân vật lý được chọn trong quartus/pins.qsf, không được suy đoán.
// ============================================================================
module uart_loopback_top #(
    parameter integer CLOCK_FREQ = 50_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16,
    parameter integer FIFO_DEPTH = 16
) (
    // Clock 50 MHz tren DE10-Lite.
    input  wire       CLOCK_50,

    // Hai nut nhan cua DE10-Lite.
    // KEY[0] duoc su dung lam reset active-low.
    input  wire [1:0] KEY,

    // Hai chan UART se duoc gan vao GPIO.
    input  wire       GPIO_UART_RX,
    output wire       GPIO_UART_TX,

    // LED hien thi trang thai.
    output wire [9:0] LEDR
);

    wire rst_n;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;

    wire       rx_framing_error;
    wire       rx_overrun_error;

    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;
    wire       tx_busy;

    reg framing_error_latched;
    reg overrun_error_latched;

    // ------------------------------------------------------------------------
    // Bộ đồng bộ reset.
    // ------------------------------------------------------------------------
    reset_sync u_reset_sync (
        .clk    (CLOCK_50),
        .arst_n (KEY[0]),
        .rst_n  (rst_n)
    );

    // ------------------------------------------------------------------------
    // Ket noi ready/valid tu RX sang TX
    // ------------------------------------------------------------------------

    // Chi truyen lai frame khong co framing error.
    assign tx_data  = rx_data;

    assign tx_valid =
        rx_valid && !rx_framing_error;

    // Frame loi duoc consume ngay nhung khong gui sang TX.
    assign rx_ready =
        (rx_valid && rx_framing_error) ? 1'b1 : tx_ready;

    // ------------------------------------------------------------------------
    // Core UART tái sử dụng với FIFO RX/TX độc lập.
    // ------------------------------------------------------------------------
    uart_top #(
        .CLOCK_FREQ    (CLOCK_FREQ),
        .BAUD_RATE     (BAUD_RATE),
        .OVERSAMPLE    (OVERSAMPLE),
        .TX_FIFO_DEPTH (FIFO_DEPTH),
        .RX_FIFO_DEPTH (FIFO_DEPTH)
    ) u_uart_top (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .uart_rx_i         (GPIO_UART_RX),
        .uart_tx_o         (GPIO_UART_TX),
        .tx_data           (tx_data),
        .tx_valid          (tx_valid),
        .tx_ready          (tx_ready),
        .rx_data           (rx_data),
        .rx_valid          (rx_valid),
        .rx_ready          (rx_ready),
        .rx_framing_error  (rx_framing_error),
        .tx_busy           (tx_busy),
        .tx_done           (),
        .rx_overrun_error  (rx_overrun_error)
    );

    // ------------------------------------------------------------------------
    // Các cờ lỗi giữ dính đến lần reset tiếp theo.
    //
    // Cac event loi chi co the keo dai mot vai clock va khong the nhin thay
    // truc tiep tren LED. Do do, loi duoc luu lai cho den lan reset tiep theo.
    // ------------------------------------------------------------------------
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            framing_error_latched <= 1'b0;
            overrun_error_latched <= 1'b0;
        end else begin
            if (rx_valid && rx_framing_error) begin
                framing_error_latched <= 1'b1;
            end

            if (rx_overrun_error) begin
                overrun_error_latched <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Trạng thái LED.
    // ------------------------------------------------------------------------

    // LEDR[0]: TX dang truyen.
    assign LEDR[0] = tx_busy;

    // LEDR[1]: RX dang giu mot byte hop le.
    assign LEDR[1] = rx_valid;

    // LEDR[2]: Da tung xay ra framing error.
    assign LEDR[2] = framing_error_latched;

    // LEDR[3]: Da tung xay ra receive overrun.
    assign LEDR[3] = overrun_error_latched;

    // Cac LED chua su dung.
    assign LEDR[9:4] = 6'b000000;

endmodule

`default_nettype wire
