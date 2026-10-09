// ============================================================================
// Module AXI_TOP
// ----------------------------------------------------------------------------
// AXI4-Lite + APB4 SoC Subsystem
//
// Architecture
// ----------------------------------------------------------------------------
// CPU memory interface
//        |
//        v
// AXI_Manager
//        |
//        v
// AXI_Interconnect
//   |          |                 |          |
//   |          |                 |          |
//   v          v                 v          v
// AXI_RAM   AXI_to_APB4       AXI_VGA    AXI_ROM
//             Bridge
//               |
//               v
//       APB4_Interconnect
//          |          |
//          v          v
//     APB4_GPIO   APB4_UART
//
// Memory Map
// ----------------------------------------------------------------------------
// 0x0000_0000 - 0x0000_0FFF : ROM  (AXI, read-only)
// 0x0001_0000 - 0x0001_0FFF : RAM  (AXI)
// 0x1000_0000 - 0x1000_00FF : GPIO (AXI -> APB4)
// 0x2000_0000 - 0x2000_00FF : UART (AXI -> APB4)
// 0x3000_0000 - 0x3000_4FFF : VGA  (AXI)
//
// Reset convention
// ----------------------------------------------------------------------------
// reset = 0 : synchronous reset active
// reset = 1 : normal operation
// ============================================================================

