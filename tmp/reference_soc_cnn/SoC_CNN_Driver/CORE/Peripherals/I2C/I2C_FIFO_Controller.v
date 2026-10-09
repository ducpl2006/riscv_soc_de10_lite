// ============================================================================
// Module I2C_FIFO_Controller
// ----------------------------------------------------------------------------
// Bọc 2 FIFO (mục G của plan) + level/threshold/flush, tách Register_IF khỏi
// chi tiết FIFO.
//
//   TX/CMD FIFO : width = TX_WIDTH (8 data + 4 flag của DATA_CMD)
//                 write <- Register_IF (push DATA_CMD)
//                 read  -> Transaction_Engine
//   RX FIFO     : width = RX_WIDTH (8 bit)
//                 write <- Transaction_Engine
//                 read  -> Register_IF (RXDATA)
//
// Tái dùng CORE/Peripherals/UART/FIFO.v (KHÔNG sửa file dùng chung):
//   - flush: kéo reset của instance FIFO xuống 1 cycle -> xoá con trỏ/đếm
//            (fifo_reset = reset & ~flush).
//   - level: đếm song song trong controller (FIFO.v không xuất count) —
//            mirror đúng điều kiện write/read của FIFO (write&&!full, read&&!empty).
//
// Threshold IRQ (theo DesignWare):
//   tx_thres_irq = tx_level <= tx_thres   (TX vơi -> cần nạp thêm)
//   rx_thres_irq = rx_level >= rx_thres   (RX đầy tới ngưỡng -> cần đọc ra)
//
// Reset: active-low.
// ============================================================================
module I2C_FIFO_Controller #(
    parameter TX_WIDTH = 12,
    parameter RX_WIDTH = 8,
    parameter DEPTH    = 16     // nên là luỹ thừa 2 (ràng buộc của FIFO.v)
)
(
    input                       clk,
    input                       reset,      // active-low

    // flush (xung 1 cycle từ FIFO_CTRL.TX_CLR/RX_CLR)
    input                       tx_flush,
    input                       rx_flush,

    // ---- TX/CMD FIFO ----
    input                       tx_push,
    input  [TX_WIDTH - 1:0]     tx_wdata,
    input                       tx_pop,
    output [TX_WIDTH - 1:0]     tx_rdata,   // show-first (head)
    output                      tx_empty,
    output                      tx_full,

    // ---- RX FIFO ----
    input                       rx_push,
    input  [RX_WIDTH - 1:0]     rx_wdata,
    input                       rx_pop,
    output [RX_WIDTH - 1:0]     rx_rdata,
    output                      rx_empty,
    output                      rx_full,

    // ---- level + threshold ----
    output [7:0]                tx_level,
    output [7:0]                rx_level,
    input  [7:0]                tx_thres,
    input  [7:0]                rx_thres,
    output                      tx_thres_irq,
    output                      rx_thres_irq
);

    // ========================================================================
    // Reset riêng cho từng FIFO (global reset + flush)
    // ========================================================================
    wire tx_fifo_rst = reset & ~tx_flush;
    wire rx_fifo_rst = reset & ~rx_flush;

    // ========================================================================
    // FIFO instances (reuse UART FIFO.v)
    // ========================================================================
    FIFO #(.W(TX_WIDTH), .L(DEPTH)) u_tx_fifo (
        .clk(clk), .reset(tx_fifo_rst),
        .write_en(tx_push), .read_en(tx_pop), .data_in(tx_wdata),
        .full(tx_full), .empty(tx_empty), .data_out(tx_rdata)
    );

    FIFO #(.W(RX_WIDTH), .L(DEPTH)) u_rx_fifo (
        .clk(clk), .reset(rx_fifo_rst),
        .write_en(rx_push), .read_en(rx_pop), .data_in(rx_wdata),
        .full(rx_full), .empty(rx_empty), .data_out(rx_rdata)
    );

    // ========================================================================
    // Level counters (mirror điều kiện của FIFO)
    // ========================================================================
    wire tx_wr = tx_push & ~tx_full;
    wire tx_rd = tx_pop  & ~tx_empty;
    wire rx_wr = rx_push & ~rx_full;
    wire rx_rd = rx_pop  & ~rx_empty;

    reg [7:0] tx_level_r;
    reg [7:0] rx_level_r;

    always @(posedge clk) begin
        if (!reset || tx_flush)
            tx_level_r <= 8'd0;
        else case ({tx_wr, tx_rd})
            2'b10:   tx_level_r <= tx_level_r + 8'd1;
            2'b01:   tx_level_r <= tx_level_r - 8'd1;
            default: tx_level_r <= tx_level_r;
        endcase
    end

    always @(posedge clk) begin
        if (!reset || rx_flush)
            rx_level_r <= 8'd0;
        else case ({rx_wr, rx_rd})
            2'b10:   rx_level_r <= rx_level_r + 8'd1;
            2'b01:   rx_level_r <= rx_level_r - 8'd1;
            default: rx_level_r <= rx_level_r;
        endcase
    end

    assign tx_level = tx_level_r;
    assign rx_level = rx_level_r;

    // ========================================================================
    // Threshold IRQ
    // ========================================================================
    assign tx_thres_irq = (tx_level_r <= tx_thres);
    assign rx_thres_irq = (rx_level_r >= rx_thres);

endmodule
