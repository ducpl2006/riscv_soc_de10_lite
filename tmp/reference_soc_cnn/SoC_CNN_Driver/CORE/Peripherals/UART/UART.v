// =================================
// Module UART TOP
// =================================

module UART #(

    parameter CLK_SYS       = 50_000_000,
    parameter BAUD_RATE     = 115200,
    parameter DATA_BITS     = 8,
    parameter OVERSAMPLE    = 16,
    parameter FIFO_WIDTH    = 8,
    parameter FIFO_DEPTH    = 32
)
(
    input clk,
    input reset,

    // UART PINS
    input rx,                   // Tín hiệu nhận được từ CP2102
    output tx,                  // Tín hiệu CPU gửi đi qua CP2102

    // ----------------------------
    // CPU Interface
    // ----------------------------

    // Tx (CPU --> UART)
    input tx_wr_en,                         // Tín hiệu cho phép ghi vào FIFO
    input [DATA_BITS - 1:0] tx_data,        // Dữ liệu cần gửi đi
    output tx_full,                          // Cờ báo FIFO đầy
    output tx_ready,

    // Rx (UART --> CPU)
    input rx_rd_en,                         // Tín hiệu cho phép đọc dữ liệu trong FIFO của rx
    output [DATA_BITS - 1:0] rx_data,       // Dữ liệu CPU nhận được
    output rx_empty,                        // Cờ báo FIFO rỗng

    // Interfacse
    output rx_irq                           // Cờ báo trong FIFO vẫn còn dữ liệu chưa đọc
);

    // =============== BAUD GENERATOR ===============
    wire baud_tick;

    Baud_Gen #(
        .CLK_SYS        (CLK_SYS),
        .BAUD_RATE      (BAUD_RATE),
        .OVERSAMPLE     (OVERSAMPLE)
    ) baud_gen (

        // Input
        .clk            (clk),
        .reset          (reset),
        
        // Ouput
        .baud_tick       (baud_tick)
    );


    // =============== TX PATH ===============
    wire [DATA_BITS - 1:0] tx_fifo_data;
    wire tx_fifo_empty;

    wire rd_en;
    wire i_send;
    reg  [DATA_BITS - 1:0] tx_data_reg;     // Capture byte trước khi FIFO advance

    // =============== FIFO TX ===============
    FIFO #(
        .W              (FIFO_WIDTH),
        .L              (FIFO_DEPTH)
    ) tx_fifo (

        // Input
        .clk            (clk),
        .reset          (reset),
        .write_en       (tx_wr_en),
        .read_en        (rd_en),
        .data_in        (tx_data),

        // Output
        .full           (tx_full),
        .empty          (tx_fifo_empty),
        .data_out       (tx_fifo_data)
    );

    // =============== UART TX ===============
    UART_Tx #(
        .DATA_BITS      (DATA_BITS),
        .OVERSAMPLE     (OVERSAMPLE)
    ) uart_tx (

        // Input
        .clk            (clk),
        .reset          (reset),
        .baud_tick      (baud_tick),
        .data_in        (tx_data_reg),
        .i_send         (i_send),

        // Output
        .tx             (tx),
        .tx_ready       (tx_ready)
    );

    // =============== TX HANDSHAKE (ready/valid) ===============
    wire tx_valid;
    assign tx_valid = ~tx_fifo_empty;

    wire tx_fire;
    reg  rd_en_r;

    // Fire only when: FIFO has data, UART_Tx idle, not already waiting for data
    assign tx_fire = tx_valid & tx_ready & ~rd_en_r;

    always @(posedge clk) begin
        if (!reset) rd_en_r <= 0;
        else        rd_en_r <= tx_fire;
    end

    // Async FIFO: tx_fifo_data luôn show current head
    // Capture data_reg tại cycle rd_en pulse (trước khi FIFO advance ở posedge tiếp theo)
    // i_send fires 1 cycle sau rd_en, dùng giá trị đã captured
    assign rd_en       = tx_fire;
    assign i_send      = rd_en_r;

    always @(posedge clk) begin
        if (!reset)         tx_data_reg <= 0;
        else if (rd_en)     tx_data_reg <= tx_fifo_data;
    end


    // =============== RX PATH ===============
    wire [DATA_BITS - 1:0] rx_data_wire;
    wire rx_valid;
    wire rx_full;

    // =============== UART RX ===============
    UART_Rx #(
        .DATA_BITS      (DATA_BITS),
        .OVERSAMPLE     (OVERSAMPLE)
    ) uart_rx (

        // Input
        .clk            (clk),
        .reset          (reset),
        .baud_tick      (baud_tick),
        .rx             (rx),

        // Ouput 
        .data_out       (rx_data_wire),
        .rx_valid       (rx_valid)
    );

    // =============== FIFO RX ===============
    FIFO #(
        .W              (FIFO_WIDTH),
        .L              (FIFO_DEPTH)
    ) rx_fifo (

        // Input
        .clk            (clk),
        .reset          (reset),
        .write_en       (rx_valid && !rx_full),
        .read_en        (rx_rd_en),
        .data_in        (rx_data_wire),
        
        // Output
        .full           (rx_full),
        .empty          (rx_empty),
        .data_out       (rx_data)
    );


    // =============== FIFO RX ===============
    assign rx_irq   = !rx_empty;

endmodule