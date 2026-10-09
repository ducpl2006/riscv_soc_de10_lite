`default_nettype none
// Module: soc_uart
// Purpose: MMIO UART TX/RX, tái sử dụng TX/FIFO đã kiểm chứng, thêm RX/FIFO độc lập.
// Clock: clk_i. Reset: rst_i synchronous active-high, chặn mọi handshake.
// Inputs: native bus offset 12 bit, rx_i bất đồng bộ. Outputs: response, tx_o, busy_o.
// Protocol: side effect tại req_i && ready_o && !err_o; RX pop đúng một lần.
// Latency: 0 wait trừ TX DATA khi FIFO đầy; RX_DATA rỗng kết thúc bằng fault.
// Error behavior: invalid/unaligned/write RO/empty RX fault, error flags W1C.
// 000 TX_DATA RW (read 0); 004 STATUS RO; 008 RX_DATA RO/pop; 00C ERRORS RW/W1C.
// STATUS[7:0]: false_start, framing, overrun, full, empty, valid, tx_busy, tx_ready.
module soc_uart #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer TX_FIFO_DEPTH = 4,
    parameter integer RX_FIFO_DEPTH = 16
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        req_i,
    input  wire        we_i,
    input  wire [11:0]  addr_i,
    input  wire [31:0]  wdata_i,
    input  wire [3:0]   wstrb_i,
    output reg  [31:0] rdata_o,
    output wire        ready_o,
    output wire        err_o,
    input  wire        rx_i,
    output wire        tx_o,
    output wire        busy_o
);
    wire tx_ready;
    wire [31:0] tx_status;
    wire [7:0] rx_byte, head;
    wire rx_valid, framing, false_start, overrun, empty, full;
    // Sticky error bits theo STATUS[7:5]. Event mới ưu tiên hơn clear cùng cạnh.
    reg [2:0] errors_q;

    // Decode: offset, quyền ghi và điều kiện đọc FIFO rỗng.
    wire valid_addr = (addr_i == 0 || addr_i == 4 ||
                       addr_i == 8 || addr_i == 12);
    wire bad_access = !valid_addr ||
                      (we_i && addr_i != 0 && addr_i != 12) ||
                      (!we_i && addr_i == 8 && empty);

    // Handshake: chỉ TX_DATA có thể chờ FIFO TX.
    assign err_o = req_i && !rst_i && bad_access;
    assign ready_o = req_i && !rst_i &&
                     (bad_access || addr_i != 0 || tx_ready);

    // Side effect chỉ được phép sau handshake thành công.
    wire commit = req_i && ready_o && !err_o;
    wire pop = commit && !we_i && addr_i == 8;
    wire clear = commit && we_i && addr_i == 12 && wstrb_i[0];

    soc_uart_tx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD(BAUD),
        .FIFO_DEPTH(TX_FIFO_DEPTH)
    ) u_tx (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(req_i && addr_i == 0),
        .we_i(we_i),
        .addr_i(addr_i[3:0]),
        .wdata_i(wdata_i),
        .wstrb_i(wstrb_i),
        .rdata_o(tx_status),
        .ready_o(tx_ready),
        .err_o(),
        .tx_o(tx_o),
        .busy_o(busy_o)
    );

    uart_rx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD(BAUD)
    ) u_rx (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .rx_i(rx_i),
        .data_o(rx_byte),
        .valid_o(rx_valid),
        .framing_error_o(framing),
        .false_start_o(false_start)
    );

    uart_rx_fifo #(.DEPTH(RX_FIFO_DEPTH)) u_rx_fifo (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .push_i(rx_valid),
        .data_i(rx_byte),
        .pop_i(pop),
        .data_o(head),
        .empty_o(empty),
        .full_o(full),
        .overrun_o(overrun)
    );

    // Latch cờ lỗi; sự kiện mới thắng W1C tại cùng cạnh clock.
    always @(posedge clk_i) begin
        if (rst_i)
            errors_q <= 0;
        else
            errors_q <= (errors_q & ~(clear ? wdata_i[7:5] : 3'b0)) |
                        {false_start, framing, overrun};
    end

    // Readback tổ hợp; việc pop RX đã được gate riêng bởi commit.
    always @* begin
        rdata_o = 0;
        case (addr_i)
            12'h004: rdata_o = {24'd0, errors_q, full, empty, !empty, tx_status[1:0]};
            12'h008: rdata_o = {24'd0, head};
            12'h00C: rdata_o = {24'd0, errors_q, 5'd0};
            default: begin end
        endcase
    end
endmodule
`default_nettype wire