module AXI_TOP #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(

    input clk, 
    input reset,

    input [ADDR_WIDTH - 1:0]    mem_addr,
    input [DATA_WIDTH - 1:0]    mem_wdata,
    input [DATA_WIDTH/8 - 1:0]  mem_wstrb,          // Byte enable từ CPU
    input                       mem_we,
    input                       mem_re,
    output [DATA_WIDTH - 1:0]   mem_rdata,
    output                      mem_ready,

    input [9:0] SW,

    input UART_RX,

    output UART_TX,

    output [9:0] LEDR,

    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5,

    output VGA_HS,
    output VGA_VS,

    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,

    inout  I2C_SCL,
    inout  I2C_SDA,
    output i2c_irq
);

    // ==============================================
    // AXI MANAGER INTERFACE
    // ==============================================

    // ================= WRITE ADDRESS ==============
    wire [ADDR_WIDTH - 1:0] m_axi_awaddr;
    wire                    m_axi_awvalid;
    wire                    m_axi_awready;

    // ================= WRITE DATA ==============
    wire [DATA_WIDTH - 1:0] m_axi_wdata;
    wire [DATA_WIDTH/8-1:0] m_axi_wstrb;
    wire                    m_axi_wvalid;
    wire                    m_axi_wready;

    // ================= WRITE RESPONSE ==============
    wire [1:0]              m_axi_bresp;
    wire                    m_axi_bvalid;
    wire                    m_axi_bready;

    // ================= READ ADDRESS ==============
    wire [ADDR_WIDTH - 1:0] m_axi_araddr;
    wire                    m_axi_arvalid;
    wire                    m_axi_arready;

    // ================= READ DATA ==============
    wire [DATA_WIDTH - 1:0] m_axi_rdata;
    wire [1:0]              m_axi_rresp;
    wire                    m_axi_rvalid;
    wire                    m_axi_rready;

    // ==============================================
    // RAM SLAVE AXI
    // ==============================================
    wire [ADDR_WIDTH - 1:0] ram_axi_awaddr;
    wire                    ram_axi_awvalid;
    wire                    ram_axi_awready;

    wire [DATA_WIDTH - 1:0] ram_axi_wdata;
    wire [DATA_WIDTH/8-1:0] ram_axi_wstrb;
    wire                    ram_axi_wvalid;
    wire                    ram_axi_wready;

    wire [1:0]              ram_axi_bresp;
    wire                    ram_axi_bvalid;
    wire                    ram_axi_bready;

    wire [ADDR_WIDTH - 1:0] ram_axi_araddr;
    wire                    ram_axi_arvalid;
    wire                    ram_axi_arready;

    wire [DATA_WIDTH - 1:0] ram_axi_rdata;
    wire [1:0]              ram_axi_rresp;
    wire                    ram_axi_rvalid;
    wire                    ram_axi_rready;

    // ==============================================
    // APB SLAVE AXI
    // ==============================================
    wire [ADDR_WIDTH - 1:0] apb_bridge_axi_awaddr;
    wire                    apb_bridge_axi_awvalid;
    wire                    apb_bridge_axi_awready;

    wire [DATA_WIDTH - 1:0] apb_bridge_axi_wdata;
    wire [DATA_WIDTH/8-1:0] apb_bridge_axi_wstrb;
    wire                    apb_bridge_axi_wvalid;
    wire                    apb_bridge_axi_wready;

    wire [1:0]              apb_bridge_axi_bresp;
    wire                    apb_bridge_axi_bvalid;
    wire                    apb_bridge_axi_bready;

    wire [ADDR_WIDTH - 1:0] apb_bridge_axi_araddr;
    wire                    apb_bridge_axi_arvalid;
    wire                    apb_bridge_axi_arready;

    wire [DATA_WIDTH - 1:0] apb_bridge_axi_rdata;
    wire [1:0]              apb_bridge_axi_rresp;
    wire                    apb_bridge_axi_rvalid;
    wire                    apb_bridge_axi_rready;

    // ==============================================
    // VGA SLAVE AXI
    // ==============================================
    wire [ADDR_WIDTH - 1:0] vga_axi_awaddr;
    wire                    vga_axi_awvalid;
    wire                    vga_axi_awready;

    wire [DATA_WIDTH - 1:0] vga_axi_wdata;
    wire [DATA_WIDTH/8-1:0] vga_axi_wstrb;
    wire                    vga_axi_wvalid;
    wire                    vga_axi_wready;

    wire [1:0]              vga_axi_bresp;
    wire                    vga_axi_bvalid;
    wire                    vga_axi_bready;

    wire [ADDR_WIDTH - 1:0] vga_axi_araddr;
    wire                    vga_axi_arvalid;
    wire                    vga_axi_arready;

    wire [DATA_WIDTH - 1:0] vga_axi_rdata;
    wire [1:0]              vga_axi_rresp;
    wire                    vga_axi_rvalid;
    wire                    vga_axi_rready;

    // ==============================================
    // ROM SLAVE AXI (read-only)
    // ==============================================
    wire [ADDR_WIDTH - 1:0] rom_axi_awaddr;
    wire                    rom_axi_awvalid;
    wire                    rom_axi_awready;

    wire [DATA_WIDTH - 1:0] rom_axi_wdata;
    wire [DATA_WIDTH/8-1:0] rom_axi_wstrb;
    wire                    rom_axi_wvalid;
    wire                    rom_axi_wready;

    wire [1:0]              rom_axi_bresp;
    wire                    rom_axi_bvalid;
    wire                    rom_axi_bready;

    wire [ADDR_WIDTH - 1:0] rom_axi_araddr;
    wire                    rom_axi_arvalid;
    wire                    rom_axi_arready;

    wire [DATA_WIDTH - 1:0] rom_axi_rdata;
    wire [1:0]              rom_axi_rresp;
    wire                    rom_axi_rvalid;
    wire                    rom_axi_rready;

    // ==============================================
    // APB Master Bus
    // ==============================================
    wire [ADDR_WIDTH - 1:0] m_apb_paddr;
    wire                    m_apb_psel;
    wire                    m_apb_penable;
    wire                    m_apb_pwrite;
    wire [DATA_WIDTH - 1:0] m_apb_pwdata;
    wire [DATA_WIDTH/8-1:0] m_apb_pstrb;
    wire [2:0]              m_apb_pprot;

    wire [DATA_WIDTH - 1:0] m_apb_prdata;
    wire                    m_apb_pready;
    wire                    m_apb_pslverr;

    // =========================================================================
    // AXI MANAGER
    // =========================================================================
    //
    // NOTE:
    // Hiện tại dùng manager standalone để test subsystem
    // Sau này CPU_BUS_TO_AXI sẽ nối vào đây
    //
    // =========================================================================
    AXI_Manager manager (

        .clk                (clk),
        .reset              (reset),

        .mem_addr           (mem_addr),
        .mem_wdata          (mem_wdata),
        .mem_wstrb          (mem_wstrb),
        .mem_we             (mem_we),
        .mem_re             (mem_re),
        .mem_rdata          (mem_rdata),
        .mem_ready          (mem_ready),

        // WRITE ADDRESS
        .axi_awaddr         (m_axi_awaddr),
        .axi_awvalid        (m_axi_awvalid),
        .axi_awready        (m_axi_awready),

        // WRITE DATA
        .axi_wdata          (m_axi_wdata),
        .axi_wstrb          (m_axi_wstrb),
        .axi_wvalid         (m_axi_wvalid),
        .axi_wready         (m_axi_wready),

        // WRITE RESPONSE
        .axi_bresp          (m_axi_bresp),
        .axi_bvalid         (m_axi_bvalid),
        .axi_bready         (m_axi_bready),

        // READ ADDRESS
        .axi_araddr         (m_axi_araddr),
        .axi_arvalid        (m_axi_arvalid),
        .axi_arready        (m_axi_arready),
        
        // READ DATA
        .axi_rdata          (m_axi_rdata),
        .axi_rresp          (m_axi_rresp),
        .axi_rvalid         (m_axi_rvalid),
        .axi_rready         (m_axi_rready)
    );

    // =========================================================================
    // AXI INTERCONNECT
    // + s0 = RAM
    // + s1 = APB Bridge
    // + s2 = VGA
    // + s3 = ROM
    // =========================================================================
    AXI_Interconnect interconnect (

        .clk                (clk),
        .reset              (reset),

        // ===============================
        // AXI MASTER SIDE
        // ===============================
        .m_axi_awaddr       (m_axi_awaddr),
        .m_axi_awvalid      (m_axi_awvalid),
        .m_axi_awready      (m_axi_awready),

        .m_axi_wdata        (m_axi_wdata),
        .m_axi_wstrb        (m_axi_wstrb),
        .m_axi_wvalid       (m_axi_wvalid),
        .m_axi_wready       (m_axi_wready),

        .m_axi_bresp        (m_axi_bresp),
        .m_axi_bvalid       (m_axi_bvalid),
        .m_axi_bready       (m_axi_bready),

        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),

        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rresp        (m_axi_rresp),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready),

        // ===============================
        // RAM SLAVE
        // ===============================
        .s0_axi_awaddr       (ram_axi_awaddr),
        .s0_axi_awvalid      (ram_axi_awvalid),
        .s0_axi_awready      (ram_axi_awready),

        .s0_axi_wdata        (ram_axi_wdata),
        .s0_axi_wstrb        (ram_axi_wstrb),
        .s0_axi_wvalid       (ram_axi_wvalid),
        .s0_axi_wready       (ram_axi_wready),

        .s0_axi_bresp        (ram_axi_bresp),
        .s0_axi_bvalid       (ram_axi_bvalid),
        .s0_axi_bready       (ram_axi_bready),

        .s0_axi_araddr       (ram_axi_araddr),
        .s0_axi_arvalid      (ram_axi_arvalid),
        .s0_axi_arready      (ram_axi_arready),

        .s0_axi_rdata        (ram_axi_rdata),
        .s0_axi_rresp        (ram_axi_rresp),
        .s0_axi_rvalid       (ram_axi_rvalid),
        .s0_axi_rready       (ram_axi_rready),

        // ===============================
        // AXI_to_APB4_Bridge
        // ===============================
        .s1_axi_awaddr       (apb_bridge_axi_awaddr),
        .s1_axi_awvalid      (apb_bridge_axi_awvalid),
        .s1_axi_awready      (apb_bridge_axi_awready),

        .s1_axi_wdata        (apb_bridge_axi_wdata),
        .s1_axi_wstrb        (apb_bridge_axi_wstrb),
        .s1_axi_wvalid       (apb_bridge_axi_wvalid),
        .s1_axi_wready       (apb_bridge_axi_wready),

        .s1_axi_bresp        (apb_bridge_axi_bresp),
        .s1_axi_bvalid       (apb_bridge_axi_bvalid),
        .s1_axi_bready       (apb_bridge_axi_bready),

        .s1_axi_araddr       (apb_bridge_axi_araddr),
        .s1_axi_arvalid      (apb_bridge_axi_arvalid),
        .s1_axi_arready      (apb_bridge_axi_arready),

        .s1_axi_rdata        (apb_bridge_axi_rdata),
        .s1_axi_rresp        (apb_bridge_axi_rresp),
        .s1_axi_rvalid       (apb_bridge_axi_rvalid),
        .s1_axi_rready       (apb_bridge_axi_rready),

        // ===============================
        // VGA SLAVE
        // ===============================
        .s2_axi_awaddr       (vga_axi_awaddr),
        .s2_axi_awvalid      (vga_axi_awvalid),
        .s2_axi_awready      (vga_axi_awready),

        .s2_axi_wdata        (vga_axi_wdata),
        .s2_axi_wstrb        (vga_axi_wstrb),
        .s2_axi_wvalid       (vga_axi_wvalid),
        .s2_axi_wready       (vga_axi_wready),

        .s2_axi_bresp        (vga_axi_bresp),
        .s2_axi_bvalid       (vga_axi_bvalid),
        .s2_axi_bready       (vga_axi_bready),

        .s2_axi_araddr       (vga_axi_araddr),
        .s2_axi_arvalid      (vga_axi_arvalid),
        .s2_axi_arready      (vga_axi_arready),

        .s2_axi_rdata        (vga_axi_rdata),
        .s2_axi_rresp        (vga_axi_rresp),
        .s2_axi_rvalid       (vga_axi_rvalid),
        .s2_axi_rready       (vga_axi_rready),

        // ===============================
        // ROM SLAVE
        // ===============================
        .s3_axi_awaddr       (rom_axi_awaddr),
        .s3_axi_awvalid      (rom_axi_awvalid),
        .s3_axi_awready      (rom_axi_awready),

        .s3_axi_wdata        (rom_axi_wdata),
        .s3_axi_wstrb        (rom_axi_wstrb),
        .s3_axi_wvalid       (rom_axi_wvalid),
        .s3_axi_wready       (rom_axi_wready),

        .s3_axi_bresp        (rom_axi_bresp),
        .s3_axi_bvalid       (rom_axi_bvalid),
        .s3_axi_bready       (rom_axi_bready),

        .s3_axi_araddr       (rom_axi_araddr),
        .s3_axi_arvalid      (rom_axi_arvalid),
        .s3_axi_arready      (rom_axi_arready),

        .s3_axi_rdata        (rom_axi_rdata),
        .s3_axi_rresp        (rom_axi_rresp),
        .s3_axi_rvalid       (rom_axi_rvalid),
        .s3_axi_rready       (rom_axi_rready)
    );

    // =========================================================================
    // AXI RAM SLAVE
    // =========================================================================
    AXI_RAM_Slave ram_slave (

        .clk                (clk),
        .reset              (reset),

        .s_axi_awaddr       (ram_axi_awaddr),
        .s_axi_awvalid      (ram_axi_awvalid),
        .s_axi_awready      (ram_axi_awready),

        .s_axi_wdata        (ram_axi_wdata),
        .s_axi_wstrb        (ram_axi_wstrb),
        .s_axi_wvalid       (ram_axi_wvalid),
        .s_axi_wready       (ram_axi_wready),

        .s_axi_bresp        (ram_axi_bresp),
        .s_axi_bvalid       (ram_axi_bvalid),
        .s_axi_bready       (ram_axi_bready),

        .s_axi_araddr       (ram_axi_araddr),
        .s_axi_arvalid      (ram_axi_arvalid),
        .s_axi_arready      (ram_axi_arready),

        .s_axi_rdata        (ram_axi_rdata),
        .s_axi_rresp        (ram_axi_rresp),
        .s_axi_rvalid       (ram_axi_rvalid),
        .s_axi_rready       (ram_axi_rready)
    );

    // =========================================================================
    // AXI to APB4 Bridge
    // =========================================================================
    AXI_to_APB4_Bridge axi_to_apb4_bridge (

        .clk                (clk),
        .reset              (reset),

        .s_axi_awaddr       (apb_bridge_axi_awaddr),
        .s_axi_awvalid      (apb_bridge_axi_awvalid),
        .s_axi_awready      (apb_bridge_axi_awready),

        .s_axi_wdata        (apb_bridge_axi_wdata),
        .s_axi_wstrb        (apb_bridge_axi_wstrb),
        .s_axi_wvalid       (apb_bridge_axi_wvalid),
        .s_axi_wready       (apb_bridge_axi_wready),

        .s_axi_bresp        (apb_bridge_axi_bresp),
        .s_axi_bvalid       (apb_bridge_axi_bvalid),
        .s_axi_bready       (apb_bridge_axi_bready),

        .s_axi_araddr       (apb_bridge_axi_araddr),
        .s_axi_arvalid      (apb_bridge_axi_arvalid),
        .s_axi_arready      (apb_bridge_axi_arready),

        .s_axi_rdata        (apb_bridge_axi_rdata),
        .s_axi_rresp        (apb_bridge_axi_rresp),
        .s_axi_rvalid       (apb_bridge_axi_rvalid),
        .s_axi_rready       (apb_bridge_axi_rready),

        .PADDR              (m_apb_paddr),
        .PSEL               (m_apb_psel),
        .PENABLE            (m_apb_penable),
        .PWRITE             (m_apb_pwrite),
        .PWDATA             (m_apb_pwdata),
        .PSTRB              (m_apb_pstrb),
        .PPROT              (m_apb_pprot),
        .PRDATA             (m_apb_prdata),
        .PREADY             (m_apb_pready),
        .PSLVERR            (m_apb_pslverr)
    );
    

    // =========================================================================
    // APB4 TOP
    // =========================================================================
    APB4_TOP apb4_top (

        .clk                (clk),
        .reset              (reset),

        .PADDR              (m_apb_paddr),
        .PSEL               (m_apb_psel),
        .PENABLE            (m_apb_penable),
        .PWRITE             (m_apb_pwrite),
        .PWDATA             (m_apb_pwdata),
        .PSTRB              (m_apb_pstrb),
        .PPROT              (m_apb_pprot),

        .PRDATA             (m_apb_prdata),
        .PREADY             (m_apb_pready),
        .PSLVERR            (m_apb_pslverr),

        .SW                 (SW),
        .LEDR               (LEDR),

        .HEX0               (HEX0),
        .HEX1               (HEX1),
        .HEX2               (HEX2),
        .HEX3               (HEX3),
        .HEX4               (HEX4),
        .HEX5               (HEX5),

        .UART_RX            (UART_RX),
        .UART_TX            (UART_TX),

        .I2C_SCL            (I2C_SCL),
        .I2C_SDA            (I2C_SDA),
        .i2c_irq            (i2c_irq)
    );

    // =========================================================================
    // AXI VGA SLAVE
    // =========================================================================
    AXI_VGA_Slave vga_slave (

        .clk                (clk),
        .reset              (reset),

        .s_axi_awaddr       (vga_axi_awaddr),
        .s_axi_awvalid      (vga_axi_awvalid),
        .s_axi_awready      (vga_axi_awready),

        .s_axi_wdata        (vga_axi_wdata),
        .s_axi_wstrb        (vga_axi_wstrb),
        .s_axi_wvalid       (vga_axi_wvalid),
        .s_axi_wready       (vga_axi_wready),

        .s_axi_bresp        (vga_axi_bresp),
        .s_axi_bvalid       (vga_axi_bvalid),
        .s_axi_bready       (vga_axi_bready),

        .s_axi_araddr       (vga_axi_araddr),
        .s_axi_arvalid      (vga_axi_arvalid),
        .s_axi_arready      (vga_axi_arready),

        .s_axi_rdata        (vga_axi_rdata),
        .s_axi_rresp        (vga_axi_rresp),
        .s_axi_rvalid       (vga_axi_rvalid),
        .s_axi_rready       (vga_axi_rready),

        .VGA_HS             (VGA_HS),
        .VGA_VS             (VGA_VS),

        .VGA_R              (VGA_R),
        .VGA_G              (VGA_G),
        .VGA_B              (VGA_B)
    );

    // =========================================================================
    // AXI ROM SLAVE (read-only)
    // =========================================================================
    AXI_ROM_Slave rom_slave (

        .clk                (clk),
        .reset              (reset),

        .s_axi_awaddr       (rom_axi_awaddr),
        .s_axi_awvalid      (rom_axi_awvalid),
        .s_axi_awready      (rom_axi_awready),

        .s_axi_wdata        (rom_axi_wdata),
        .s_axi_wstrb        (rom_axi_wstrb),
        .s_axi_wvalid       (rom_axi_wvalid),
        .s_axi_wready       (rom_axi_wready),

        .s_axi_bresp        (rom_axi_bresp),
        .s_axi_bvalid       (rom_axi_bvalid),
        .s_axi_bready       (rom_axi_bready),

        .s_axi_araddr       (rom_axi_araddr),
        .s_axi_arvalid      (rom_axi_arvalid),
        .s_axi_arready      (rom_axi_arready),

        .s_axi_rdata        (rom_axi_rdata),
        .s_axi_rresp        (rom_axi_rresp),
        .s_axi_rvalid       (rom_axi_rvalid),
        .s_axi_rready       (rom_axi_rready)
    );

endmodule