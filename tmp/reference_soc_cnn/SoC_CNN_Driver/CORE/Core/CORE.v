// ==============================================
// Module CORE
// CPU + AXI 4-Lite
// ==============================================
module CORE (
    
    input           clk,
    input           reset,

    input [9:0]     SW,
    input           GPIO_0,

    output [9:0]    LEDR,
    output [6:0]    HEX0,
    output [6:0]    HEX1,
    output [6:0]    HEX2,
    output [6:0]    HEX3,
    output [6:0]    HEX4,
    output [6:0]    HEX5,

    output          GPIO_1,

    inout           I2C_SCL,
    inout           I2C_SDA,

    output          VGA_HS,
    output          VGA_VS,
    output [3:0]    VGA_R,
    output [3:0]    VGA_G,
    output [3:0]    VGA_B
);

    // ========================================
    // CPU <--> AXI
    // ========================================
    wire [31:0] addr;
    wire [31:0] wdata;
    wire [3:0]  wstrb;          // Byte enable cho SB/SH/SW
    wire [31:0] rdata;
    wire we;
    wire re;
    wire ready;

    // ========================================
    // CPU 
    // ========================================
    CPU cpu (

        .clk            (clk),
        .reset          (reset),

        .read_dataM     (rdata),
        .mem_ready      (ready),

        .addrM          (addr),
        .write_dataM    (wdata),

        .mem_writeM     (we),
        .mem_readM      (re),

        .write_strbM    (wstrb)
    );

    // ========================================
    // AXI SUBSYSTEM
    // ========================================
    AXI_TOP axi_top (

        .clk            (clk),
        .reset          (reset),

        .mem_addr       (addr),
        .mem_wdata      (wdata),
        .mem_wstrb      (wstrb),

        .mem_we         (we),
        .mem_re         (re),

        .mem_rdata      (rdata),
        .mem_ready      (ready),

        .SW             (SW),
        
        .LEDR           (LEDR),

        .UART_RX        (GPIO_0),
        .UART_TX        (GPIO_1),

        .HEX0           (HEX0),
        .HEX1           (HEX1),
        .HEX2           (HEX2),
        .HEX3           (HEX3),
        .HEX4           (HEX4),
        .HEX5           (HEX5),

        .VGA_HS         (VGA_HS),
        .VGA_VS         (VGA_VS),
        .VGA_R          (VGA_R),
        .VGA_G          (VGA_G),
        .VGA_B          (VGA_B),

        .I2C_SCL        (I2C_SCL),
        .I2C_SDA        (I2C_SDA),
        .i2c_irq        ()          // chưa nối interrupt vào CPU (polling qua STATUS)
    );

endmodule