`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : uart_rx_sync
// Chức năng : Đồng bộ tín hiệu UART RX bất đồng bộ vào clock hệ thống.
//
// ĐẶC TẢ:
//   uart_rx_i -> sync_ff1 -> sync_ff2 -> uart_rx_sync_o
//
//   - Độ trễ danh định là hai cạnh lên của clk.
//   - Reset đặt cả hai tầng và đầu ra về 1, đúng mức idle của UART.
//   - rst_n phải được nhả đồng bộ với clk, ví dụ qua reset_sync.
//   - Module chỉ dành cho tín hiệu một bit; không dùng cấu trúc 2FF này để
//     đồng bộ một bus nhiều bit.
//   - Synchronizer giảm xác suất metastability truyền vào logic, không thể
//     loại bỏ metastability tuyệt đối.
//
// GIAO DIỆN:
//   uart_rx_i      : chân RX bất đồng bộ.
//   uart_rx_sync_o : RX đã đồng bộ, chỉ dùng trong miền clk.
// ============================================================================
module uart_rx_sync (
    input  wire clk,
    input  wire rst_n,

    input  wire uart_rx_i,

    output wire uart_rx_sync_o
);

/*    // Đánh dấu cả hai tầng để công cụ triển khai giữ và nhận diện đúng
    // chuỗi đồng bộ metastability. Quartus dùng altera_attribute; các công cụ
    // khác thường nhận ASYNC_REG.
`ifdef ALTERA_RESERVED_QIS
    (* altera_attribute =
           "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
`else
    (* ASYNC_REG = "TRUE" *)
`endif
    reg sync_ff1;

`ifdef ALTERA_RESERVED_QIS
    (* altera_attribute =
           "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
`else
    (* ASYNC_REG = "TRUE" *)
`endif
    reg sync_ff1;
    reg sync_ff2;
*/
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // UART ở trạng thái nghỉ mức cao.
            sync_ff1 <= 1'b1;
            sync_ff2 <= 1'b1;
        end else begin
            sync_ff1 <= uart_rx_i;
            sync_ff2 <= sync_ff1;
        end
    end

    assign uart_rx_sync_o = sync_ff2;

endmodule

`default_nettype wire
