// ============================================================================
// Module I2C_Master
// ----------------------------------------------------------------------------
// Tầng CORE (structural, mục A.1 của plan). Ghép toàn bộ sub-block đã verify:
//
//   Clock_Divider ─ ticks ─▶ Bit_Controller ◀─ Byte_Controller ◀─ Transaction_Engine
//                                   │                                    │
//                             SCL/SDA_Controller ◀── Bus_Recovery        FIFO_Controller
//                                   │  (mux recovery_active)             (TX/CMD, RX)
//                             Input_Filter ×2 ── sda_in/scl_in
//                             Timeout, IRQ_Status
//
// KHÔNG có FSM mới — chỉ đi dây + mux line-owner. Xuất giao diện gọn cho
// I2C_Register_IF (push DATA_CMD, pop RXDATA, config, status/irq) + chân I2C.
//
// Reset: active-low.
// ============================================================================
module I2C_Master #(
    parameter PRESCALE_WIDTH        = 16,
    parameter FIFO_DEPTH            = 16,
    parameter SYNC_STAGES           = 2,
    parameter SPIKE_LEN             = 3,
    parameter SUPPORT_CLOCK_STRETCH = 1,
    parameter ENABLE_ARBITRATION    = 0
)
(
    input                           clk,
    input                           reset,          // active-low

    // ---- control / config (từ register) ----
    input                           core_en,        // CTRL.EN
    input                           recover_en,     // CTRL.RECOVER_EN (auto recovery)
    input  [PRESCALE_WIDTH - 1:0]   prescale,       // PRESCALE
    input  [9:0]                    addr,           // ADDRESS
    input  [23:0]                   timeout_val,    // TIMEOUT

    // ---- COMMAND (pulse) ----
    input                           cmd_abort,
    input                           cmd_bus_recover,

    // ---- DATA_CMD FIFO push (Register_IF) ----
    input                           tx_push,
    input  [11:0]                   tx_wdata,
    // ---- RXDATA pop (Register_IF) ----
    input                           rx_pop,
    output [7:0]                    rx_rdata,

    // ---- FIFO flush + threshold + status ----
    input                           tx_flush,
    input                           rx_flush,
    input  [7:0]                    tx_thres,
    input  [7:0]                    rx_thres,
    output [7:0]                    tx_level,
    output [7:0]                    rx_level,
    output                          tx_full,
    output                          tx_empty,
    output                          rx_full,
    output                          rx_empty,

    // ---- interrupt ----
    input  [7:0]                    int_enable,
    input  [7:0]                    int_clr,        // W1C pulses
    input  [4:0]                    err_clr,        // W1C pulses
    output [7:0]                    int_status,
    output [4:0]                    err_status,
    output                          irq,

    // ---- live status (STATUS reg) ----
    output [7:0]                    status,

    // ---- I2C pins (open-drain, cần pull-up ngoài) ----
    inout                           scl_pad,
    inout                           sda_pad
);

    // ========================================================================
    // Interconnect wires
    // ========================================================================
    // clock divider
    wire [1:0]  phase;
    wire        tick_a, tick_b, tick_c, tick_d;
    wire        pause;

    // line
    wire        scl_in, sda_in, scl_raw, sda_raw;
    wire        bit_scl_oe, bit_sda_oe;
    wire        rec_scl_oe, rec_sda_oe, recovery_active;

    // bit <-> byte
    wire [2:0]  bit_cmd;
    wire        bit_cmd_valid, bit_din, bit_cmd_ack, bit_dout, bit_al;

    // byte <-> transaction
    wire [1:0]  byte_cmd;
    wire        byte_cmd_valid, byte_ack_in, byte_cmd_ack, byte_rx_ack, byte_al;
    wire [7:0]  byte_wr_data, byte_rd_data;

    // transaction <-> fifo
    wire        tx_pop, rx_push;
    wire [11:0] tx_entry;
    wire [7:0]  rx_wdata;
    wire        tx_thres_irq, rx_thres_irq;

    // events
    wire        ev_tx_done, ev_rx_done, ev_nack, ev_nack_addr, ev_nack_data;
    wire        ev_stop, ev_arb_lost, te_busy, te_rxack;
    wire        rec_done, rec_sda_stuck;
    wire        to_timeout;

    // ========================================================================
    // Clock divider
    // ========================================================================
    I2C_Clock_Divider #(.PRESCALE_WIDTH(PRESCALE_WIDTH)) u_div (
        .clk(clk), .reset(reset), .enable(core_en), .pause(pause), .prescale(prescale),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d));

    // ========================================================================
    // Input filters (2-FF sync + spike)
    // ========================================================================
    I2C_Input_Filter #(.SYNC_STAGES(SYNC_STAGES), .SPIKE_LEN(SPIKE_LEN)) f_scl (
        .clk(clk), .reset(reset), .line_async(scl_raw), .line_clean(scl_in));
    I2C_Input_Filter #(.SYNC_STAGES(SYNC_STAGES), .SPIKE_LEN(SPIKE_LEN)) f_sda (
        .clk(clk), .reset(reset), .line_async(sda_raw), .line_clean(sda_in));

    // ========================================================================
    // Line pad drivers (open-drain + mux owner)
    // ========================================================================
    I2C_SCL_Controller u_scl (
        .bit_scl_oe(bit_scl_oe), .rec_scl_oe(rec_scl_oe), .recovery_active(recovery_active),
        .scl_pad(scl_pad), .scl_in_raw(scl_raw));
    I2C_SDA_Controller u_sda (
        .bit_sda_oe(bit_sda_oe), .rec_sda_oe(rec_sda_oe), .recovery_active(recovery_active),
        .sda_pad(sda_pad), .sda_in_raw(sda_raw));

    // ========================================================================
    // Bit controller
    // ========================================================================
    I2C_Bit_Controller #(
        .SUPPORT_CLOCK_STRETCH(SUPPORT_CLOCK_STRETCH), .ENABLE_ARBITRATION(ENABLE_ARBITRATION)
    ) u_bit (
        .clk(clk), .reset(reset), .core_en(core_en),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d),
        .pause(pause),
        .cmd(bit_cmd), .cmd_valid(bit_cmd_valid), .din(bit_din),
        .cmd_ack(bit_cmd_ack), .dout(bit_dout), .al(bit_al),
        .scl_oe(bit_scl_oe), .sda_oe(bit_sda_oe), .scl_in(scl_in), .sda_in(sda_in));

    // ========================================================================
    // Byte controller
    // ========================================================================
    I2C_Byte_Controller u_byte (
        .clk(clk), .reset(reset), .core_en(core_en),
        .cmd(byte_cmd), .cmd_valid(byte_cmd_valid), .wr_data(byte_wr_data), .ack_in(byte_ack_in),
        .cmd_ack(byte_cmd_ack), .rd_data(byte_rd_data), .rx_ack(byte_rx_ack), .al(byte_al),
        .bit_cmd(bit_cmd), .bit_cmd_valid(bit_cmd_valid), .bit_din(bit_din),
        .bit_cmd_ack(bit_cmd_ack), .bit_dout(bit_dout), .bit_al(bit_al));

    // ========================================================================
    // Transaction engine
    // ========================================================================
    I2C_Transaction_Engine u_te (
        .clk(clk), .reset(reset), .core_en(core_en), .abort(cmd_abort),
        .addr(addr),
        .tx_empty(tx_empty), .tx_entry(tx_entry), .tx_pop(tx_pop),
        .rx_push(rx_push), .rx_wdata(rx_wdata),
        .byte_cmd(byte_cmd), .byte_cmd_valid(byte_cmd_valid), .byte_wr_data(byte_wr_data),
        .byte_ack_in(byte_ack_in), .byte_cmd_ack(byte_cmd_ack), .byte_rd_data(byte_rd_data),
        .byte_rx_ack(byte_rx_ack), .byte_al(byte_al),
        .busy(te_busy), .ev_tx_done(ev_tx_done), .ev_rx_done(ev_rx_done),
        .ev_nack(ev_nack), .ev_nack_addr(ev_nack_addr), .ev_nack_data(ev_nack_data),
        .ev_stop(ev_stop), .ev_arb_lost(ev_arb_lost), .rxack(te_rxack));

    // ========================================================================
    // FIFO controller (TX/CMD + RX)
    // ========================================================================
    I2C_FIFO_Controller #(.TX_WIDTH(12), .RX_WIDTH(8), .DEPTH(FIFO_DEPTH)) u_fifo (
        .clk(clk), .reset(reset), .tx_flush(tx_flush), .rx_flush(rx_flush),
        .tx_push(tx_push), .tx_wdata(tx_wdata), .tx_pop(tx_pop),
        .tx_rdata(tx_entry), .tx_empty(tx_empty), .tx_full(tx_full),
        .rx_push(rx_push), .rx_wdata(rx_wdata), .rx_pop(rx_pop),
        .rx_rdata(rx_rdata), .rx_empty(rx_empty), .rx_full(rx_full),
        .tx_level(tx_level), .rx_level(rx_level),
        .tx_thres(tx_thres), .rx_thres(rx_thres),
        .tx_thres_irq(tx_thres_irq), .rx_thres_irq(rx_thres_irq));

    // ========================================================================
    // Timeout monitor
    // ========================================================================
    I2C_Timeout u_to (
        .clk(clk), .reset(reset), .core_en(core_en),
        .scl_in(scl_in), .timeout_val(timeout_val), .timeout(to_timeout));

    // ========================================================================
    // Bus recovery
    // ========================================================================
    wire rec_trigger = cmd_bus_recover | (recover_en & to_timeout);

    I2C_Bus_Recovery u_rec (
        .clk(clk), .reset(reset), .core_en(core_en), .trigger(rec_trigger),
        .tick_a(tick_a), .tick_c(tick_c), .sda_in(sda_in),
        .rec_scl_oe(rec_scl_oe), .rec_sda_oe(rec_sda_oe), .recovery_active(recovery_active),
        .done(rec_done), .sda_stuck(rec_sda_stuck));

    // ========================================================================
    // INT / ERROR set pulses
    // ========================================================================
    // TX_EMPTY / RX_FULL interrupt: cạnh lên của threshold flag
    reg tx_thres_d, rx_thres_d;
    always @(posedge clk) begin
        if (!reset) begin tx_thres_d <= 1'b0; rx_thres_d <= 1'b0; end
        else        begin tx_thres_d <= tx_thres_irq; rx_thres_d <= rx_thres_irq; end
    end
    wire tx_empty_evt = tx_thres_irq & ~tx_thres_d;
    wire rx_full_evt  = rx_thres_irq & ~rx_thres_d;

    wire [7:0] int_set = {
        ev_stop,        // 7 STOP_DET
        to_timeout,     // 6 TIMEOUT
        rx_full_evt,    // 5 RX_FULL
        tx_empty_evt,   // 4 TX_EMPTY
        ev_arb_lost,    // 3 ARB_LOST
        ev_nack,        // 2 NACK
        ev_rx_done,     // 1 RX_DONE
        ev_tx_done      // 0 TX_DONE
    };

    wire [4:0] err_set = {
        rec_sda_stuck,  // 4 SDA_STUCK
        to_timeout,     // 3 SCL_TIMEOUT
        ev_arb_lost,    // 2 ARB_LOST
        ev_nack_data,   // 1 NACK_DATA
        ev_nack_addr    // 0 NACK_ADDR
    };

    I2C_IRQ_Status u_irq (
        .clk(clk), .reset(reset),
        .int_set(int_set), .err_set(err_set),
        .int_clr(int_clr), .err_clr(err_clr), .int_enable(int_enable),
        .int_status(int_status), .err_status(err_status), .irq(irq));

    // ========================================================================
    // Live STATUS (0x08)
    // ========================================================================
    wire core_busy = te_busy | recovery_active;
    assign status = {
        ~core_busy,         // 7 IDLE
        rx_full,            // 6 RX_FULL
        tx_empty,           // 5 TX_EMPTY
        pause,              // 4 BUS_HOLD (clock stretching)
        err_status[2],      // 3 AL (sticky arb lost)
        te_rxack,           // 2 RXACK
        te_busy,            // 1 TIP
        core_busy           // 0 BUSY
    };

endmodule
