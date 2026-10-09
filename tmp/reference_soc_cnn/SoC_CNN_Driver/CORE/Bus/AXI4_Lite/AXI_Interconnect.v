// ==========================================================
// AXI4-Lite Interconnect
// Single Master -> Multi Slave (4 Slaves)
//
// Memory Map
// ----------------------------------------------------------
// Slave 0: RAM
// Slave 1: AXI_to_APB4_Bridge
// Slave 2: VGA
// Slave 3: ROM (Read-only)
// ==========================================================

module AXI_Interconnect #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input                       clk,
    input                       reset,

    // ===============================
    // AXI MASTER SIDE
    // ===============================

    // WRITE ADDRESS CHANNEL
    input  [ADDR_WIDTH - 1:0]   m_axi_awaddr,
    input                       m_axi_awvalid,
    output                      m_axi_awready,

    // WRITE DATA CHANNEL
    input  [DATA_WIDTH - 1:0]   m_axi_wdata,
    input  [DATA_WIDTH/8-1:0]   m_axi_wstrb,    // FIX [1]: DATA_WIDTH/8, không phải DATA_WIDTH
    input                       m_axi_wvalid,
    output                      m_axi_wready,

    // WRITE RESPONSE CHANNEL
    output [1:0]                m_axi_bresp,
    output                      m_axi_bvalid,
    input                       m_axi_bready,

    // READ ADDRESS CHANNEL
    input  [ADDR_WIDTH - 1:0]   m_axi_araddr,
    input                       m_axi_arvalid,
    output                      m_axi_arready,

    // READ DATA CHANNEL
    output [DATA_WIDTH - 1:0]   m_axi_rdata,
    output [1:0]                m_axi_rresp,
    output                      m_axi_rvalid,
    input                       m_axi_rready,

    // ===============================
    // AXI SLAVE 0: RAM
    // ===============================
    output [ADDR_WIDTH - 1:0]   s0_axi_awaddr,
    output                      s0_axi_awvalid,
    input                       s0_axi_awready,

    output [DATA_WIDTH - 1:0]   s0_axi_wdata,
    output [DATA_WIDTH/8-1:0]   s0_axi_wstrb,
    output                      s0_axi_wvalid,
    input                       s0_axi_wready,

    input  [1:0]                s0_axi_bresp,
    input                       s0_axi_bvalid,
    output                      s0_axi_bready,

    output [ADDR_WIDTH - 1:0]   s0_axi_araddr,
    output                      s0_axi_arvalid,
    input                       s0_axi_arready,

    input  [DATA_WIDTH - 1:0]   s0_axi_rdata,
    input  [1:0]                s0_axi_rresp,
    input                       s0_axi_rvalid,
    output                      s0_axi_rready,

    // ===============================
    // AXI SLAVE 1: APB
    // ===============================
    output [ADDR_WIDTH - 1:0]   s1_axi_awaddr,
    output                      s1_axi_awvalid,
    input                       s1_axi_awready,

    output [DATA_WIDTH - 1:0]   s1_axi_wdata,
    output [DATA_WIDTH/8-1:0]   s1_axi_wstrb,
    output                      s1_axi_wvalid,
    input                       s1_axi_wready,

    input  [1:0]                s1_axi_bresp,
    input                       s1_axi_bvalid,
    output                      s1_axi_bready,

    output [ADDR_WIDTH - 1:0]   s1_axi_araddr,
    output                      s1_axi_arvalid,
    input                       s1_axi_arready,

    input  [DATA_WIDTH - 1:0]   s1_axi_rdata,
    input  [1:0]                s1_axi_rresp,
    input                       s1_axi_rvalid,
    output                      s1_axi_rready,

    // ===============================
    // AXI SLAVE 2: VGA
    // ===============================
    output [ADDR_WIDTH - 1:0]   s2_axi_awaddr,
    output                      s2_axi_awvalid,
    input                       s2_axi_awready,

    output [DATA_WIDTH - 1:0]   s2_axi_wdata,
    output [DATA_WIDTH/8-1:0]   s2_axi_wstrb,
    output                      s2_axi_wvalid,
    input                       s2_axi_wready,

    input  [1:0]                s2_axi_bresp,
    input                       s2_axi_bvalid,
    output                      s2_axi_bready,

    output [ADDR_WIDTH - 1:0]   s2_axi_araddr,
    output                      s2_axi_arvalid,
    input                       s2_axi_arready,

    input  [DATA_WIDTH - 1:0]   s2_axi_rdata,
    input  [1:0]                s2_axi_rresp,
    input                       s2_axi_rvalid,
    output                      s2_axi_rready,

    // ===============================
    // AXI SLAVE 3: ROM
    // ===============================
    output [ADDR_WIDTH - 1:0]   s3_axi_awaddr,
    output                      s3_axi_awvalid,
    input                       s3_axi_awready,

    output [DATA_WIDTH - 1:0]   s3_axi_wdata,
    output [DATA_WIDTH/8-1:0]   s3_axi_wstrb,
    output                      s3_axi_wvalid,
    input                       s3_axi_wready,

    input  [1:0]                s3_axi_bresp,
    input                       s3_axi_bvalid,
    output                      s3_axi_bready,

    output [ADDR_WIDTH - 1:0]   s3_axi_araddr,
    output                      s3_axi_arvalid,
    input                       s3_axi_arready,

    input  [DATA_WIDTH - 1:0]   s3_axi_rdata,
    input  [1:0]                s3_axi_rresp,
    input                       s3_axi_rvalid,
    output                      s3_axi_rready
);

    // ==========================================================
    // MEMORY MAP
    // ==========================================================
    localparam ROM_BASE  = 32'h0000_0000;
    localparam ROM_SIZE  = 32'h0000_1000;
    localparam ROM_END   = ROM_BASE + ROM_SIZE - 1;

    localparam RAM_BASE  = 32'h0001_0000;
    localparam RAM_SIZE  = 32'h0000_1000;
    localparam RAM_END   = RAM_BASE + RAM_SIZE - 1;

    localparam GPIO_BASE = 32'h1000_0000;
    localparam GPIO_SIZE = 32'h0000_0100;
    localparam GPIO_END  = GPIO_BASE + GPIO_SIZE - 1;

    localparam UART_BASE = 32'h2000_0000;
    localparam UART_SIZE = 32'h0000_0100;
    localparam UART_END  = UART_BASE + UART_SIZE - 1;

    localparam VGA_BASE  = 32'h3000_0000;
    localparam VGA_SIZE  = 32'h0000_5000;
    localparam VGA_END   = VGA_BASE + VGA_SIZE - 1;

    localparam I2C_BASE  = 32'h4000_0000;
    localparam I2C_SIZE  = 32'h0000_0100;
    localparam I2C_END   = I2C_BASE + I2C_SIZE - 1;

    // Slave ID encoding
    localparam SEL_RAM  = 3'd0;
    localparam SEL_APB  = 3'd1;
    localparam SEL_VGA  = 3'd2;
    localparam SEL_ROM  = 3'd3;

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // ==========================================================
    // ADDRESS DECODE — combinational, chỉ dùng lúc handshake
    // ==========================================================
    wire dec_ram_write  = (m_axi_awaddr >= RAM_BASE)  && (m_axi_awaddr <= RAM_END);
    wire dec_gpio_write = (m_axi_awaddr >= GPIO_BASE) && (m_axi_awaddr <= GPIO_END);
    wire dec_uart_write = (m_axi_awaddr >= UART_BASE) && (m_axi_awaddr <= UART_END);
    wire dec_i2c_write  = (m_axi_awaddr >= I2C_BASE)  && (m_axi_awaddr <= I2C_END);
    wire dec_apb_write  = (dec_gpio_write) || (dec_uart_write) || (dec_i2c_write);
    wire dec_vga_write  = (m_axi_awaddr >= VGA_BASE)  && (m_axi_awaddr <= VGA_END);
    wire dec_rom_write  = (m_axi_awaddr >= ROM_BASE)  && (m_axi_awaddr <= ROM_END);
    wire dec_hit_write  = dec_ram_write | dec_apb_write | dec_vga_write | dec_rom_write;

    wire dec_ram_read  = (m_axi_araddr >= RAM_BASE)  && (m_axi_araddr <= RAM_END);
    wire dec_gpio_read = (m_axi_araddr >= GPIO_BASE) && (m_axi_araddr <= GPIO_END);
    wire dec_uart_read = (m_axi_araddr >= UART_BASE) && (m_axi_araddr <= UART_END);
    wire dec_i2c_read  = (m_axi_araddr >= I2C_BASE)  && (m_axi_araddr <= I2C_END);
    wire dec_apb_read  = (dec_gpio_read) || (dec_uart_read) || (dec_i2c_read);
    wire dec_vga_read  = (m_axi_araddr >= VGA_BASE)  && (m_axi_araddr <= VGA_END);
    wire dec_rom_read  = (m_axi_araddr >= ROM_BASE)  && (m_axi_araddr <= ROM_END);
    wire dec_hit_read  = dec_ram_read | dec_apb_read | dec_vga_read | dec_rom_read;

    // ==========================================================
    // WRITE SEL REGISTER
    // Lock slave selection tại thời điểm AW handshake
    // Giải phóng sau B handshake
    // Đảm bảo W channel và B channel route đúng slave
    // dù Master hạ awaddr sau handshake
    // ==========================================================
    reg [2:0] sel_write_reg;    // Slave đã được chọn
    reg       sel_write_lock;   // 1 = đang có write transaction
    reg       sel_write_err;    // 1 = address miss → cần trả SLVERR

    // Slave index tại thời điểm AW
    wire [2:0] dec_write_sel = dec_ram_write  ? SEL_RAM  :
                               dec_apb_write  ? SEL_APB  :
                               dec_vga_write  ? SEL_VGA  :
                               dec_rom_write  ? SEL_ROM  : SEL_VGA;

    always @(posedge clk) begin
        if (!reset) begin
            sel_write_reg  <= SEL_RAM;
            sel_write_lock <= 1'b0;
            sel_write_err  <= 1'b0;
        end
        else begin
            // Lock tại AW handshake
            if (!sel_write_lock && m_axi_awvalid && m_axi_awready) begin
                sel_write_reg  <= dec_write_sel;
                sel_write_err  <= !dec_hit_write;   // address miss
                sel_write_lock <= 1'b1;
            end

            // Giải phóng sau B handshake
            if (m_axi_bvalid && m_axi_bready) begin
                sel_write_lock <= 1'b0;
                sel_write_err  <= 1'b0;
            end
        end
    end

    // Helper: slave đang được chọn cho write
    // Gate bằng !sel_write_err để miss address (default SEL_VGA) không route sai
    wire sel_w_ram  = sel_write_lock && (sel_write_reg == SEL_RAM)  && !sel_write_err;
    wire sel_w_apb  = sel_write_lock && (sel_write_reg == SEL_APB)  && !sel_write_err;
    wire sel_w_vga  = sel_write_lock && (sel_write_reg == SEL_VGA)  && !sel_write_err;
    wire sel_w_rom  = sel_write_lock && (sel_write_reg == SEL_ROM)  && !sel_write_err;

    // ==========================================================
    // READ SEL REGISTER
    // Lock slave selection tại thời điểm AR handshake
    // Giải phóng sau R handshake
    // ==========================================================
    reg [2:0] sel_read_reg;
    reg       sel_read_lock;
    reg       sel_read_err;

    wire [2:0] dec_read_sel = dec_ram_read   ? SEL_RAM  :
                              dec_apb_read   ? SEL_APB  :
                              dec_vga_read   ? SEL_VGA  :
                              dec_rom_read   ? SEL_ROM  : SEL_VGA;

    always @(posedge clk) begin
        if (!reset) begin
            sel_read_reg  <= SEL_RAM;
            sel_read_lock <= 1'b0;
            sel_read_err  <= 1'b0;
        end
        else begin
            // Lock tại AR handshake
            if (!sel_read_lock && m_axi_arvalid && m_axi_arready) begin
                sel_read_reg  <= dec_read_sel;
                sel_read_err  <= !dec_hit_read;
                sel_read_lock <= 1'b1;
            end

            // Giải phóng sau R handshake
            if (m_axi_rvalid && m_axi_rready) begin
                sel_read_lock <= 1'b0;
                sel_read_err  <= 1'b0;
            end
        end
    end

    // Helper: slave đang được chọn cho read
    // Gate bằng !sel_read_err để miss address (default SEL_VGA) không route sai
    wire sel_r_ram  = sel_read_lock && (sel_read_reg == SEL_RAM)  && !sel_read_err;
    wire sel_r_apb  = sel_read_lock && (sel_read_reg == SEL_APB)  && !sel_read_err;
    wire sel_r_vga  = sel_read_lock && (sel_read_reg == SEL_VGA)  && !sel_read_err;
    wire sel_r_rom  = sel_read_lock && (sel_read_reg == SEL_ROM)  && !sel_read_err;

    // ==========================================================
    // ERROR SLAVE — WRITE
    // Khi địa chỉ không khớp slave nào, error slave tự sinh
    // bvalid + SLVERR sau khi nhận đủ AW và W handshake
    // ==========================================================
    reg err_aw_done;    // Đã nhận AW miss
    reg err_w_done;     // Đã nhận W  miss
    reg err_bvalid;     // Error slave đang giữ bvalid

    wire dec_err_now;

    always @(posedge clk) begin
        if (!reset) begin
            err_aw_done <= 1'b0;
            err_w_done  <= 1'b0;
            err_bvalid  <= 1'b0;
        end
        else begin
            // AW handshake với address miss
            if (!sel_write_lock && m_axi_awvalid && m_axi_awready && !dec_hit_write)
                err_aw_done <= 1'b1;

            // W handshake (dùng err_aw_done HOẶC dec_err_now để chắc chắn đây là miss transaction)
            // dec_err_now bắt case master gửi AW+W cùng cycle với miss address
            //      (err_aw_done chưa kịp commit ở cycle đó → cần dec_err_now bypass)
            if ((err_aw_done || dec_err_now) && m_axi_wvalid && m_axi_wready)
                err_w_done <= 1'b1;

            // Đủ AW + W → assert bvalid
            if (err_aw_done && err_w_done && !err_bvalid)
                err_bvalid <= 1'b1;

            // B handshake
            if (err_bvalid && m_axi_bready) begin
                err_bvalid  <= 1'b0;
                err_aw_done <= 1'b0;
                err_w_done  <= 1'b0;
            end
        end
    end

    // ==========================================================
    // ERROR SLAVE — READ
    // Khi địa chỉ không khớp slave nào, error slave tự sinh
    // rvalid + SLVERR
    // ==========================================================
    reg err_ar_done;
    reg err_rvalid;

    always @(posedge clk) begin
        if (!reset) begin
            err_ar_done <= 1'b0;
            err_rvalid  <= 1'b0;
        end
        else begin
            if (!sel_read_lock && m_axi_arvalid && m_axi_arready && !dec_hit_read)
                err_ar_done <= 1'b1;

            if (err_ar_done && !err_rvalid)
                err_rvalid <= 1'b1;

            if (err_rvalid && m_axi_rready) begin
                err_rvalid  <= 1'b0;
                err_ar_done <= 1'b0;
            end
        end
    end

    // ==========================================================
    // WRITE ADDRESS CHANNEL → Slaves
    // awready cần trả về trước khi lock (không có transaction đang chạy)
    // ==========================================================

    // AW chỉ forward khi chưa lock và address hợp lệ
    assign s0_axi_awaddr  = m_axi_awaddr;
    assign s1_axi_awaddr  = m_axi_awaddr;
    assign s2_axi_awaddr  = m_axi_awaddr;
    assign s3_axi_awaddr  = m_axi_awaddr;

    assign s0_axi_awvalid = m_axi_awvalid & dec_ram_write  & !sel_write_lock;
    assign s1_axi_awvalid = m_axi_awvalid & dec_apb_write  & !sel_write_lock;
    assign s2_axi_awvalid = m_axi_awvalid & dec_vga_write  & !sel_write_lock;
    assign s3_axi_awvalid = m_axi_awvalid & dec_rom_write  & !sel_write_lock;

    // awready: từ slave đúng khi chưa lock; 1 khi address miss (absorb ngay)
    assign m_axi_awready  = !sel_write_lock && (
                                dec_ram_write  ? s0_axi_awready :
                                dec_apb_write  ? s1_axi_awready :
                                dec_vga_write  ? s2_axi_awready :
                                dec_rom_write  ? s3_axi_awready :
                                                 1'b1            // miss: absorb
                            );

    // ==========================================================
    // WRITE DATA CHANNEL → Slaves
    // Route theo sel_write_reg (locked), không phải awaddr
    // ==========================================================

    // ==========================================================
    // SAME-CYCLE AW/W SUPPORT
    // AXI4-Lite cho phép AW và W cùng cycle
    // ==========================================================

    wire aw_handshake;

    assign aw_handshake = m_axi_awvalid && m_axi_awready;

    assign dec_err_now  = aw_handshake && !dec_hit_write;

    // chỉ bypass đúng cycle AW handshake
    wire dec_w_ram_now  = aw_handshake && dec_ram_write;

    wire dec_w_apb_now  = aw_handshake && dec_apb_write;

    wire dec_w_vga_now  = aw_handshake && dec_vga_write;

    wire dec_w_rom_now  = aw_handshake && dec_rom_write;

    assign s0_axi_wdata  = m_axi_wdata;
    assign s0_axi_wstrb  = m_axi_wstrb;
    assign s1_axi_wdata  = m_axi_wdata;
    assign s1_axi_wstrb  = m_axi_wstrb;
    assign s2_axi_wdata  = m_axi_wdata;
    assign s2_axi_wstrb  = m_axi_wstrb;
    assign s3_axi_wdata  = m_axi_wdata;
    assign s3_axi_wstrb  = m_axi_wstrb;

    // wvalid forward đến đúng slave đã lock
    // Khi address miss: err_aw_done đã set, forward wvalid → wready=1 (absorb)
    assign s0_axi_wvalid = m_axi_wvalid & (sel_w_ram  | dec_w_ram_now);
    assign s1_axi_wvalid = m_axi_wvalid & (sel_w_apb  | dec_w_apb_now);
    assign s2_axi_wvalid = m_axi_wvalid & (sel_w_vga  | dec_w_vga_now);
    assign s3_axi_wvalid = m_axi_wvalid & (sel_w_rom  | dec_w_rom_now);

    // wready: từ slave đã lock; 1 khi miss (absorb W data)
    assign m_axi_wready  =
    // locked transaction
    sel_w_ram      ? s0_axi_wready :
    sel_w_apb      ? s1_axi_wready :
    sel_w_vga      ? s2_axi_wready :
    sel_w_rom      ? s3_axi_wready :

    // same-cycle AW/W support
    dec_w_ram_now  ? s0_axi_wready :
    dec_w_apb_now  ? s1_axi_wready :
    dec_w_vga_now  ? s2_axi_wready :
    dec_w_rom_now  ? s3_axi_wready :

    // error slave
    sel_write_err ? 1'b1 :
    dec_err_now   ? 1'b1 :
                    1'b0;

    // ==========================================================
    // WRITE RESPONSE CHANNEL ← Slaves
    // bvalid = 0 mặc định; lên khi slave hoặc error slave response
    // ==========================================================
    assign s0_axi_bready = m_axi_bready & sel_w_ram;
    assign s1_axi_bready = m_axi_bready & sel_w_apb;
    assign s2_axi_bready = m_axi_bready & sel_w_vga;
    assign s3_axi_bready = m_axi_bready & sel_w_rom;

    assign m_axi_bvalid  = sel_w_ram    ? s0_axi_bvalid :
                           sel_w_apb    ? s1_axi_bvalid :
                           sel_w_vga    ? s2_axi_bvalid :
                           sel_w_rom    ? s3_axi_bvalid :
                           err_bvalid   ? 1'b1          :   // error slave
                                          1'b0;             // không phantom

    assign m_axi_bresp   = sel_w_ram    ? s0_axi_bresp  :
                           sel_w_apb    ? s1_axi_bresp  :
                           sel_w_vga    ? s2_axi_bresp  :
                           sel_w_rom    ? s3_axi_bresp  :
                           err_bvalid   ? RESP_SLVERR   :
                                          RESP_OKAY;

    // ==========================================================
    // READ ADDRESS CHANNEL → Slaves
    // ==========================================================
    assign s0_axi_araddr  = m_axi_araddr;
    assign s1_axi_araddr  = m_axi_araddr;
    assign s2_axi_araddr  = m_axi_araddr;
    assign s3_axi_araddr  = m_axi_araddr;

    assign s0_axi_arvalid = m_axi_arvalid & dec_ram_read  & !sel_read_lock;
    assign s1_axi_arvalid = m_axi_arvalid & dec_apb_read  & !sel_read_lock;
    assign s2_axi_arvalid = m_axi_arvalid & dec_vga_read  & !sel_read_lock;
    assign s3_axi_arvalid = m_axi_arvalid & dec_rom_read  & !sel_read_lock;

    assign m_axi_arready  = !sel_read_lock && (
                                dec_ram_read  ? s0_axi_arready :
                                dec_apb_read  ? s1_axi_arready :
                                dec_vga_read  ? s2_axi_arready :
                                dec_rom_read  ? s3_axi_arready :
                                                1'b1             // miss: absorb
                            );

    // ==========================================================
    // READ DATA CHANNEL ← Slaves
    // rvalid = 0 mặc định
    // route theo sel_read_reg (locked)
    // ==========================================================
    assign s0_axi_rready = m_axi_rready & sel_r_ram;
    assign s1_axi_rready = m_axi_rready & sel_r_apb;
    assign s2_axi_rready = m_axi_rready & sel_r_vga;
    assign s3_axi_rready = m_axi_rready & sel_r_rom;

    assign m_axi_rvalid  = sel_r_ram    ? s0_axi_rvalid  :
                           sel_r_apb    ? s1_axi_rvalid  :
                           sel_r_vga    ? s2_axi_rvalid  :
                           sel_r_rom    ? s3_axi_rvalid  :
                           err_rvalid   ? 1'b1           :   // error slave
                                          1'b0;              // không phantom

    assign m_axi_rresp   = sel_r_ram    ? s0_axi_rresp   :
                           sel_r_apb    ? s1_axi_rresp   :
                           sel_r_vga    ? s2_axi_rresp   :
                           sel_r_rom    ? s3_axi_rresp   :
                           err_rvalid   ? RESP_SLVERR    :
                                          RESP_OKAY;

    assign m_axi_rdata   = sel_r_ram    ? s0_axi_rdata   :
                           sel_r_apb    ? s1_axi_rdata   :
                           sel_r_vga    ? s2_axi_rdata   :
                           sel_r_rom    ? s3_axi_rdata   :
                                          {DATA_WIDTH{1'b0}};

endmodule