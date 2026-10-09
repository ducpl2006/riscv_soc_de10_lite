module APB4_TOP #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input                         clk,
    input                         reset,

    // APB4 master interface from AXI-to-APB bridge
    input  [ADDR_WIDTH-1:0]       PADDR,
    input                         PSEL,
    input                         PENABLE,
    input                         PWRITE,
    input  [DATA_WIDTH-1:0]       PWDATA,
    input  [DATA_WIDTH/8-1:0]     PSTRB,
    input  [2:0]                  PPROT,

    output [DATA_WIDTH-1:0]       PRDATA,
    output                        PREADY,
    output                        PSLVERR,

    // GPIO
    input  [9:0]                  SW,
    output [9:0]                  LEDR,

    output [6:0]                  HEX0,
    output [6:0]                  HEX1,
    output [6:0]                  HEX2,
    output [6:0]                  HEX3,
    output [6:0]                  HEX4,
    output [6:0]                  HEX5,

    // UART
    input                         UART_RX,
    output                        UART_TX,

    // I2C
    inout                         I2C_SCL,
    inout                         I2C_SDA,
    output                        i2c_irq
);

    // APB GPIO wires
    wire [ADDR_WIDTH-1:0]       gpio_paddr;
    wire                        gpio_psel;
    wire                        gpio_penable;
    wire                        gpio_pwrite;
    wire [DATA_WIDTH-1:0]       gpio_pwdata;
    wire [DATA_WIDTH/8-1:0]     gpio_pstrb;
    wire [2:0]                  gpio_pprot;

    wire [DATA_WIDTH-1:0]       gpio_prdata;
    wire                        gpio_pready;
    wire                        gpio_pslverr;

    // APB UART wires
    wire [ADDR_WIDTH-1:0]       uart_paddr;
    wire                        uart_psel;
    wire                        uart_penable;
    wire                        uart_pwrite;
    wire [DATA_WIDTH-1:0]       uart_pwdata;
    wire [DATA_WIDTH/8-1:0]     uart_pstrb;
    wire [2:0]                  uart_pprot;

    wire [DATA_WIDTH-1:0]       uart_prdata;
    wire                        uart_pready;
    wire                        uart_pslverr;

    // APB I2C wires
    wire [ADDR_WIDTH-1:0]       i2c_paddr;
    wire                        i2c_psel;
    wire                        i2c_penable;
    wire                        i2c_pwrite;
    wire [DATA_WIDTH-1:0]       i2c_pwdata;
    wire [DATA_WIDTH/8-1:0]     i2c_pstrb;
    wire [2:0]                  i2c_pprot;

    wire [DATA_WIDTH-1:0]       i2c_prdata;
    wire                        i2c_pready;
    wire                        i2c_pslverr;

    // APB interconnect
    APB4_Interconnect interconnect (
        .m_apb_paddr       (PADDR),
        .m_apb_psel        (PSEL),
        .m_apb_penable     (PENABLE),
        .m_apb_pwrite      (PWRITE),
        .m_apb_pwdata      (PWDATA),
        .m_apb_pstrb       (PSTRB),
        .m_apb_pprot       (PPROT),

        .m_apb_prdata      (PRDATA),
        .m_apb_pready      (PREADY),
        .m_apb_pslverr     (PSLVERR),

        .gpio_apb_paddr    (gpio_paddr),
        .gpio_apb_psel     (gpio_psel),
        .gpio_apb_penable  (gpio_penable),
        .gpio_apb_pwrite   (gpio_pwrite),
        .gpio_apb_pwdata   (gpio_pwdata),
        .gpio_apb_pstrb    (gpio_pstrb),
        .gpio_apb_pprot    (gpio_pprot),
        .gpio_apb_prdata   (gpio_prdata),
        .gpio_apb_pready   (gpio_pready),
        .gpio_apb_pslverr  (gpio_pslverr),

        .uart_apb_paddr    (uart_paddr),
        .uart_apb_psel     (uart_psel),
        .uart_apb_penable  (uart_penable),
        .uart_apb_pwrite   (uart_pwrite),
        .uart_apb_pwdata   (uart_pwdata),
        .uart_apb_pstrb    (uart_pstrb),
        .uart_apb_pprot    (uart_pprot),
        .uart_apb_prdata   (uart_prdata),
        .uart_apb_pready   (uart_pready),
        .uart_apb_pslverr  (uart_pslverr),

        .i2c_apb_paddr     (i2c_paddr),
        .i2c_apb_psel      (i2c_psel),
        .i2c_apb_penable   (i2c_penable),
        .i2c_apb_pwrite    (i2c_pwrite),
        .i2c_apb_pwdata    (i2c_pwdata),
        .i2c_apb_pstrb     (i2c_pstrb),
        .i2c_apb_pprot     (i2c_pprot),
        .i2c_apb_prdata    (i2c_prdata),
        .i2c_apb_pready    (i2c_pready),
        .i2c_apb_pslverr   (i2c_pslverr)
    );

    APB4_GPIO_Slave gpio_slave (
        .clk        (clk),
        .reset      (reset),

        .PADDR      (gpio_paddr),
        .PSEL       (gpio_psel),
        .PENABLE    (gpio_penable),
        .PWRITE     (gpio_pwrite),
        .PWDATA     (gpio_pwdata),
        .PSTRB      (gpio_pstrb),
        .PPROT      (gpio_pprot),

        .PRDATA     (gpio_prdata),
        .PREADY     (gpio_pready),
        .PSLVERR    (gpio_pslverr),

        .SW         (SW),
        .LEDR       (LEDR),

        .HEX0       (HEX0),
        .HEX1       (HEX1),
        .HEX2       (HEX2),
        .HEX3       (HEX3),
        .HEX4       (HEX4),
        .HEX5       (HEX5)
    );

    APB4_UART_Slave uart_slave (
        .clk        (clk),
        .reset      (reset),

        .PADDR      (uart_paddr),
        .PSEL       (uart_psel),
        .PENABLE    (uart_penable),
        .PWRITE     (uart_pwrite),
        .PWDATA     (uart_pwdata),
        .PSTRB      (uart_pstrb),
        .PPROT      (uart_pprot),

        .PRDATA     (uart_prdata),
        .PREADY     (uart_pready),
        .PSLVERR    (uart_pslverr),

        .rx         (UART_RX),
        .tx         (UART_TX)
    );

    APB4_I2C_Slave i2c_slave (
        .clk        (clk),
        .reset      (reset),

        .PADDR      (i2c_paddr),
        .PSEL       (i2c_psel),
        .PENABLE    (i2c_penable),
        .PWRITE     (i2c_pwrite),
        .PWDATA     (i2c_pwdata),
        .PSTRB      (i2c_pstrb),
        .PPROT      (i2c_pprot),

        .PRDATA     (i2c_prdata),
        .PREADY     (i2c_pready),
        .PSLVERR    (i2c_pslverr),

        .irq        (i2c_irq),
        .scl        (I2C_SCL),
        .sda        (I2C_SDA)
    );

endmodule