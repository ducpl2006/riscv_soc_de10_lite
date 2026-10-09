`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : uart_tx
// Chức năng : Phát một byte theo chuẩn UART 8N1.
//
// ĐẶC TẢ KHUNG:
//   - Trạng thái nghỉ=1, một bit bắt đầu=0, 8 bit dữ liệu LSB trước,
//     không bit chẵn lẻ, một bit dừng=1.
//   - Mỗi ký hiệu dài floor(CLOCK_FREQ / BAUD_RATE) chu kỳ clk.
//   - uart_tx_o được đăng ký, chỉ đổi tại cạnh lên clk và không có glitch tổ hợp.
//
// ĐẶC TẢ READY/VALID:
//   - Byte được chấp nhận tại cạnh lên khi tx_valid && tx_ready.
//   - Phía cấp dữ liệu phải giữ tx_valid và tx_data ổn định khi tx_ready=0.
//   - Module không có FIFO nội bộ; chỉ lưu đúng byte đang phát.
//   - tx_ready=1 duy nhất khi IDLE và không reset.
//
// ĐẶC TẢ TRẠNG THÁI:
//   - tx_busy=1 từ sau handshake đến hết stop bit.
//   - tx_done là xung đúng một chu kỳ clk tại cạnh kết thúc bit dừng.
//   - Reset hủy frame đang phát, đặt uart_tx_o=1, tx_busy=0, tx_done=0.
// ============================================================================

module uart_tx #(
    parameter integer CLOCK_FREQ = 50_000_000,  // Hz
    parameter integer BAUD_RATE = 115_200      // baud
) (
    input wire clk,
    input wire rst_n,

    // Giao tiep du lieu dau vao
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,

    // Giao tiep UART.
    output reg uart_tx_o,

    // Tin hieu trang thai
    output wire       tx_busy,
    output reg        tx_done

);

    // ------------------------------------------------------------------------
    // Ma hoa trang thai FSM
    // ------------------------------------------------------------------------
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0] state;

    // Luu byte dang duoc truyen.
    reg [7:0] data_reg;

    // Chi so bit du lieu hien tai: D0 den D7.
    reg [2:0] bit_index;

    wire baud_tick;
    wire baud_enable;
    wire baud_restart;
    wire accept_data;

    // ------------------------------------------------------------------------
    // Giao thức bắt tay ready/valid.
    // ------------------------------------------------------------------------
    // Khong bao ready trong reset vi giao dich khong duoc chap nhan luc nay.
    assign tx_ready    = rst_n && (state == ST_IDLE);
    assign accept_data = tx_valid && tx_ready;

     // UART busy khi khong o trang thai IDLE.
    assign tx_busy = (state != ST_IDLE);

    // Baud counter chi hoat dong khi UART dang truyen.
    assign baud_enable = (state != ST_IDLE);

    // Khoi dong lai baud counter khi chap nhan byte moi.
    assign baud_restart = accept_data;

    // ------------------------------------------------------------------------
    // Bộ tạo tick baud.
    // ------------------------------------------------------------------------
    uart_baud_gen #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_baud_gen (
        .clk     (clk),
        .rst_n   (rst_n),
        .enable  (baud_enable),
        .restart (baud_restart),
        .tick    (baud_tick)
    );

    // ------------------------------------------------------------------------
    // Máy trạng thái và đường dữ liệu UART TX.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            data_reg  <= 8'h00;
            bit_index <= 3'd0;
            uart_tx_o <= 1'b1;
            tx_done   <= 1'b0;
        end else begin
            // Gia tri mac dinh de tx_done chi keo dai mot clock.
            tx_done <= 1'b0;

            case (state)

                // ============================================================
                // IDLE: Cho byte moi
                // ============================================================
                ST_IDLE: begin
                    uart_tx_o <= 1'b1;
                    bit_index <= 3'd0;

                    if (accept_data) begin
                        // Chot du lieu tai thoi diem handshake.
                        data_reg <= tx_data;

                        // Bat dau START bit ngay tai canh clock nay.
                        uart_tx_o <= 1'b0;
                        state     <= ST_START;
                    end
                end

                // ============================================================
                // START: Giu uart_tx_o = 0 trong mot chu ky bit
                // ============================================================
                ST_START: begin
                    if (baud_tick) begin
                        // Chuyen sang data bit dau tien D0.
                        uart_tx_o <= data_reg[0];
                        bit_index <= 3'd0;
                        state     <= ST_DATA;
                    end
                end

                // ============================================================
                // DATA: Truyen lan luot D0 den D7
                // ============================================================
                ST_DATA: begin
                    if (baud_tick) begin
                        if (bit_index == 3'd7) begin
                            // Da truyen xong D7, bat dau STOP bit.
                            uart_tx_o <= 1'b1;
                            state     <= ST_STOP;
                        end else begin
                            // Chuyen sang data bit tiep theo.
                            bit_index <= bit_index + 3'd1;

                            uart_tx_o <=
                                data_reg[bit_index + 3'd1];
                        end
                    end
                end

                // ============================================================
                // STOP: Giu uart_tx_o = 1 trong mot chu ky bit
                // ============================================================
                ST_STOP: begin
                    if (baud_tick) begin
                        uart_tx_o <= 1'b1;
                        state     <= ST_IDLE;
                        tx_done   <= 1'b1;
                    end
                end

                // ============================================================
                // Phuc hoi neu state roi vao gia tri khong hop le
                // ============================================================
                default: begin
                    state     <= ST_IDLE;
                    data_reg  <= 8'h00;
                    bit_index <= 3'd0;
                    uart_tx_o <= 1'b1;
                end

            endcase
        end
    end


endmodule

`default_nettype wire
