`timescale 1ns/1ps

// ======================================================
// Testbench: tb_AXI_Interconnect
// Kiểm tra AXI_Interconnect (Single Master, 4 Slaves)
// ------------------------------------------------------
// Testbench tích hợp 4 Slave BFM (Bus Functional Model)
// Mỗi BFM mô phỏng slave thực: lưu data, trả response
// ------------------------------------------------------
// Test cases:
//   TC1  : Write + Read đến từng slave (RAM/GPIO/UART/VGA)
//   TC2  : Out-of-range address → SLVERR (write + read)
//   TC3  : AW đến trước W nhiều cycle → routing vẫn đúng (sel lock)
//   TC4  : W đến trước AW → routing vẫn đúng
//   TC5  : Back-to-back write → slave khác nhau không xung đột
//   TC6  : Slave bvalid chậm (backpressure) → Interconnect chờ đúng
//   TC7  : Slave rvalid chậm (backpressure) → Interconnect chờ đúng
//   TC8  : Master hạ awaddr sau AW handshake → routing không đổi
// ======================================================

module tb_AXI_Interconnect;

    // =====================================================
    // PARAMETERS
    // =====================================================
    parameter ADDR_WIDTH    = 32;
    parameter DATA_WIDTH    = 32;
    parameter CLK_PERIOD    = 10;
    parameter TIMEOUT_CYC   = 300;

    // Memory map boundaries (khớp với DUT)
    parameter RAM_BASE  = 32'h0000_0000;
    parameter GPIO_BASE = 32'h1000_0000;
    parameter UART_BASE = 32'h2000_0000;
    parameter VGA_BASE  = 32'h3000_0000;
    parameter OOR_ADDR  = 32'hFFFF_0000;   // Out-of-range

    // =====================================================
    // CLOCK / RESET
    // =====================================================
    reg clk;
    reg reset;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =====================================================
    // MASTER → DUT
    // =====================================================
    reg  [ADDR_WIDTH-1:0]   m_axi_awaddr;
    reg                     m_axi_awvalid;
    wire                    m_axi_awready;

    reg  [DATA_WIDTH-1:0]   m_axi_wdata;
    reg  [DATA_WIDTH/8-1:0] m_axi_wstrb;
    reg                     m_axi_wvalid;
    wire                    m_axi_wready;

    wire [1:0]              m_axi_bresp;
    wire                    m_axi_bvalid;
    reg                     m_axi_bready;

    reg  [ADDR_WIDTH-1:0]   m_axi_araddr;
    reg                     m_axi_arvalid;
    wire                    m_axi_arready;

    wire [DATA_WIDTH-1:0]   m_axi_rdata;
    wire [1:0]              m_axi_rresp;
    wire                    m_axi_rvalid;
    reg                     m_axi_rready;

    // =====================================================
    // DUT → SLAVE 0 (RAM)
    // =====================================================
    wire [ADDR_WIDTH-1:0]   s0_axi_awaddr;
    wire                    s0_axi_awvalid;
    reg                     s0_axi_awready;

    wire [DATA_WIDTH-1:0]   s0_axi_wdata;
    wire [DATA_WIDTH/8-1:0] s0_axi_wstrb;
    wire                    s0_axi_wvalid;
    reg                     s0_axi_wready;

    reg  [1:0]              s0_axi_bresp;
    reg                     s0_axi_bvalid;
    wire                    s0_axi_bready;

    wire [ADDR_WIDTH-1:0]   s0_axi_araddr;
    wire                    s0_axi_arvalid;
    reg                     s0_axi_arready;

    reg  [DATA_WIDTH-1:0]   s0_axi_rdata;
    reg  [1:0]              s0_axi_rresp;
    reg                     s0_axi_rvalid;
    wire                    s0_axi_rready;

    // =====================================================
    // DUT → SLAVE 1 (GPIO)
    // =====================================================
    wire [ADDR_WIDTH-1:0]   s1_axi_awaddr;
    wire                    s1_axi_awvalid;
    reg                     s1_axi_awready;

    wire [DATA_WIDTH-1:0]   s1_axi_wdata;
    wire [DATA_WIDTH/8-1:0] s1_axi_wstrb;
    wire                    s1_axi_wvalid;
    reg                     s1_axi_wready;

    reg  [1:0]              s1_axi_bresp;
    reg                     s1_axi_bvalid;
    wire                    s1_axi_bready;

    wire [ADDR_WIDTH-1:0]   s1_axi_araddr;
    wire                    s1_axi_arvalid;
    reg                     s1_axi_arready;

    reg  [DATA_WIDTH-1:0]   s1_axi_rdata;
    reg  [1:0]              s1_axi_rresp;
    reg                     s1_axi_rvalid;
    wire                    s1_axi_rready;

    // =====================================================
    // DUT → SLAVE 2 (UART)
    // =====================================================
    wire [ADDR_WIDTH-1:0]   s2_axi_awaddr;
    wire                    s2_axi_awvalid;
    reg                     s2_axi_awready;

    wire [DATA_WIDTH-1:0]   s2_axi_wdata;
    wire [DATA_WIDTH/8-1:0] s2_axi_wstrb;
    wire                    s2_axi_wvalid;
    reg                     s2_axi_wready;

    reg  [1:0]              s2_axi_bresp;
    reg                     s2_axi_bvalid;
    wire                    s2_axi_bready;

    wire [ADDR_WIDTH-1:0]   s2_axi_araddr;
    wire                    s2_axi_arvalid;
    reg                     s2_axi_arready;

    reg  [DATA_WIDTH-1:0]   s2_axi_rdata;
    reg  [1:0]              s2_axi_rresp;
    reg                     s2_axi_rvalid;
    wire                    s2_axi_rready;

    // =====================================================
    // DUT → SLAVE 3 (VGA)
    // =====================================================
    wire [ADDR_WIDTH-1:0]   s3_axi_awaddr;
    wire                    s3_axi_awvalid;
    reg                     s3_axi_awready;

    wire [DATA_WIDTH-1:0]   s3_axi_wdata;
    wire [DATA_WIDTH/8-1:0] s3_axi_wstrb;
    wire                    s3_axi_wvalid;
    reg                     s3_axi_wready;

    reg  [1:0]              s3_axi_bresp;
    reg                     s3_axi_bvalid;
    wire                    s3_axi_bready;

    wire [ADDR_WIDTH-1:0]   s3_axi_araddr;
    wire                    s3_axi_arvalid;
    reg                     s3_axi_arready;

    reg  [DATA_WIDTH-1:0]   s3_axi_rdata;
    reg  [1:0]              s3_axi_rresp;
    reg                     s3_axi_rvalid;
    wire                    s3_axi_rready;

    // =====================================================
    // DUT INSTANTIATION
    // =====================================================
    AXI_Interconnect #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk            (clk),
        .reset          (reset),

        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),

        .s0_axi_awaddr  (s0_axi_awaddr),  .s0_axi_awvalid (s0_axi_awvalid),
        .s0_axi_awready (s0_axi_awready),
        .s0_axi_wdata   (s0_axi_wdata),   .s0_axi_wstrb   (s0_axi_wstrb),
        .s0_axi_wvalid  (s0_axi_wvalid),  .s0_axi_wready  (s0_axi_wready),
        .s0_axi_bresp   (s0_axi_bresp),   .s0_axi_bvalid  (s0_axi_bvalid),
        .s0_axi_bready  (s0_axi_bready),
        .s0_axi_araddr  (s0_axi_araddr),  .s0_axi_arvalid (s0_axi_arvalid),
        .s0_axi_arready (s0_axi_arready),
        .s0_axi_rdata   (s0_axi_rdata),   .s0_axi_rresp   (s0_axi_rresp),
        .s0_axi_rvalid  (s0_axi_rvalid),  .s0_axi_rready  (s0_axi_rready),

        .s1_axi_awaddr  (s1_axi_awaddr),  .s1_axi_awvalid (s1_axi_awvalid),
        .s1_axi_awready (s1_axi_awready),
        .s1_axi_wdata   (s1_axi_wdata),   .s1_axi_wstrb   (s1_axi_wstrb),
        .s1_axi_wvalid  (s1_axi_wvalid),  .s1_axi_wready  (s1_axi_wready),
        .s1_axi_bresp   (s1_axi_bresp),   .s1_axi_bvalid  (s1_axi_bvalid),
        .s1_axi_bready  (s1_axi_bready),
        .s1_axi_araddr  (s1_axi_araddr),  .s1_axi_arvalid (s1_axi_arvalid),
        .s1_axi_arready (s1_axi_arready),
        .s1_axi_rdata   (s1_axi_rdata),   .s1_axi_rresp   (s1_axi_rresp),
        .s1_axi_rvalid  (s1_axi_rvalid),  .s1_axi_rready  (s1_axi_rready),

        .s2_axi_awaddr  (s2_axi_awaddr),  .s2_axi_awvalid (s2_axi_awvalid),
        .s2_axi_awready (s2_axi_awready),
        .s2_axi_wdata   (s2_axi_wdata),   .s2_axi_wstrb   (s2_axi_wstrb),
        .s2_axi_wvalid  (s2_axi_wvalid),  .s2_axi_wready  (s2_axi_wready),
        .s2_axi_bresp   (s2_axi_bresp),   .s2_axi_bvalid  (s2_axi_bvalid),
        .s2_axi_bready  (s2_axi_bready),
        .s2_axi_araddr  (s2_axi_araddr),  .s2_axi_arvalid (s2_axi_arvalid),
        .s2_axi_arready (s2_axi_arready),
        .s2_axi_rdata   (s2_axi_rdata),   .s2_axi_rresp   (s2_axi_rresp),
        .s2_axi_rvalid  (s2_axi_rvalid),  .s2_axi_rready  (s2_axi_rready),

        .s3_axi_awaddr  (s3_axi_awaddr),  .s3_axi_awvalid (s3_axi_awvalid),
        .s3_axi_awready (s3_axi_awready),
        .s3_axi_wdata   (s3_axi_wdata),   .s3_axi_wstrb   (s3_axi_wstrb),
        .s3_axi_wvalid  (s3_axi_wvalid),  .s3_axi_wready  (s3_axi_wready),
        .s3_axi_bresp   (s3_axi_bresp),   .s3_axi_bvalid  (s3_axi_bvalid),
        .s3_axi_bready  (s3_axi_bready),
        .s3_axi_araddr  (s3_axi_araddr),  .s3_axi_arvalid (s3_axi_arvalid),
        .s3_axi_arready (s3_axi_arready),
        .s3_axi_rdata   (s3_axi_rdata),   .s3_axi_rresp   (s3_axi_rresp),
        .s3_axi_rvalid  (s3_axi_rvalid),  .s3_axi_rready  (s3_axi_rready)
    );

    // =====================================================
    // SLAVE BFM — 4 instances
    // Mỗi slave có:
    //   - Bộ nhớ nội bộ 16 word
    //   - Phản hồi AW/W/AR tức thì (awready=1, wready=1, arready=1)
    //   - Có thể inject delay qua slow_wr / slow_rd flag
    // =====================================================

    // Cờ điều khiển tốc độ response từ test sequence
    reg s0_slow_wr, s0_slow_rd;
    reg s1_slow_wr, s1_slow_rd;
    reg s2_slow_wr, s2_slow_rd;
    reg s3_slow_wr, s3_slow_rd;

    // ---- SLAVE BFM MACRO (dùng `include-style task nếu có tool hỗ trợ,
    //      ở đây viết riêng cho từng slave để tương thích ModelSim/Quartus) ----

    // --- SLAVE 0 BFM ---
    reg [DATA_WIDTH-1:0] s0_mem [0:15];
    reg [3:0]            s0_wr_state;
    reg [ADDR_WIDTH-1:0] s0_wr_addr_lat;
    reg [DATA_WIDTH-1:0] s0_wr_data_lat;
    reg [DATA_WIDTH/8-1:0] s0_wr_strb_lat;
    reg [3:0]            s0_rd_state;
    integer s0_delay_cnt;

    localparam BFM_IDLE=0, BFM_AW=1, BFM_W=2, BFM_B=3, BFM_B_WAIT=4;
    localparam BFM_AR=5, BFM_R=6, BFM_R_WAIT=7;

    always @(posedge clk) begin
        if (!reset) begin
            s0_axi_awready <= 1'b1; s0_axi_wready  <= 1'b1;
            s0_axi_bvalid  <= 1'b0; s0_axi_bresp   <= 2'b00;
            s0_axi_arready <= 1'b1;
            s0_axi_rvalid  <= 1'b0; s0_axi_rresp   <= 2'b00;
            s0_axi_rdata   <= 0;
            s0_wr_state    <= BFM_IDLE; s0_rd_state <= BFM_IDLE;
            s0_delay_cnt   <= 0;
        end else begin
            // --- WRITE FSM ---
            case (s0_wr_state)
                BFM_IDLE: begin
                    s0_axi_awready <= 1'b1; s0_axi_wready <= 1'b1;
                    if (s0_axi_awvalid && s0_axi_awready) begin
                        s0_wr_addr_lat <= s0_axi_awaddr;
                        s0_axi_awready <= 1'b0;
                        s0_wr_state    <= BFM_W;
                    end
                end
                BFM_W: begin
                    s0_axi_wready <= 1'b1;
                    if (s0_axi_wvalid && s0_axi_wready) begin
                        s0_wr_data_lat <= s0_axi_wdata;
                        s0_wr_strb_lat <= s0_axi_wstrb;
                        s0_axi_wready  <= 1'b0;
                        // Ghi vào mem nội bộ
                        if (s0_wr_strb_lat[0]) s0_mem[s0_wr_addr_lat[5:2]][7:0]   <= s0_axi_wdata[7:0];
                        if (s0_wr_strb_lat[1]) s0_mem[s0_wr_addr_lat[5:2]][15:8]  <= s0_axi_wdata[15:8];
                        if (s0_wr_strb_lat[2]) s0_mem[s0_wr_addr_lat[5:2]][23:16] <= s0_axi_wdata[23:16];
                        if (s0_wr_strb_lat[3]) s0_mem[s0_wr_addr_lat[5:2]][31:24] <= s0_axi_wdata[31:24];
                        s0_delay_cnt   <= 0;
                        s0_wr_state    <= BFM_B_WAIT;
                    end
                end
                BFM_B_WAIT: begin
                    // Delay nếu slow_wr được bật
                    if (!s0_slow_wr || s0_delay_cnt >= 3) begin
                        s0_axi_bvalid <= 1'b1;
                        s0_axi_bresp  <= 2'b00;
                        s0_wr_state   <= BFM_B;
                    end else
                        s0_delay_cnt <= s0_delay_cnt + 1;
                end
                BFM_B: begin
                    if (s0_axi_bvalid && s0_axi_bready) begin
                        s0_axi_bvalid <= 1'b0;
                        s0_wr_state   <= BFM_IDLE;
                    end
                end
            endcase

            // --- READ FSM ---
            case (s0_rd_state)
                BFM_IDLE: begin
                    s0_axi_arready <= 1'b1;
                    if (s0_axi_arvalid && s0_axi_arready) begin
                        s0_wr_addr_lat <= s0_axi_araddr;   // reuse reg
                        s0_axi_arready <= 1'b0;
                        s0_delay_cnt   <= 0;
                        s0_rd_state    <= BFM_R_WAIT;
                    end
                end
                BFM_R_WAIT: begin
                    if (!s0_slow_rd || s0_delay_cnt >= 3) begin
                        s0_axi_rdata  <= s0_mem[s0_wr_addr_lat[5:2]];
                        s0_axi_rresp  <= 2'b00;
                        s0_axi_rvalid <= 1'b1;
                        s0_rd_state   <= BFM_R;
                    end else
                        s0_delay_cnt <= s0_delay_cnt + 1;
                end
                BFM_R: begin
                    if (s0_axi_rvalid && s0_axi_rready) begin
                        s0_axi_rvalid <= 1'b0;
                        s0_rd_state   <= BFM_IDLE;
                    end
                end
            endcase
        end
    end

    // --- SLAVE 1 BFM (GPIO) ---
    reg [DATA_WIDTH-1:0] s1_mem [0:15];
    reg [3:0]  s1_wr_state, s1_rd_state;
    reg [ADDR_WIDTH-1:0] s1_addr_lat;
    integer s1_delay_cnt;

    always @(posedge clk) begin
        if (!reset) begin
            s1_axi_awready<=1'b1; s1_axi_wready<=1'b1;
            s1_axi_bvalid<=1'b0; s1_axi_bresp<=2'b00;
            s1_axi_arready<=1'b1; s1_axi_rvalid<=1'b0;
            s1_axi_rresp<=2'b00; s1_axi_rdata<=0;
            s1_wr_state<=BFM_IDLE; s1_rd_state<=BFM_IDLE; s1_delay_cnt<=0;
        end else begin
            case (s1_wr_state)
                BFM_IDLE: begin
                    s1_axi_awready<=1'b1; s1_axi_wready<=1'b1;
                    if (s1_axi_awvalid && s1_axi_awready) begin
                        s1_addr_lat<=s1_axi_awaddr; s1_axi_awready<=1'b0; s1_wr_state<=BFM_W;
                    end
                end
                BFM_W: begin
                    s1_axi_wready<=1'b1;
                    if (s1_axi_wvalid && s1_axi_wready) begin
                        s1_mem[s1_addr_lat[5:2]] <= s1_axi_wdata;
                        s1_axi_wready<=1'b0; s1_delay_cnt<=0; s1_wr_state<=BFM_B_WAIT;
                    end
                end
                BFM_B_WAIT: begin
                    if (!s1_slow_wr || s1_delay_cnt>=3) begin
                        s1_axi_bvalid<=1'b1; s1_axi_bresp<=2'b00; s1_wr_state<=BFM_B;
                    end else s1_delay_cnt<=s1_delay_cnt+1;
                end
                BFM_B: begin
                    if (s1_axi_bvalid && s1_axi_bready) begin
                        s1_axi_bvalid<=1'b0; s1_wr_state<=BFM_IDLE;
                    end
                end
            endcase
            case (s1_rd_state)
                BFM_IDLE: begin
                    s1_axi_arready<=1'b1;
                    if (s1_axi_arvalid && s1_axi_arready) begin
                        s1_addr_lat<=s1_axi_araddr; s1_axi_arready<=1'b0;
                        s1_delay_cnt<=0; s1_rd_state<=BFM_R_WAIT;
                    end
                end
                BFM_R_WAIT: begin
                    if (!s1_slow_rd || s1_delay_cnt>=3) begin
                        s1_axi_rdata<=s1_mem[s1_addr_lat[5:2]];
                        s1_axi_rresp<=2'b00; s1_axi_rvalid<=1'b1; s1_rd_state<=BFM_R;
                    end else s1_delay_cnt<=s1_delay_cnt+1;
                end
                BFM_R: begin
                    if (s1_axi_rvalid && s1_axi_rready) begin
                        s1_axi_rvalid<=1'b0; s1_rd_state<=BFM_IDLE;
                    end
                end
            endcase
        end
    end

    // --- SLAVE 2 BFM (UART) ---
    reg [DATA_WIDTH-1:0] s2_mem [0:15];
    reg [3:0]  s2_wr_state, s2_rd_state;
    reg [ADDR_WIDTH-1:0] s2_addr_lat;
    integer s2_delay_cnt;

    always @(posedge clk) begin
        if (!reset) begin
            s2_axi_awready<=1'b1; s2_axi_wready<=1'b1;
            s2_axi_bvalid<=1'b0; s2_axi_bresp<=2'b00;
            s2_axi_arready<=1'b1; s2_axi_rvalid<=1'b0;
            s2_axi_rresp<=2'b00; s2_axi_rdata<=0;
            s2_wr_state<=BFM_IDLE; s2_rd_state<=BFM_IDLE; s2_delay_cnt<=0;
        end else begin
            case (s2_wr_state)
                BFM_IDLE: begin
                    s2_axi_awready<=1'b1; s2_axi_wready<=1'b1;
                    if (s2_axi_awvalid && s2_axi_awready) begin
                        s2_addr_lat<=s2_axi_awaddr; s2_axi_awready<=1'b0; s2_wr_state<=BFM_W;
                    end
                end
                BFM_W: begin
                    s2_axi_wready<=1'b1;
                    if (s2_axi_wvalid && s2_axi_wready) begin
                        s2_mem[s2_addr_lat[5:2]] <= s2_axi_wdata;
                        s2_axi_wready<=1'b0; s2_delay_cnt<=0; s2_wr_state<=BFM_B_WAIT;
                    end
                end
                BFM_B_WAIT: begin
                    if (!s2_slow_wr || s2_delay_cnt>=3) begin
                        s2_axi_bvalid<=1'b1; s2_axi_bresp<=2'b00; s2_wr_state<=BFM_B;
                    end else s2_delay_cnt<=s2_delay_cnt+1;
                end
                BFM_B: begin
                    if (s2_axi_bvalid && s2_axi_bready) begin
                        s2_axi_bvalid<=1'b0; s2_wr_state<=BFM_IDLE;
                    end
                end
            endcase
            case (s2_rd_state)
                BFM_IDLE: begin
                    s2_axi_arready<=1'b1;
                    if (s2_axi_arvalid && s2_axi_arready) begin
                        s2_addr_lat<=s2_axi_araddr; s2_axi_arready<=1'b0;
                        s2_delay_cnt<=0; s2_rd_state<=BFM_R_WAIT;
                    end
                end
                BFM_R_WAIT: begin
                    if (!s2_slow_rd || s2_delay_cnt>=3) begin
                        s2_axi_rdata<=s2_mem[s2_addr_lat[5:2]];
                        s2_axi_rresp<=2'b00; s2_axi_rvalid<=1'b1; s2_rd_state<=BFM_R;
                    end else s2_delay_cnt<=s2_delay_cnt+1;
                end
                BFM_R: begin
                    if (s2_axi_rvalid && s2_axi_rready) begin
                        s2_axi_rvalid<=1'b0; s2_rd_state<=BFM_IDLE;
                    end
                end
            endcase
        end
    end

    // --- SLAVE 3 BFM (VGA) ---
    reg [DATA_WIDTH-1:0] s3_mem [0:15];
    reg [3:0]  s3_wr_state, s3_rd_state;
    reg [ADDR_WIDTH-1:0] s3_addr_lat;
    integer s3_delay_cnt;

    always @(posedge clk) begin
        if (!reset) begin
            s3_axi_awready<=1'b1; s3_axi_wready<=1'b1;
            s3_axi_bvalid<=1'b0; s3_axi_bresp<=2'b00;
            s3_axi_arready<=1'b1; s3_axi_rvalid<=1'b0;
            s3_axi_rresp<=2'b00; s3_axi_rdata<=0;
            s3_wr_state<=BFM_IDLE; s3_rd_state<=BFM_IDLE; s3_delay_cnt<=0;
        end else begin
            case (s3_wr_state)
                BFM_IDLE: begin
                    s3_axi_awready<=1'b1; s3_axi_wready<=1'b1;
                    if (s3_axi_awvalid && s3_axi_awready) begin
                        s3_addr_lat<=s3_axi_awaddr; s3_axi_awready<=1'b0; s3_wr_state<=BFM_W;
                    end
                end
                BFM_W: begin
                    s3_axi_wready<=1'b1;
                    if (s3_axi_wvalid && s3_axi_wready) begin
                        s3_mem[s3_addr_lat[5:2]] <= s3_axi_wdata;
                        s3_axi_wready<=1'b0; s3_delay_cnt<=0; s3_wr_state<=BFM_B_WAIT;
                    end
                end
                BFM_B_WAIT: begin
                    if (!s3_slow_wr || s3_delay_cnt>=3) begin
                        s3_axi_bvalid<=1'b1; s3_axi_bresp<=2'b00; s3_wr_state<=BFM_B;
                    end else s3_delay_cnt<=s3_delay_cnt+1;
                end
                BFM_B: begin
                    if (s3_axi_bvalid && s3_axi_bready) begin
                        s3_axi_bvalid<=1'b0; s3_wr_state<=BFM_IDLE;
                    end
                end
            endcase
            case (s3_rd_state)
                BFM_IDLE: begin
                    s3_axi_arready<=1'b1;
                    if (s3_axi_arvalid && s3_axi_arready) begin
                        s3_addr_lat<=s3_axi_araddr; s3_axi_arready<=1'b0;
                        s3_delay_cnt<=0; s3_rd_state<=BFM_R_WAIT;
                    end
                end
                BFM_R_WAIT: begin
                    if (!s3_slow_rd || s3_delay_cnt>=3) begin
                        s3_axi_rdata<=s3_mem[s3_addr_lat[5:2]];
                        s3_axi_rresp<=2'b00; s3_axi_rvalid<=1'b1; s3_rd_state<=BFM_R;
                    end else s3_delay_cnt<=s3_delay_cnt+1;
                end
                BFM_R: begin
                    if (s3_axi_rvalid && s3_axi_rready) begin
                        s3_axi_rvalid<=1'b0; s3_rd_state<=BFM_IDLE;
                    end
                end
            endcase
        end
    end

    // =====================================================
    // SCOREBOARD
    // =====================================================
    integer pass_count;
    integer fail_count;

    task check_equal;
        input [63:0] actual;
        input [63:0] expected;
        input [255:0] label;
        begin
            if (actual === expected) begin
                $display("  [PASS] %s : %h", label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s : expected=%h, got=%h", label, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task print_tc;
        input [255:0] name;
        begin
            $display("--------------------------------------------");
            $display("%s", name);
            $display("--------------------------------------------");
        end
    endtask

    // =====================================================
    // TASK: wait_clk — sample sau cạnh để tránh race
    // =====================================================
    task wait_clk;
        begin
            @(posedge clk); #1;
        end
    endtask

    // =====================================================
    // TASK: axi_write
    // AW và W gửi đồng thời, chờ B response
    // out: resp — bresp nhận được
    // =====================================================
    task axi_write;
        input [ADDR_WIDTH-1:0]   addr;
        input [DATA_WIDTH-1:0]   data;
        input [DATA_WIDTH/8-1:0] strb;
        output [1:0]             resp;

        integer to;
        reg aw_done, w_done;
        begin
            wait_clk;
            m_axi_awaddr  <= addr;   m_axi_awvalid <= 1'b1;
            m_axi_wdata   <= data;   m_axi_wstrb   <= strb;
            m_axi_wvalid  <= 1'b1;   m_axi_bready  <= 1'b1;

            aw_done=0; w_done=0; to=0;
            while (!aw_done || !w_done) begin
                wait_clk; to=to+1;
                if (m_axi_awvalid && m_axi_awready) begin m_axi_awvalid<=1'b0; aw_done=1; end
                if (m_axi_wvalid  && m_axi_wready)  begin m_axi_wvalid <=1'b0; w_done =1; end
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] axi_write AW/W addr=%h", addr); $finish; end
            end

            to=0;
            while (!m_axi_bvalid) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] axi_write BVALID addr=%h", addr); $finish; end
            end
            resp = m_axi_bresp;
            wait_clk;
            m_axi_bready <= 1'b0;
        end
    endtask

    // =====================================================
    // TASK: axi_write_delayed_w
    // AW đến trước W nhiều cycle → kiểm tra sel lock
    // =====================================================
    task axi_write_delayed_w;
        input [ADDR_WIDTH-1:0]   addr;
        input [DATA_WIDTH-1:0]   data;
        input [DATA_WIDTH/8-1:0] strb;
        input integer            aw_w_gap;   // số cycle delay giữa AW và W
        output [1:0]             resp;

        integer to, i;
        begin
            // --- AW phase ---
            wait_clk;
            m_axi_awaddr  <= addr; m_axi_awvalid <= 1'b1;
            m_axi_wvalid  <= 1'b0; m_axi_bready  <= 1'b1;

            to=0;
            while (!(m_axi_awvalid && m_axi_awready)) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] delayed_w AW"); $finish; end
            end
            wait_clk; m_axi_awvalid <= 1'b0;

            // --- Gap: addr đã thay đổi (test sel lock) ---
            m_axi_awaddr <= OOR_ADDR;   // Đổi addr sang OOR để chứng minh lock không bị ảnh hưởng
            for (i=0; i<aw_w_gap; i=i+1) wait_clk;

            // --- W phase ---
            m_axi_wdata  <= data; m_axi_wstrb <= strb; m_axi_wvalid <= 1'b1;
            to=0;
            while (!(m_axi_wvalid && m_axi_wready)) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] delayed_w W"); $finish; end
            end
            wait_clk; m_axi_wvalid <= 1'b0;

            // --- B phase ---
            to=0;
            while (!m_axi_bvalid) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] delayed_w B"); $finish; end
            end
            resp = m_axi_bresp;
            wait_clk; m_axi_bready <= 1'b0;
            m_axi_awaddr <= 0;  // restore
        end
    endtask

    // =====================================================
    // TASK: axi_read
    // out: data, resp
    // =====================================================
    task axi_read;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;
        output [1:0]            resp;

        integer to;
        begin
            wait_clk;
            m_axi_araddr  <= addr; m_axi_arvalid <= 1'b1; m_axi_rready <= 1'b1;

            to=0;
            while (!(m_axi_arvalid && m_axi_arready)) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] axi_read AR addr=%h", addr); $finish; end
            end
            wait_clk; m_axi_arvalid <= 1'b0;

            to=0;
            while (!m_axi_rvalid) begin
                wait_clk; to=to+1;
                if (to>=TIMEOUT_CYC) begin $display("[TIMEOUT] axi_read RVALID addr=%h", addr); $finish; end
            end
            data = m_axi_rdata; resp = m_axi_rresp;
            wait_clk; m_axi_rready <= 1'b0;
        end
    endtask

    // =====================================================
    // TEST SEQUENCE
    // =====================================================
    reg [DATA_WIDTH-1:0] rd_data;
    reg [1:0]            rd_resp, wr_resp;
    integer              i;

    initial begin
        pass_count = 0; fail_count = 0;

        // Khởi tạo slow flags
        s0_slow_wr=0; s0_slow_rd=0;
        s1_slow_wr=0; s1_slow_rd=0;
        s2_slow_wr=0; s2_slow_rd=0;
        s3_slow_wr=0; s3_slow_rd=0;

        // Khởi tạo master signals
        reset=1'b0;
        m_axi_awaddr=0; m_axi_awvalid=0;
        m_axi_wdata=0;  m_axi_wstrb=0; m_axi_wvalid=0;
        m_axi_bready=0;
        m_axi_araddr=0; m_axi_arvalid=0;
        m_axi_rready=0;

        repeat(5) @(posedge clk); #1;
        reset = 1'b1;
        repeat(3) @(posedge clk);

        // =============================================
        // TC1: Write + Read đến từng slave
        // Kiểm tra routing cơ bản đến đúng slave
        // =============================================
        print_tc("TC1: Write + Read toi tung slave");

        // Slave 0 — RAM
        axi_write(RAM_BASE  + 32'h0000_0000, 32'hAAAA_0000, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b00, "TC1 S0 BRESP  ");
        axi_read (RAM_BASE  + 32'h0000_0000, rd_data, rd_resp);
        check_equal(rd_data, 32'hAAAA_0000, "TC1 S0 RDATA  ");
        check_equal(rd_resp, 2'b00,         "TC1 S0 RRESP  ");

        // Slave 1 — GPIO
        axi_write(GPIO_BASE + 32'h0000_0010, 32'hBBBB_1111, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b00, "TC1 S1 BRESP  ");
        axi_read (GPIO_BASE + 32'h0000_0010, rd_data, rd_resp);
        check_equal(rd_data, 32'hBBBB_1111, "TC1 S1 RDATA  ");

        // Slave 2 — UART
        axi_write(UART_BASE + 32'h0000_0020, 32'hCCCC_2222, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b00, "TC1 S2 BRESP  ");
        axi_read (UART_BASE + 32'h0000_0020, rd_data, rd_resp);
        check_equal(rd_data, 32'hCCCC_2222, "TC1 S2 RDATA  ");

        // Slave 3 — VGA
        axi_write(VGA_BASE  + 32'h0000_0030, 32'hDDDD_3333, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b00, "TC1 S3 BRESP  ");
        axi_read (VGA_BASE  + 32'h0000_0030, rd_data, rd_resp);
        check_equal(rd_data, 32'hDDDD_3333, "TC1 S3 RDATA  ");

        // =============================================
        // TC2: Out-of-range address → SLVERR
        // Kiểm tra error slave hoạt động đúng
        // =============================================
        print_tc("TC2: Out-of-range address -> SLVERR");

        axi_write(OOR_ADDR, 32'hDEAD_BEEF, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b10, "TC2 WR SLVERR ");

        axi_read(OOR_ADDR, rd_data, rd_resp);
        check_equal(rd_resp, 2'b10, "TC2 RD SLVERR ");

        // =============================================
        // TC3: AW đến trước W nhiều cycle
        // Sau AW handshake, awaddr bị đổi sang OOR_ADDR
        // Nếu sel lock đúng: routing vẫn đến Slave 0
        // Nếu sel lock sai: routing đổi → timeout hoặc SLVERR
        // =============================================
        print_tc("TC3: AW truoc W nhieu cycle, awaddr thay doi sau handshake");

        // Ghi giá trị ban đầu để có baseline
        axi_write(RAM_BASE + 32'h0000_0004, 32'hBASE_LINE, 4'hF, wr_resp);

        // Gửi AW đến RAM, delay 5 cycle, thay awaddr, rồi gửi W
        axi_write_delayed_w(RAM_BASE + 32'h0000_0004, 32'h1234_5678, 4'hF, 5, wr_resp);
        check_equal(wr_resp, 2'b00, "TC3 BRESP OKAY");

        // Đọc lại — phải thấy giá trị mới (không phải OOR bị ignore)
        axi_read(RAM_BASE + 32'h0000_0004, rd_data, rd_resp);
        check_equal(rd_data, 32'h1234_5678, "TC3 RDATA lock");

        // =============================================
        // TC4: W đến trước AW (AW không dùng ở đây vì
        //      Interconnect này accept AW và W đồng thời)
        //      Kiểm tra wready không lên khi chưa có AW
        // =============================================
        print_tc("TC4: Kiem tra wready chi len sau khi co AW");

        // Gửi W trước, không có AW → wready phải = 0
        wait_clk;
        m_axi_wdata  <= 32'hDEAD_0000;
        m_axi_wstrb  <= 4'hF;
        m_axi_wvalid <= 1'b1;

        // Chờ 5 cycle — wready phải không lên (chưa có AW)
        repeat(5) wait_clk;
        check_equal(m_axi_wready, 1'b0, "TC4 WREADY=0  ");

        // Bây giờ gửi AW → cả hai handshake cùng xảy ra
        m_axi_awaddr  <= RAM_BASE + 32'h0000_0008;
        m_axi_awvalid <= 1'b1;
        m_axi_bready  <= 1'b1;

        begin : TC4_WAIT
            integer tc4_to;
            reg tc4_aw_done, tc4_w_done;
            tc4_aw_done=0; tc4_w_done=0; tc4_to=0;
            while (!tc4_aw_done || !tc4_w_done) begin
                wait_clk; tc4_to=tc4_to+1;
                if (m_axi_awvalid && m_axi_awready) begin m_axi_awvalid<=1'b0; tc4_aw_done=1; end
                if (m_axi_wvalid  && m_axi_wready)  begin m_axi_wvalid <=1'b0; tc4_w_done =1; end
                if (tc4_to>=TIMEOUT_CYC) begin $display("[TIMEOUT] TC4 AW/W"); $finish; end
            end
        end

        begin : TC4_B
            integer tc4_to2;
            tc4_to2=0;
            while (!m_axi_bvalid) begin
                wait_clk; tc4_to2=tc4_to2+1;
                if (tc4_to2>=TIMEOUT_CYC) begin $display("[TIMEOUT] TC4 B"); $finish; end
            end
        end
        check_equal(m_axi_bresp, 2'b00, "TC4 BRESP OKAY");
        wait_clk; m_axi_bready <= 1'b0;

        // =============================================
        // TC5: Back-to-back write → 2 slave khác nhau
        // Kiểm tra không có data corruption
        // =============================================
        print_tc("TC5: Back-to-back write, 2 slave khac nhau");

        axi_write(RAM_BASE  + 32'h0000_000C, 32'hAABB_CCDD, 4'hF, wr_resp);
        // Không có idle — gửi ngay lập tức
        axi_write(GPIO_BASE + 32'h0000_0000, 32'h1122_3344, 4'hF, wr_resp);

        axi_read(RAM_BASE  + 32'h0000_000C, rd_data, rd_resp);
        check_equal(rd_data, 32'hAABB_CCDD, "TC5 S0 RDATA  ");

        axi_read(GPIO_BASE + 32'h0000_0000, rd_data, rd_resp);
        check_equal(rd_data, 32'h1122_3344, "TC5 S1 RDATA  ");

        // =============================================
        // TC6: Slave bvalid chậm (backpressure)
        // Interconnect phải chờ slave, không bị stuck
        // =============================================
        print_tc("TC6: Slave BVALID cham (slow_wr=1)");

        s0_slow_wr = 1;   // Slave 0 delay 3 cycle trước khi assert bvalid
        axi_write(RAM_BASE + 32'h0000_0010, 32'hSLOW_WR00, 4'hF, wr_resp);
        check_equal(wr_resp, 2'b00, "TC6 BRESP OKAY");
        s0_slow_wr = 0;

        // Đọc lại verify data đã ghi đúng
        axi_read(RAM_BASE + 32'h0000_0010, rd_data, rd_resp);
        check_equal(rd_data, 32'hSLOW_WR00, "TC6 RDATA     ");

        // =============================================
        // TC7: Slave rvalid chậm (backpressure)
        // =============================================
        print_tc("TC7: Slave RVALID cham (slow_rd=1)");

        axi_write(GPIO_BASE + 32'h0000_0004, 32'hSLOW_RD11, 4'hF, wr_resp);

        s1_slow_rd = 1;
        axi_read(GPIO_BASE + 32'h0000_0004, rd_data, rd_resp);
        check_equal(rd_data, 32'hSLOW_RD11, "TC7 RDATA     ");
        check_equal(rd_resp, 2'b00,          "TC7 RRESP     ");
        s1_slow_rd = 0;

        // =============================================
        // TC8: Verify không có cross-routing
        // Ghi data riêng vào mỗi slave, đọc lại verify
        // không có dữ liệu bị ghi nhầm sang slave khác
        // =============================================
        print_tc("TC8: Verify khong cross-routing giua cac slave");

        axi_write(RAM_BASE  + 32'h0000_0014, 32'hCC00_0001, 4'hF, wr_resp);
        axi_write(GPIO_BASE + 32'h0000_0014, 32'hCC00_0002, 4'hF, wr_resp);
        axi_write(UART_BASE + 32'h0000_0014, 32'hCC00_0003, 4'hF, wr_resp);
        axi_write(VGA_BASE  + 32'h0000_0014, 32'hCC00_0004, 4'hF, wr_resp);

        axi_read(RAM_BASE  + 32'h0000_0014, rd_data, rd_resp);
        check_equal(rd_data, 32'hCC00_0001, "TC8 S0 RDATA  ");

        axi_read(GPIO_BASE + 32'h0000_0014, rd_data, rd_resp);
        check_equal(rd_data, 32'hCC00_0002, "TC8 S1 RDATA  ");

        axi_read(UART_BASE + 32'h0000_0014, rd_data, rd_resp);
        check_equal(rd_data, 32'hCC00_0003, "TC8 S2 RDATA  ");

        axi_read(VGA_BASE  + 32'h0000_0014, rd_data, rd_resp);
        check_equal(rd_data, 32'hCC00_0004, "TC8 S3 RDATA  ");

        // =============================================
        // SUMMARY
        // =============================================
        #50;
        $display("============================================");
        $display("RESULT: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("============================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check [FAIL] lines above");
        $finish;
    end

endmodule