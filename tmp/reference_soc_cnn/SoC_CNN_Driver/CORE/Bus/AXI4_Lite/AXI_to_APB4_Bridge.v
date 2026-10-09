// ==========================================================
// AXI4-Lite to APB4 Bridge
// ----------------------------------------------------------
// Single AXI4-Lite Slave  ->  Single APB4 Master
//
// Use case:
// AXI_Interconnect
//      |
//      | s_axi_*
//      v
// AXI_to_APB4_Bridge
//      |
//      | APB4 bus
//      v
// APB4_Decoder / APB4_Peripherals
//
// Reset convention:
// reset = 0 : reset active
// reset = 1 : normal operation
//
// Notes:
// - Supports AW before W
// - Supports W before AW
// - Supports AW and W same cycle
// - Serializes AXI read/write into one APB transfer at a time
// - APB wait-state supported through PREADY
// - APB error supported through PSLVERR
// ==========================================================
module AXI_to_APB4_Bridge #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,

    // Tín hiệu bảo vệ, hiện tại để mặc định là 3'b000 (Chế độ mặc định)
    parameter [2:0] PPROT_VALUE = 3'b000
)
(
    input clk,
    input reset,

    // ================================================
    // AXI 4 -Lite SLAVE SIDE
    // + Tín hiệu được chuyển từ AXI_Interconnect
    // + CHuyển đổi tín hiệu từ AXI sang APB4
    // ================================================

    // WRITE ADDRESS CHANNEL
    input  [ADDR_WIDTH - 1:0]       s_axi_awaddr,
    input                           s_axi_awvalid,
    output                          s_axi_awready,

    // WRITE DATA CHANNEL
    input  [DATA_WIDTH - 1:0]       s_axi_wdata,
    input  [DATA_WIDTH/8-1:0]       s_axi_wstrb,   
    input                           s_axi_wvalid,
    output                          s_axi_wready,

    // WRITE RESPONSE CHANNEL
    output reg [1:0]                s_axi_bresp,
    output reg                      s_axi_bvalid,
    input                           s_axi_bready,

    // READ ADDRESS CHANNEL
    input  [ADDR_WIDTH - 1:0]       s_axi_araddr,
    input                           s_axi_arvalid,
    output                          s_axi_arready,

    // READ DATA CHANNEL
    output reg [DATA_WIDTH-1:0]     s_axi_rdata,
    output reg [1:0]                s_axi_rresp,
    output reg                      s_axi_rvalid,
    input                           s_axi_rready,

    // ================================================
    // APB 4 Master Side
    // AXI_to_APB_Bridge đóng vai trò là Master
    // ================================================

    // Nhóm tín hiệu APB Master chuyển sang APB Slave
    output reg [ADDR_WIDTH - 1:0]   PADDR,      // Địa chỉ APB mà CPU muốn truy cập 
    output reg                      PSEL,       // Tín hiệu báo rằng đang có một APB Slave được chọn
    output reg                      PENABLE,    // Phân biệt 2 Phase của APB FSM (SETUP = 0, ACCESS = 1)
    output reg                      PWRITE,     // Tín hiệu cho biết Transaction là WRITE hay READ
    output reg [DATA_WIDTH - 1:0]   PWDATA,     // Dữ liệu ghi từ CPU xuống Peripheral
    output reg [DATA_WIDTH/8-1:0]   PSTRB,      // Byte Enable của APB 4
    output reg [2:0]                PPROT,      // Tín hiệu bảo vệ của APB4 

    // Nhóm tín hiệu APB Slvae phản hổi lại APB Master
    input [DATA_WIDTH - 1:0]        PRDATA,     // Dữ liệu đọc từ Peripheral trả về Master
    input                           PREADY,     // Tín hiệu báo Transaction đã hoàn thành hay chưa
    input                           PSLVERR     // Báo lỗi từ APB Slave
);  

    // =============================================
    // Local Parameters
    // =============================================
    localparam RESP_OKAY        = 2'b00;
    localparam RESP_SLVERR      = 2'b10;

    localparam ST_IDLE          = 3'd0;
    localparam ST_W_COLLECT     = 3'd1;     // Trạng thái chờ AW và W của AXI cùng đền (AW và W có thể đến không cùng lúc nên cần trạng thái chờ)
    localparam ST_APB_SETUP     = 3'd2;
    localparam ST_APB_ACCESS    = 3'd3;
    localparam ST_AXI_BRESP     = 3'd4;
    localparam ST_AXI_RRESP     = 3'd5;

    // =============================================
    // Internal Registers
    // =============================================
    reg [2:0] state;

    reg [ADDR_WIDTH - 1:0] addr_reg;
    reg [DATA_WIDTH - 1:0] wdata_reg;
    reg [DATA_WIDTH/8-1:0] wstrb_reg;

    reg                    write_reg;

    reg                    aw_done;
    reg                    w_done;

    // =============================================
    // AXI Handshake Helper
    // =============================================
    wire idle_state         = (state == ST_IDLE);
    wire w_collect_state    = (state == ST_W_COLLECT);

    /*
        - Bridge chỉ nhận tín hiệu WRITE ở IDLE hoặc W_COLLECT
        + Cần nhận WRITE ở 2 trạng thái này vì cần chờ AW và W cùng đến để chuyển qua APB
    */
    wire can_accept_write   = idle_state || w_collect_state;

    /*
        - Bridge chỉ nhận read khi ở trạng thái IDLE
        + Khi read data thì AXI không được phép ghi thêm dữ liệu vào các Slave
        + !s_axi_awvalid: AXI không có ADDR nào cần gửi xuống APB
        + !s_axi_wvalid: AXI không có DATA nào cần gửi xuống APB
        => Không có dữ liệu WRITE xuống APB trong quá trình read
    */
    // Nếu WRITE và READ cùng đến, ưu tiên WRITE trước
    wire can_accept_read    = idle_state && !s_axi_awvalid && !s_axi_wvalid;

    assign s_axi_awready    = can_accept_write && !aw_done;     // Transaction WRITE thành công khi đang ở trong trạng thái write và nhận được tín hiệu phản hồi done
    assign s_axi_wready     = can_accept_write && !w_done;

    assign s_axi_arready    = can_accept_read;

    /*
        - Tín hiệu báo Handshake đã diễn ra thành công (Transaction trên channel đó đã thực sự được truyền đi)
        - Trên AXI:
        + VALID: Bên gửi có dữ liệu 
        + READY: Bên nhận sẵn sàng nhận dữ liệu
        => Dữ liệu được coi là truyền thành công khi Handshake xảy ra (VALID && READY)
    */
    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;

    // =============================================
    // Main FSM
    // =============================================
    always @(posedge clk) begin
    
        if (!reset) begin
            state           <= ST_IDLE;

            // AXI Write Response
            s_axi_bresp     <= RESP_OKAY;
            s_axi_bvalid    <= 1'b0;

            // AXI Read Response
            s_axi_rdata     <= {DATA_WIDTH{1'b0}};
            s_axi_rresp     <= RESP_OKAY;
            s_axi_rvalid    <= 1'b0;

            // APB4 signals
            PADDR           <= {ADDR_WIDTH{1'b0}};
            PSEL            <= 1'b0;
            PENABLE         <= 1'b0;
            PWRITE          <= 1'b0;
            PWDATA          <= {DATA_WIDTH{1'b0}};
            PSTRB           <= {(DATA_WIDTH/8){1'b0}};
            PPROT           <= PPROT_VALUE;

            // Internal
            addr_reg        <= {ADDR_WIDTH{1'b0}};
            wdata_reg       <= {DATA_WIDTH{1'b0}};
            wstrb_reg       <= {(DATA_WIDTH/8){1'b0}};

            write_reg       <= 1'b0;

            aw_done         <= 1'b0;
            w_done          <= 1'b0;
        end

        else begin
            
            case (state)

                // ==================================================
                // IDLE
                // Chờ AXI write hoặc AXI read transaction
                // ==================================================
                ST_IDLE: begin
                    PSEL    <= 1'b0;
                    PENABLE <= 1'b0;

                    aw_done <= 1'b0;
                    w_done  <= 1'b0;

                    // ----------------------------------------------
                    // WRITE transaction start
                    // Có thể nhận AW, W hoặc cả AW/W cùng chu kỳ
                    // ----------------------------------------------
                    if (aw_fire || w_fire) begin
                        write_reg   <= 1'b1;        // Bật tín hiệu này để xác nhận hệ thống đang thực hiện write

                        // AW (ADDR) đến độc lập (Trước hoặc sau)
                        if (aw_fire) begin
                            addr_reg    <= s_axi_awaddr;
                        end

                        // W (ADDR) đến độc lập (Trước hoặc sau)
                        if (w_fire) begin
                            wdata_reg   <= s_axi_wdata;
                            wstrb_reg   <= s_axi_wstrb;
                        end

                        // AW và W đến cùng lúc, cùng có dữ liệu trong 1 chu kỳ --> Lưu trực tiếp vào các channel chính của APB4
                        if (aw_fire && w_fire) begin
                            // Start APB SETUP phase
                            PADDR       <= s_axi_awaddr;
                            PWRITE      <= 1'b1;
                            PWDATA      <= s_axi_wdata;
                            PSTRB       <= s_axi_wstrb;
                            PPROT       <= PPROT_VALUE;

                            PSEL        <= 1'b1;
                            PENABLE     <= 1'b0;

                            aw_done     <= 1'b0;
                            w_done      <= 1'b0;

                            state       <= ST_APB_SETUP;
                        end

                        // Nếu mới nhận được một phần (AW hoặc W) chờ tín hiệu còn lại tới
                        else begin
                            aw_done     <= aw_fire;
                            w_done      <= w_fire;

                            state       <= ST_W_COLLECT;
                        end
                    end

                    // ----------------------------------------------
                    // READ transaction start
                    // ----------------------------------------------
                    else if (ar_fire) begin
                        write_reg   <= 1'b0;

                        addr_reg    <= s_axi_araddr;

                        // Start APB SETUP phase
                        PADDR       <= s_axi_araddr;
                        PWRITE      <= 1'b0;
                        PWDATA      <= {DATA_WIDTH{1'b0}};
                        PSTRB       <= {(DATA_WIDTH/8){1'b0}};
                        PPROT       <= PPROT_VALUE;

                        PSEL        <= 1'b1;
                        PENABLE     <= 1'b0;

                        state       <= ST_APB_SETUP;
                    end
                end

                // ==================================================
                // WRITE COLLECT
                // Chờ nhận đủ AW và W
                // Hỗ trợ:
                // - AW trước W
                // - W trước AW
                // ==================================================
                ST_W_COLLECT: begin
                    if (aw_fire) begin
                        addr_reg    <= s_axi_awaddr;
                    end

                    if (w_fire) begin
                        wdata_reg   <= s_axi_wdata;
                        wstrb_reg   <= s_axi_wstrb;
                    end 

                    // Nếu sau chu kỳ này đã đủ AW và W
                    if ((aw_done || aw_fire) && (w_done || w_fire)) begin
                        // Start APB SETUP phase
                        PADDR       <= aw_fire ? s_axi_awaddr : addr_reg;
                        PWRITE      <= 1'b1;
                        PWDATA      <= w_fire ? s_axi_wdata : wdata_reg;
                        PSTRB       <= w_fire ? s_axi_wstrb : wstrb_reg;
                        PPROT       <= PPROT_VALUE;

                        PSEL        <= 1'b1;
                        PENABLE     <= 1'b0;

                        state       <= ST_APB_SETUP;
                    end

                    else begin
                        aw_done     <= aw_done | aw_fire;
                        w_done      <= w_done  | w_fire; 
                    end 
                end

                // ==================================================
                // APB SETUP PHASE
                // PSEL    = 1
                // PENABLE = 0
                //
                // APB yêu cầu SETUP phase kéo dài đúng 1 chu kỳ
                // Sau đó chuyển sang ACCESS phase
                // ==================================================
                ST_APB_SETUP: begin
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b1;

                    state   <= ST_APB_ACCESS;
                end

                // ==================================================
                // APB ACCESS PHASE
                // PSEL    = 1
                // PENABLE = 1
                //
                // Nếu PREADY = 0: giữ nguyên ACCESS phase
                // Nếu PREADY = 1: hoàn thành APB transfer
                // ==================================================
                ST_APB_ACCESS: begin
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b1;

                    if (PREADY) begin
                        PSEL    <= 1'b0;
                        PENABLE <= 1'b0;

                        // ------------------------------------------
                        // APB WRITE completed
                        // Trả AXI B response
                        // ------------------------------------------
                        if (write_reg) begin
                            s_axi_bresp     <= PSLVERR ? RESP_SLVERR : RESP_OKAY;
                            s_axi_bvalid    <= 1'b1;

                            state           <= ST_AXI_BRESP;
                        end

                        // ------------------------------------------
                        // APB READ completed
                        // Trả AXI R data/response
                        // ------------------------------------------
                        else begin
                            s_axi_rdata     <= PRDATA;
                            s_axi_rresp     <= PSLVERR ? RESP_SLVERR : RESP_OKAY;
                            s_axi_rvalid    <= 1'b1;

                            state           <= ST_AXI_RRESP;
                        end
                    end
                end

                // ==================================================
                // AXI WRITE RESPONSE PHASE
                // Giữ BVALID cho đến khi BREADY = 1
                // ==================================================
                ST_AXI_BRESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid    <= 1'b0;
                        s_axi_bresp     <= RESP_OKAY;

                        write_reg       <= 1'b0;

                        state           <= ST_IDLE;
                    end
                end

                // ==================================================
                // AXI READ RESPONSE PHASE
                // Giữ RVALID/RDATA cho đến khi RREADY = 1
                // ==================================================
                ST_AXI_RRESP: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid    <= 1'b0;
                        s_axi_rresp     <= RESP_OKAY;
                        s_axi_rdata     <= {DATA_WIDTH{1'b0}};

                        write_reg       <= 1'b0;

                        state           <= ST_IDLE;
                    end
                end

                // ==================================================
                // DEFAULT
                // ==================================================
                default: begin
                    state           <= ST_IDLE;

                    PSEL            <= 1'b0;
                    PENABLE         <= 1'b0;

                    s_axi_bvalid    <= 1'b0;
                    s_axi_rvalid    <= 1'b0;

                    aw_done         <= 1'b0;
                    w_done          <= 1'b0;
                end

            endcase

        end

    end

endmodule