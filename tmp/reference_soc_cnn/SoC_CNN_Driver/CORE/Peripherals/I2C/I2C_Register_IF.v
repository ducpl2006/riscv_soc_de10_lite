// ============================================================================
// Module I2C_Register_IF
// ----------------------------------------------------------------------------
// Tầng REGISTER THUẦN (mục A.3/B của plan). Giải mã offset, đọc/ghi thanh ghi,
// sinh xung write & W1C/self-clear; bọc I2C_Master. `rd_data` combinational
// (bám pattern UART_Register_IF.v) để APB capture đúng cycle. KHÔNG latch status.
//
// Register map (offset = {addr[7:2],2'b00}):
//   0x00 VERSION    RO
//   0x04 CTRL       RW   [0]EN [5]RECOVER_EN ...
//   0x08 STATUS     RO
//   0x0C COMMAND    WO/SC [0]ABORT [1]BUS_RECOVER [2]SOFT_RESET [3]IACK
//   0x10 PRESCALE   RW
//   0x14 ADDRESS    RW   [9:0]
//   0x18 DATA_CMD   WO   push [11:0] vào TX/CMD FIFO
//   0x1C RXDATA     RO   pop RX FIFO khi đọc
//   0x20 INT_ENABLE RW
//   0x24 INT_STATUS RW1C
//   0x28 FIFO_CTRL  RW/SC [0]TX_CLR [1]RX_CLR [11:4]TX_THRES [19:12]RX_THRES
//   0x2C FIFO_STATUS RO
//   0x30 TIMEOUT    RW   [23:0]
//   0x34 ERROR_STATUS RW1C
//
// Reset: active-low.
// ============================================================================
module I2C_Register_IF #(
    parameter ADDR_WIDTH            = 32,
    parameter PRESCALE_WIDTH        = 16,
    parameter FIFO_DEPTH            = 16,
    parameter SYNC_STAGES           = 2,
    parameter SPIKE_LEN             = 3,
    parameter SUPPORT_CLOCK_STRETCH = 1,
    parameter ENABLE_ARBITRATION    = 0,
    parameter [31:0] VERSION_ID     = 32'h0001_0000
)
(
    input                       clk,
    input                       reset,      // active-low

    // ---- register access (từ APB slave) ----
    input  [ADDR_WIDTH - 1:0]   addr,
    input  [31:0]               wr_data,
    input                       write_en,   // 1-cycle strobe
    input                       read_en,    // 1-cycle strobe
    output reg [31:0]           rd_data,    // combinational

    // ---- interrupt ra CPU ----
    output                      irq,

    // ---- I2C pins ----
    inout                       scl_pad,
    inout                       sda_pad
);

    // ---- offset ----
    wire [7:0] off = {addr[7:2], 2'b00};

    localparam OFF_VERSION  = 8'h00;
    localparam OFF_CTRL     = 8'h04;
    localparam OFF_STATUS   = 8'h08;
    localparam OFF_COMMAND  = 8'h0C;
    localparam OFF_PRESCALE = 8'h10;
    localparam OFF_ADDRESS  = 8'h14;
    localparam OFF_DATACMD  = 8'h18;
    localparam OFF_RXDATA   = 8'h1C;
    localparam OFF_INTEN    = 8'h20;
    localparam OFF_INTSTAT  = 8'h24;
    localparam OFF_FIFOCTRL = 8'h28;
    localparam OFF_FIFOSTAT = 8'h2C;
    localparam OFF_TIMEOUT  = 8'h30;
    localparam OFF_ERRSTAT  = 8'h34;

    // ========================================================================
    // RW register storage
    // ========================================================================
    reg [31:0] ctrl_reg;
    reg [31:0] prescale_reg;
    reg [31:0] addr_reg;
    reg [31:0] timeout_reg;
    reg [31:0] inten_reg;
    reg [31:0] fifoctrl_reg;   // chỉ giữ threshold; TX_CLR/RX_CLR self-clear

    always @(posedge clk) begin
        if (!reset) begin
            ctrl_reg     <= 32'd0;
            prescale_reg <= 32'h0000_00FF;
            addr_reg     <= 32'd0;
            timeout_reg  <= 32'd0;
            inten_reg    <= 32'd0;
            fifoctrl_reg <= 32'd0;
        end
        else if (write_en) begin
            case (off)
                OFF_CTRL:     ctrl_reg     <= wr_data;
                OFF_PRESCALE: prescale_reg <= wr_data;
                OFF_ADDRESS:  addr_reg     <= wr_data;
                OFF_TIMEOUT:  timeout_reg  <= wr_data;
                OFF_INTEN:    inten_reg    <= wr_data;
                OFF_FIFOCTRL: fifoctrl_reg <= {wr_data[31:2], 2'b00}; // clr bit self-clear
                default: ;
            endcase
        end
    end

    // ========================================================================
    // Write-derived pulses (1-cycle theo write_en)
    // ========================================================================
    wire wr_cmd      = write_en && (off == OFF_COMMAND);
    wire wr_intstat  = write_en && (off == OFF_INTSTAT);
    wire wr_errstat  = write_en && (off == OFF_ERRSTAT);
    wire wr_fifoctrl = write_en && (off == OFF_FIFOCTRL);

    wire cmd_abort       = wr_cmd && wr_data[0];
    wire cmd_bus_recover = wr_cmd && wr_data[1];
    wire soft_reset      = wr_cmd && wr_data[2];
    wire iack            = wr_cmd && wr_data[3];

    // DATA_CMD push
    wire        tx_push  = write_en && (off == OFF_DATACMD);
    wire [11:0] tx_wdata = wr_data[11:0];

    // RXDATA pop khi đọc
    wire        rx_pop   = read_en && (off == OFF_RXDATA);

    // FIFO flush (self-clear + soft_reset)
    wire tx_flush = (wr_fifoctrl && wr_data[0]) || soft_reset;
    wire rx_flush = (wr_fifoctrl && wr_data[1]) || soft_reset;

    // INT/ERROR W1C (IACK xoá toàn bộ INT)
    wire [7:0] int_clr = ({8{iack}}) | (wr_intstat ? wr_data[7:0] : 8'd0);
    wire [4:0] err_clr = wr_errstat ? wr_data[4:0] : 5'd0;

    // ========================================================================
    // I2C_Master
    // ========================================================================
    wire [7:0]  m_rx_rdata;
    wire [7:0]  m_tx_level, m_rx_level;
    wire        m_tx_full, m_tx_empty, m_rx_full, m_rx_empty;
    wire [7:0]  m_int_status, m_status;
    wire [4:0]  m_err_status;

    I2C_Master #(
        .PRESCALE_WIDTH(PRESCALE_WIDTH), .FIFO_DEPTH(FIFO_DEPTH),
        .SYNC_STAGES(SYNC_STAGES), .SPIKE_LEN(SPIKE_LEN),
        .SUPPORT_CLOCK_STRETCH(SUPPORT_CLOCK_STRETCH), .ENABLE_ARBITRATION(ENABLE_ARBITRATION)
    ) u_master (
        .clk(clk), .reset(reset),
        .core_en(ctrl_reg[0]), .recover_en(ctrl_reg[5]),
        .prescale(prescale_reg[PRESCALE_WIDTH - 1:0]),
        .addr(addr_reg[9:0]), .timeout_val(timeout_reg[23:0]),
        .cmd_abort(cmd_abort), .cmd_bus_recover(cmd_bus_recover),
        .tx_push(tx_push), .tx_wdata(tx_wdata),
        .rx_pop(rx_pop), .rx_rdata(m_rx_rdata),
        .tx_flush(tx_flush), .rx_flush(rx_flush),
        .tx_thres(fifoctrl_reg[11:4]), .rx_thres(fifoctrl_reg[19:12]),
        .tx_level(m_tx_level), .rx_level(m_rx_level),
        .tx_full(m_tx_full), .tx_empty(m_tx_empty),
        .rx_full(m_rx_full), .rx_empty(m_rx_empty),
        .int_enable(inten_reg[7:0]), .int_clr(int_clr), .err_clr(err_clr),
        .int_status(m_int_status), .err_status(m_err_status), .irq(irq),
        .status(m_status),
        .scl_pad(scl_pad), .sda_pad(sda_pad)
    );

    // ========================================================================
    // Read mux (combinational)
    // ========================================================================
    wire [31:0] fifo_status = {14'd0, m_rx_empty, m_tx_full, m_rx_level, m_tx_level};

    always @(*) begin
        case (off)
            OFF_VERSION:  rd_data = VERSION_ID;
            OFF_CTRL:     rd_data = ctrl_reg;
            OFF_STATUS:   rd_data = {24'd0, m_status};
            OFF_PRESCALE: rd_data = prescale_reg;
            OFF_ADDRESS:  rd_data = addr_reg;
            OFF_RXDATA:   rd_data = {24'd0, m_rx_rdata};
            OFF_INTEN:    rd_data = inten_reg;
            OFF_INTSTAT:  rd_data = {24'd0, m_int_status};
            OFF_FIFOCTRL: rd_data = fifoctrl_reg;
            OFF_FIFOSTAT: rd_data = fifo_status;
            OFF_TIMEOUT:  rd_data = timeout_reg;
            OFF_ERRSTAT:  rd_data = {27'd0, m_err_status};
            default:      rd_data = 32'd0;   // COMMAND/DATA_CMD (WO) và offset lạ
        endcase
    end

endmodule
