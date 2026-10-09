`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : uart_top
// Chức năng : UART full-duplex tái sử dụng, có FIFO TX và RX độc lập.
//
// ĐẶC TẢ KHUNG UART:
//   - Nghỉ=1, bắt đầu=0, 8 bit dữ liệu LSB trước, không bit chẵn lẻ,
//     một bit dừng=1.
//   - TX và RX dùng chung clk nhưng vận hành độc lập, có thể chạy đồng thời.
//   - CLOCK_FREQ, BAUD_RATE và OVERSAMPLE phải thỏa ràng buộc của uart_tx,
//     uart_rx và uart_baud_gen.
//
// ĐẶC TẢ READY/VALID:
//   - Giao dịch chỉ xảy ra tại cạnh lên khi valid && ready.
//   - Phía cấp dữ liệu phải giữ valid và payload ổn định khi ready=0.
//   - tx_ready cho biết TX FIFO còn chỗ, không phải bộ phát đang nghỉ.
//   - rx_valid cho biết đầu RX FIFO có {rx_framing_error, rx_data} hợp lệ.
//
// ĐẶC TẢ BUFFER VÀ LỖI:
//   - TX_FIFO_DEPTH, RX_FIFO_DEPTH >= 1 và không cần là lũy thừa của hai.
//   - framing_error được lưu cùng byte trong RX FIFO nên thông tin lỗi không lệch.
//   - rx_overrun_error phát xung một clock khi uart_rx phải loại frame mới nhất.
//   - tx_busy=1 nếu bộ phát đang chạy hoặc TX FIFO vẫn còn byte.
//   - tx_done phát xung một clock sau bit dừng của mỗi byte đã phát xong.
//
// ĐẶC TẢ RESET:
//   - rst_n tích cực thấp và phải được nhả đồng bộ với clk.
//   - Dùng reset_sync nếu nguồn reset của bo mạch là bất đồng bộ.
//   - Trong reset, các tín hiệu ready/valid đều bằng 0, uart_tx_o ở mức 1.
// ============================================================================
module uart_top #(
    parameter integer CLOCK_FREQ    = 50_000_000,
    parameter integer BAUD_RATE     = 115_200,
    parameter integer OVERSAMPLE    = 16,
    parameter integer TX_FIFO_DEPTH = 16,
    parameter integer RX_FIFO_DEPTH = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       uart_rx_i,
    output wire       uart_tx_o,

    // Luồng phát: logic ứng dụng -> UART.
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,

    // Luồng nhận: UART -> logic ứng dụng.
    output wire [7:0] rx_data,
    output wire       rx_valid,
    input  wire       rx_ready,
    output wire       rx_framing_error,

    // Tín hiệu trạng thái/sự kiện.
    // tx_busy bao gồm cả byte đang chờ và byte đang phát trên dây.
    output wire       tx_busy,
    // tx_done là xung một clk sau khi phát xong bit dừng.
    output wire       tx_done,
    // rx_overrun_error là xung một clk khi frame mới nhất bị loại.
    output wire       rx_overrun_error
);

    wire [7:0] tx_fifo_data;
    wire       tx_fifo_valid;
    wire       tx_fifo_ready;

    wire       tx_core_busy;

    wire [7:0] rx_core_data;
    wire       rx_core_valid;
    wire       rx_core_ready;
    wire       rx_core_framing_error;

    wire [8:0] rx_fifo_data;

    // ------------------------------------------------------------------------
    // Hàng đợi phát và bộ tuần tự hóa.
    // ------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH (8),
        .DEPTH      (TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .write_data  (tx_data),
        .write_valid (tx_valid),
        .write_ready (tx_ready),
        .read_data   (tx_fifo_data),
        .read_valid  (tx_fifo_valid),
        .read_ready  (tx_fifo_ready),
        .full        (),
        .empty       ()
    );

    uart_tx #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_data   (tx_fifo_data),
        .tx_valid  (tx_fifo_valid),
        .tx_ready  (tx_fifo_ready),
        .uart_tx_o (uart_tx_o),
        .tx_busy   (tx_core_busy),
        .tx_done   (tx_done)
    );

    assign tx_busy = tx_core_busy || tx_fifo_valid;

    // ------------------------------------------------------------------------
    // Bộ nhận và hàng đợi nhận.
    //
    // Bit framing_error được xếp hàng cùng byte để luôn thẳng hàng với dữ liệu,
    // kể cả khi logic ứng dụng tạo áp lực ngược.
    // ------------------------------------------------------------------------
    uart_rx #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx_i     (uart_rx_i),
        .rx_data       (rx_core_data),
        .rx_valid      (rx_core_valid),
        .rx_ready      (rx_core_ready),
        .framing_error (rx_core_framing_error),
        .overrun_error (rx_overrun_error)
    );

    sync_fifo #(
        .DATA_WIDTH (9),
        .DEPTH      (RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .write_data  ({rx_core_framing_error, rx_core_data}),
        .write_valid (rx_core_valid),
        .write_ready (rx_core_ready),
        .read_data   (rx_fifo_data),
        .read_valid  (rx_valid),
        .read_ready  (rx_ready),
        .full        (),
        .empty       ()
    );

    assign rx_data          = rx_fifo_data[7:0];
    assign rx_framing_error = rx_fifo_data[8];

    // Ready/valid là giao diện điều khiển luồng chính thức; các cổng full/empty dư
    // thừa của FIFO được chủ ý để hở.

endmodule

`default_nettype wire
