// ==========================================================
// Module UART_Register_IF
// ----------------------------------------------------------
// UART Register Interface
//
// Register Map
// ----------------------------------------------------------
// 0x00 : TX DATA      (WRITE)
// 0x04 : RX DATA      (READ)
// 0x08 : STATUS       (READ)
//
// STATUS
// ----------------------------------------------------------
// bit[0] : tx_full
// bit[1] : rx_empty
// bit[2] : tx_ready
// bit[3] : rx_irq
// ==========================================================

module UART_Register_IF (

    input clk,
    input reset,

    // ======================================================
    // Register Interface
    // ======================================================
    input [31:0] addr,
    input [31:0] wr_data,
    input        write_en,
    input        read_en,
    
    output reg [31:0] rd_data,

    // ======================================================
    // UART PINS
    // ======================================================
    input rx,
    output tx
);

    // ======================================================
    // UART STATUS
    // ======================================================   
    wire tx_full;
    wire rx_empty;

    wire [7:0] rx_data;

    wire rx_irq;
    wire tx_ready;

    // ======================================================
    // UART CONTROL
    // ======================================================
    reg tx_wr_en;
    reg rx_rd_en;

    // ======================================================
    // ADDRESS OFFSET
    // + Xác định register nào trong peripheral được truy cập
    // + 0x2000_0000 -- TX_DATA
    // + 0x2000_0004 -- RX_DATA
    // + 0x2000_0008 -- STATUS
    // ======================================================
    wire [3:0] offset;
    
    assign offset = addr[5:2];

    // ======================================================
    // UART CORE
    // ======================================================
    UART uart_core (

        // Input
        .clk            (clk),
        .reset          (reset),

        // UART PINS
        .rx             (rx),
        .tx             (tx),

        // TX
        .tx_wr_en       (tx_wr_en),
        .tx_data        (wr_data[7:0]),
        .tx_full        (tx_full),
        .tx_ready       (tx_ready),

        // RX
        .rx_rd_en       (rx_rd_en),
        .rx_data        (rx_data),
        .rx_empty       (rx_empty),

        // Interfaces
        .rx_irq         (rx_irq)
    );

    // ======================================================
    // WRITE PULSE GENERATION
    //
    // Verison mới: Khác write_enable trong MMIO
    // * Tạo 1 xung write đúng 1 xung clock cycle để ghi
    //   dữ liệu vào TX FIFO (Vì FIFO chỉ cần 1 pulse)
    // 
    // ====================================================== 
    always @(posedge clk) begin

        if (!reset) begin
            tx_wr_en <= 1'b0;
        end

        else begin
            // Default
            tx_wr_en <= 1'b0;

            if (write_en && (offset == 4'h0)) begin
                // Chỉ bật trong 1 clock cycle
                if (!tx_full) begin
                    tx_wr_en <= 1'b1;
                end
            end
        end

    end

    // ======================================================
    // RX READ PULSE GENERATION
    // ====================================================== 
    always @(posedge clk) begin
        
        if (!reset) begin
            rx_rd_en <= 1'b0;
        end

        else begin
            // Default
            rx_rd_en <= 1'b0;

            if (read_en && (offset == 4'h1)) begin
                if (!rx_empty) begin
                    rx_rd_en <= 1'b1;
                end
            end
        end

    end

    // ======================================================
    // COMBINATIONAL READ DATA
    // + Async FIFO: rx_data luôn show current head
    // + rd_data combinational --> AXI capture đúng cycle, không bị
    //   off-by-one timing như version registered
    // ======================================================
    always @(*) begin

        case (offset)

            // ======================================
            // RX DATA
            // ======================================
            4'h1: rd_data = {24'b0, rx_data};

            // ======================================
            // STATUS
            // ======================================
            4'h2: rd_data = {28'b0, rx_irq, tx_ready, rx_empty, tx_full};

            // ======================================
            // DEFAULT
            // ======================================
            default: rd_data = 32'b0;

        endcase

    end

endmodule