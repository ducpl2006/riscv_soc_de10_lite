// ============================================================================
// Module I2C_Transaction_Engine
// ----------------------------------------------------------------------------
// FSM mức TRANSACTION (mục F của plan). Đọc entry DATA_CMD từ TX/CMD FIFO,
// điều phối I2C_Byte_Controller phát chuỗi byte, tự sinh START/RESTART/STOP,
// đẩy byte đọc vào RX FIFO, xử lý NACK.
//
// Entry (tx_entry[11:0]) = DATA_CMD register (0x18):
//   [7:0]  DATA
//   [8]    CMD    0=WRITE byte, 1=READ byte
//   [9]    START  phát (repeated) START + gửi ADDRESS trước entry này
//   [10]   STOP   phát STOP sau entry này
//   [11]   NACK   khi READ: master trả NACK cho byte này (byte cuối)
//
// Với mỗi entry:
//   START=1 -> BC_START -> BC_WRITE({ADDRESS[6:0], CMD})  [gửi địa chỉ + R/W]
//              nếu slave NACK địa chỉ -> lỗi -> STOP
//   CMD=0   -> BC_WRITE(DATA) ; NACK data -> lỗi -> STOP
//   CMD=1   -> BC_READ(ack=NACK) -> push RX FIFO
//   STOP=1  -> BC_STOP
//
// Handshake dưới (Byte_Controller): pulse byte_cmd_valid (cạnh lên), chờ
// byte_cmd_ack. Có 1 cycle valid=0 giữa 2 lệnh.
//
// Reset: active-low.
// ============================================================================
module I2C_Transaction_Engine (
    input           clk,
    input           reset,          // active-low
    input           core_en,
    input           abort,          // COMMAND.ABORT (mức) -> kết thúc sớm bằng STOP

    // ---- cấu hình ----
    input  [9:0]    addr,           // ADDRESS.SLAVE_ADDR (dùng [6:0] cho 7-bit)

    // ---- TX/CMD FIFO (đọc) ----
    input           tx_empty,
    input  [11:0]   tx_entry,       // = head FIFO (show-first)
    output          tx_pop,

    // ---- RX FIFO (ghi) ----
    output          rx_push,
    output [7:0]    rx_wdata,

    // ---- Byte_Controller ----
    output [1:0]    byte_cmd,
    output          byte_cmd_valid,
    output [7:0]    byte_wr_data,
    output          byte_ack_in,
    input           byte_cmd_ack,
    input  [7:0]    byte_rd_data,
    input           byte_rx_ack,
    input           byte_al,

    // ---- status / events (pulse trừ busy/rxack) ----
    output          busy,
    output          ev_tx_done,     // ghi xong 1 byte (ACK)
    output          ev_rx_done,     // đọc xong 1 byte
    output          ev_nack,        // slave NACK (chung)
    output          ev_nack_addr,   // NACK ở byte địa chỉ
    output          ev_nack_data,   // NACK ở byte data
    output          ev_stop,        // đã phát STOP
    output          ev_arb_lost,    // mất arbitration
    output          rxack           // ACK gần nhất từ slave (0=ACK,1=NACK)
);

    // ---- Byte command encodings (khớp I2C_Byte_Controller) ----
    localparam BC_START = 2'd0;
    localparam BC_STOP  = 2'd1;
    localparam BC_WRITE = 2'd2;
    localparam BC_READ  = 2'd3;

    // ---- FSM states ----
    localparam S_IDLE  = 3'd0;
    localparam S_FETCH = 3'd1;
    localparam S_ISSUE = 3'd2;
    localparam S_WAIT  = 3'd3;

    // ---- phase (ngữ cảnh của lệnh byte đang chạy) ----
    localparam PH_START = 3'd0;
    localparam PH_ADDR  = 3'd1;
    localparam PH_DATA  = 3'd2;
    localparam PH_STOP  = 3'd3;
    localparam PH_ABORT = 3'd4;

    reg [2:0]   state;
    reg [2:0]   phase;
    reg [11:0]  entry;

    reg [1:0]   bcmd_r;
    reg [7:0]   bwr_r;
    reg         back_r;
    reg         bcv;            // byte_cmd_valid

    reg         tx_pop_r;
    reg         rx_push_r;
    reg [7:0]   rx_wdata_r;

    reg         busy_r;
    reg         rxack_r;
    reg         ev_tx_done_r, ev_rx_done_r, ev_nack_r, ev_stop_r, ev_al_r;
    reg         ev_na_r, ev_nd_r;   // NACK address / data

    // entry field aliases
    wire        e_cmd   = entry[8];
    wire        e_start = entry[9];
    wire        e_stop  = entry[10];
    wire        e_nack  = entry[11];

    // ========================================================================
    always @(posedge clk) begin

        if (!reset) begin
            state       <= S_IDLE;
            phase       <= PH_START;
            entry       <= 12'd0;
            bcmd_r      <= BC_START;
            bwr_r       <= 8'd0;
            back_r      <= 1'b0;
            bcv         <= 1'b0;
            tx_pop_r    <= 1'b0;
            rx_push_r   <= 1'b0;
            rx_wdata_r  <= 8'd0;
            busy_r      <= 1'b0;
            rxack_r     <= 1'b0;
            ev_tx_done_r<= 1'b0;
            ev_rx_done_r<= 1'b0;
            ev_nack_r   <= 1'b0;
            ev_stop_r   <= 1'b0;
            ev_al_r     <= 1'b0;
            ev_na_r     <= 1'b0;
            ev_nd_r     <= 1'b0;
        end

        else if (!core_en) begin
            state     <= S_IDLE;
            bcv       <= 1'b0;
            tx_pop_r  <= 1'b0;
            rx_push_r <= 1'b0;
            busy_r    <= 1'b0;
        end

        else begin
            // pulses mặc định = 0
            tx_pop_r    <= 1'b0;
            rx_push_r   <= 1'b0;
            ev_tx_done_r<= 1'b0;
            ev_rx_done_r<= 1'b0;
            ev_nack_r   <= 1'b0;
            ev_stop_r   <= 1'b0;
            ev_al_r     <= 1'b0;
            ev_na_r     <= 1'b0;
            ev_nd_r     <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                S_IDLE: begin
                    busy_r <= 1'b0;
                    if (!tx_empty && !abort) begin
                        busy_r <= 1'b1;
                        state  <= S_FETCH;
                    end
                end

                // ----------------------------------------------------------------
                // Lấy entry ở đầu FIFO, quyết định hành động đầu tiên
                // ----------------------------------------------------------------
                S_FETCH: begin
                    entry    <= tx_entry;   // head (show-first)
                    tx_pop_r <= 1'b1;       // advance FIFO

                    if (tx_entry[9]) begin  // START flag
                        bcmd_r <= BC_START;
                        phase  <= PH_START;
                    end else begin
                        // tiếp tục transaction: đi thẳng vào data op
                        if (tx_entry[8]) begin  // CMD=READ
                            bcmd_r <= BC_READ;
                            back_r <= tx_entry[11];
                        end else begin          // CMD=WRITE
                            bcmd_r <= BC_WRITE;
                            bwr_r  <= tx_entry[7:0];
                        end
                        phase <= PH_DATA;
                    end
                    state <= S_ISSUE;
                end

                // ----------------------------------------------------------------
                S_ISSUE: begin
                    bcv   <= 1'b1;
                    state <= S_WAIT;
                end

                // ----------------------------------------------------------------
                S_WAIT: begin
                    if (byte_cmd_ack) begin
                        bcv <= 1'b0;
                        if (byte_al) ev_al_r <= 1'b1;

                        case (phase)

                            // --- sau START -> gửi địa chỉ + R/W ---
                            PH_START: begin
                                bcmd_r <= BC_WRITE;
                                bwr_r  <= {addr[6:0], e_cmd};   // R/W = CMD
                                phase  <= PH_ADDR;
                                state  <= S_ISSUE;
                            end

                            // --- sau ADDRESS -> kiểm tra ACK ---
                            PH_ADDR: begin
                                rxack_r <= byte_rx_ack;
                                if (byte_rx_ack) begin
                                    // NACK địa chỉ -> lỗi -> STOP
                                    ev_nack_r <= 1'b1;
                                    ev_na_r   <= 1'b1;
                                    bcmd_r    <= BC_STOP;
                                    phase     <= PH_ABORT;
                                    state     <= S_ISSUE;
                                end else begin
                                    // gửi/nhận data
                                    if (e_cmd) begin
                                        bcmd_r <= BC_READ;
                                        back_r <= e_nack;
                                    end else begin
                                        bcmd_r <= BC_WRITE;
                                        bwr_r  <= entry[7:0];
                                    end
                                    phase <= PH_DATA;
                                    state <= S_ISSUE;
                                end
                            end

                            // --- sau DATA op ---
                            PH_DATA: begin
                                if (e_cmd) begin
                                    // READ: push byte vào RX FIFO
                                    rx_push_r    <= 1'b1;
                                    rx_wdata_r   <= byte_rd_data;
                                    ev_rx_done_r <= 1'b1;
                                end else begin
                                    // WRITE: kiểm tra ACK
                                    rxack_r <= byte_rx_ack;
                                    if (byte_rx_ack) begin
                                        ev_nack_r <= 1'b1;
                                        ev_nd_r   <= 1'b1;
                                        bcmd_r    <= BC_STOP;
                                        phase     <= PH_ABORT;
                                        state     <= S_ISSUE;
                                    end else begin
                                        ev_tx_done_r <= 1'b1;
                                    end
                                end

                                // nếu chưa chuyển sang ABORT (state vẫn S_WAIT) -> stop check
                                if (!(!e_cmd && byte_rx_ack)) begin
                                    if (e_stop) begin
                                        bcmd_r <= BC_STOP;
                                        phase  <= PH_STOP;
                                        state  <= S_ISSUE;
                                    end else begin
                                        state <= S_IDLE;    // entry kế
                                    end
                                end
                            end

                            // --- sau STOP bình thường ---
                            PH_STOP: begin
                                ev_stop_r <= 1'b1;
                                state     <= S_IDLE;
                            end

                            // --- sau STOP do abort/nack ---
                            PH_ABORT: begin
                                ev_stop_r <= 1'b1;
                                state     <= S_IDLE;
                            end

                            default: state <= S_IDLE;
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Outputs
    // ========================================================================
    assign tx_pop         = tx_pop_r;
    assign rx_push        = rx_push_r;
    assign rx_wdata       = rx_wdata_r;

    assign byte_cmd       = bcmd_r;
    assign byte_cmd_valid = bcv;
    assign byte_wr_data   = bwr_r;
    assign byte_ack_in    = back_r;

    assign busy        = busy_r;
    assign ev_tx_done  = ev_tx_done_r;
    assign ev_rx_done  = ev_rx_done_r;
    assign ev_nack      = ev_nack_r;
    assign ev_nack_addr = ev_na_r;
    assign ev_nack_data = ev_nd_r;
    assign ev_stop     = ev_stop_r;
    assign ev_arb_lost = ev_al_r;
    assign rxack       = rxack_r;

endmodule
