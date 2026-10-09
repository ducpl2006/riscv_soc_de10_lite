// ============================================================================
// Module AXI_VGA_Slave
// ----------------------------------------------------------------------------
// AXI4-Lite VGA Slave
//
// Chức năng:
//   + AXI4-Lite slave interface
//   + Kết nối AXI <-> VGA_Register_IF
//   + Hỗ trợ:
//       - TEXT RAM write
//       - CTRL register write/read
//       - STATUS register read
//
// NOTE:
//   + Active-LOW reset
//   + Single outstanding transaction
//   + Simple AXI-Lite architecture
// ============================================================================

module AXI_VGA_Slave #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input clk,
    input reset,

    // ================================
    // WRITE ADDRESS CHANNEL
    // ================================
    input  [ADDR_WIDTH-1:0] s_axi_awaddr,
    input                   s_axi_awvalid,
    output reg              s_axi_awready,

    // ================================
    // WRITE DATA CHANNEL
    // ================================
    input  [DATA_WIDTH-1:0]     s_axi_wdata,
    input  [DATA_WIDTH/8-1:0]   s_axi_wstrb,     
    input                       s_axi_wvalid,
    output reg                  s_axi_wready,

    // ================================
    // WRITE RESPONSE CHANNEL
    // ================================
    output reg [1:0]            s_axi_bresp,
    output reg                  s_axi_bvalid,
    input                       s_axi_bready,

    // ================================
    // READ ADDRESS CHANNEL
    // ================================
    input  [ADDR_WIDTH-1:0]     s_axi_araddr,
    input                       s_axi_arvalid,
    output reg                  s_axi_arready,

    // ================================
    // READ DATA CHANNEL
    // ================================
    output reg [DATA_WIDTH-1:0] s_axi_rdata,
    output reg [1:0]            s_axi_rresp,
    output reg                  s_axi_rvalid,
    input                       s_axi_rready,

    // ================================
    // VGA OUTPUT
    // ================================
    output VGA_HS,
    output VGA_VS,

    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B
);

    // ================================
    // AXI RESPONSE CODES
    // ================================
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;   

    // ================================
    // VGA REGISTER INTERFACE SIGNALS
    // ================================
    wire [31:0]  vga_addr;
    reg [31:0]  vga_wr_data;

    reg         vga_write_en;
    reg         vga_read_en;

    wire [31:0] vga_rd_data;

    // ================================
    // VGA CORE SIGNALS
    // ================================
    wire        text_we;
    wire [11:0] text_addr_cpu;
    wire [15:0] text_data_cpu;

    wire        ctrl_we;
    wire [31:0] ctrl_data;

    wire [31:0] ctrl_rd_data;
    wire [31:0] stat_rd_data;

    // ================================
    // VGA REGISTER INTERFACE 
    // ================================
    VGA_Register_IF vga_if (

        .clk            (clk),
        .reset          (reset),

        .addr           (vga_addr),
        .wr_data        (vga_wr_data),

        .write_en       (vga_write_en),
        .read_en        (vga_read_en),

        .rd_data        (vga_rd_data),

        .text_we        (text_we),
        .text_addr_cpu  (text_addr_cpu),
        .text_data_cpu  (text_data_cpu),

        .ctrl_we        (ctrl_we),
        .ctrl_data      (ctrl_data),

        .ctrl_rd_data   (ctrl_rd_data),
        .stat_rd_data   (stat_rd_data)
    );

    // ================================
    // VGA CORE
    // ================================
    VGA_CORE vga_core (

        .clk_cpu        (clk),
        .reset          (reset),

        .text_we        (text_we),
        .text_addr_cpu  (text_addr_cpu),
        .text_data_cpu  (text_data_cpu),

        .ctrl_we        (ctrl_we),
        .ctrl_data      (ctrl_data),

        .ctrl_rd_data   (ctrl_rd_data),
        .stat_rd_data   (stat_rd_data),

        .VGA_HS         (VGA_HS),
        .VGA_VS         (VGA_VS),
        .VGA_R          (VGA_R),
        .VGA_G          (VGA_G),
        .VGA_B          (VGA_B)
    );

    // ================================
    // ADDRESS VALID CHECK
    // ================================
    function automatic addr_valid;

        input [31:0] addr;
        
        begin
            addr_valid = ((addr >= 32'h3000_0000) && (addr <= 32'h3000_257C)) ||
                         (addr == 32'h3000_4000)                              ||
                         (addr == 32'h3000_4004);
        end 

    endfunction

    // ================================
    // WRITE CHANNEL
    // ================================
    reg [31:0] awaddr_lat;
    reg [31:0] wdata_reg;

    reg aw_done;
    reg w_done;

    always @(posedge clk or negedge reset) begin
        
        if (!reset) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;

            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;

            awaddr_lat      <= 32'b0;
            wdata_reg       <= 32'b0;

            aw_done         <= 1'b0;
            w_done          <= 1'b0;

            vga_wr_data     <= 32'b0;
            vga_write_en    <= 1'b0;
        end

        else begin
            
            // -------- DEFAULT --------
            vga_write_en    <= 1'b0;

            // -------- READY --------
            s_axi_awready   <= !aw_done;
            s_axi_wready    <= !w_done;

            // -------- AW HANDSHAKE --------
            if (s_axi_awvalid && s_axi_awready) begin
                s_axi_awready   <= 1'b0;
                awaddr_lat      <= s_axi_awaddr;
                aw_done         <= 1'b1;
            end
            else if (!aw_done) begin
                s_axi_awready   <= 1'b1;
            end

            // -------- W HANDSHAKE --------
            if (s_axi_wvalid && s_axi_wready) begin
                s_axi_wready    <= 1'b0;
 
                // Byte nào strobe = 0 thì giữ nguyên giá trị cũ trong wdata_reg
                if (s_axi_wstrb[0]) wdata_reg[ 7: 0] <= s_axi_wdata[ 7: 0];
                if (s_axi_wstrb[1]) wdata_reg[15: 8] <= s_axi_wdata[15: 8];
                if (s_axi_wstrb[2]) wdata_reg[23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) wdata_reg[31:24] <= s_axi_wdata[31:24];
 
                w_done          <= 1'b1;
            end else if (!w_done) begin
                s_axi_wready    <= 1'b1;
            end

            // -------- EXECUTE WRITE --------
            if (aw_done && w_done && !s_axi_bvalid) begin
                vga_wr_data     <= wdata_reg;

                // VALID ADDRESS
                if (addr_valid(awaddr_lat)) begin
                    vga_write_en    <= 1'b1;
                    s_axi_bresp     <= RESP_OKAY;
                end

                // INVALID ADDRESS
                else begin
                    s_axi_bresp     <= RESP_SLVERR;
                end

                s_axi_bvalid        <= 1'b1;

                aw_done             <= 1'b0;
                w_done              <= 1'b0;
            end

            // -------- B HANDSHAKE --------
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid        <= 1'b0;
            end
        end

    end

    // ================================
    // READ CHANNEL
    // ================================
    reg [31:0] araddr_lat;

    reg read_wait;
    reg read_pending;

    always @(posedge clk or negedge reset) begin
        
        if (!reset) begin
            s_axi_arready   <= 1'b0;

            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'b0;
            s_axi_rresp     <= RESP_OKAY;

            araddr_lat      <= 32'b0;

            read_wait       <= 1'b0;
            read_pending    <= 1'b0;

            vga_read_en     <= 1'b0;
        end

        else begin
            
            // -------- DEFAULT --------
            vga_read_en     <= 1'b0;

            // -------- ARREADY --------
            s_axi_arready   <= !read_wait && !read_pending && !s_axi_rvalid;

            // -------- AR HANDSHAKE --------
            if (s_axi_arvalid && s_axi_arready) begin
                araddr_lat  <= s_axi_araddr;
                vga_read_en <= 1'b1;
                read_wait   <= 1'b1;
            end

            // -------- WAIT 1 CYCLE --------
            if (read_wait) begin
                read_wait       <= 1'b0;
                read_pending    <= 1'b1;
            end

            // -------- RETURN READ DATA --------
            if (read_pending) begin
                s_axi_rdata     <= vga_rd_data;

                if (addr_valid(araddr_lat)) begin
                    s_axi_rresp <= RESP_OKAY;
                end
                else begin
                    s_axi_rresp <= RESP_SLVERR;
                end

                s_axi_rvalid    <= 1'b1;

                read_pending    <= 1'b0;
            end

            // -------- R HANDSHAKE --------
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid    <= 1'b0;
            end
        end

    end

    // ================================================================
    // vga_addr combinational mux
    //
    //   (write và read channel) → multiple-driver error.
    //
    //   Sửa: write channel dùng awaddr_lat, read channel dùng
    //   araddr_lat. vga_addr là wire combinational chọn giữa hai,
    //   ưu tiên read khi đang có read transaction đang chờ.
    //   Không bao giờ có conflict vì AXI4-Lite single-outstanding
    //   đảm bảo write và read không xảy ra đồng thời.
    // ================================================================
    assign vga_addr = (read_wait || read_pending) ? araddr_lat : awaddr_lat;

endmodule