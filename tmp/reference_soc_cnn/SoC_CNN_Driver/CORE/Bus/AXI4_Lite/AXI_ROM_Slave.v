// ============================================================================
// Module AXI_ROM_Slave
// ----------------------------------------------------------------------------
// AXI4-Lite Read-Only ROM Slave
//
// Purpose
// ----------------------------------------------------------------------------
// + Allow CPU data-side AXI read to access Instr_Memory
// + Used for reading .rodata / const string / firmware data
// + Write is not allowed:
//      - Accept AW + W handshake
//      - Return BRESP = SLVERR
//      - Do NOT modify Instr_Memory
//
// Memory Map
// ----------------------------------------------------------------------------
// 0x0000_0000 ~ 0x0000_0FFF
//
// Notes
// ----------------------------------------------------------------------------
// + Instr_Memory size = 4KB = 1024 words
// + Instr_Memory is internally initialized by firmware.hex
// + boot_mode is tied to 0 in this slave
//
// ============================================================================
module AXI_ROM_Slave #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 1024
)
(
    input                       clk,
    input                       reset,    // Active LOW

    // =====================================================
    // WRITE ADDRESS CHANNEL
    // =====================================================
    input [ADDR_WIDTH - 1:0]    s_axi_awaddr,
    input                       s_axi_awvalid,
    output                      s_axi_awready,

    // =====================================================
    // WRITE DATA CHANNEL
    // =====================================================
    input [DATA_WIDTH - 1:0]    s_axi_wdata,
    input [DATA_WIDTH/8-1:0]    s_axi_wstrb,
    input                       s_axi_wvalid,
    output                      s_axi_wready,

    // =====================================================
    // WRITE RESPONSE CHANNEL
    // =====================================================
    output reg [1:0]            s_axi_bresp,
    output reg                  s_axi_bvalid,
    input                       s_axi_bready,

    // =====================================================
    // READ ADDRESS CHANNEL
    // =====================================================
    input [ADDR_WIDTH - 1:0]    s_axi_araddr,
    input                       s_axi_arvalid,
    output                      s_axi_arready,

    // =====================================================
    // READ DATA CHANNEL
    // =====================================================
    output reg [DATA_WIDTH - 1:0]   s_axi_rdata,
    output reg [1:0]                s_axi_rresp,
    output reg                      s_axi_rvalid,
    input                           s_axi_rready
);

    // =====================================================
    // AXI RESPONSE
    // =====================================================
    localparam RESP_OKAY    = 2'b00;
    localparam RESP_SLVERR  = 2'b10;

    // =====================================================
    // WRITE FSM
    // =====================================================
    localparam WR_IDLE      = 2'd0;
    localparam WR_RESP      = 2'd1;

    reg [1:0] wr_state;

    // =====================================================
    // READ FSM
    // =====================================================
    localparam RD_IDLE      = 2'd0;
    localparam RD_WAIT      = 2'd1;
    localparam RD_LATCH     = 2'd2;
    localparam RD_VALID     = 2'd3;

    reg [1:0] rd_state;

    // =====================================================
    // WRITE CHANNEL REGISTERS
    // =====================================================
    reg [31:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;

    reg        aw_done;
    reg        w_done;

    // =====================================================
    // READ CHANNEL REGISTERS
    // =====================================================
    reg [31:0] araddr_reg;

    // =====================================================
    // ROM INTERFACE
    // =====================================================
    wire [31:0] rom_addr;
    wire [31:0] rom_instruction;

    assign rom_addr = araddr_reg;

    Instr_Memory instr_rom(

        .clk            (clk),

        // CPU-Style Read Interface
        .addr           (rom_addr),
        .instruction    (rom_instruction),

        // Bootloader
        .boot_mode      (1'b0),
        .we_boot        (1'b0),
        .addr_boot      (32'b0),
        .data_boot      (32'b0)
    );

    // =====================================================
    // READY GENERATION
    // =====================================================
    assign s_axi_awready = (wr_state == WR_IDLE) && !aw_done;
    
    assign s_axi_wready  = (wr_state == WR_IDLE) && !w_done;

    assign s_axi_arready = (rd_state == RD_IDLE);

    // =====================================================
    // HANDSHAKE DETECT
    // =====================================================
    wire aw_fire;
    wire w_fire;
    wire ar_fire;

    assign aw_fire = s_axi_awvalid && s_axi_awready;

    assign w_fire  = s_axi_wvalid && s_axi_wready;

    assign ar_fire = s_axi_arvalid && s_axi_arready;

    // =====================================================
    // ADDRESS VALID
    // ROM range: 0x0000_0000 ~ 0x0000_0FFF
    // =====================================================
    function automatic addr_valid;

        input [31:0] addr;

        begin
            addr_valid =
                (addr[31:12] == 20'h0);
        end

    endfunction

    // =====================================================
    // WRITE FSM
    // Read-only ROM:
    // + Accept AW
    // + Accept W
    // + Return SLVERR
    // + Do not write to Instr_Memory
    // =====================================================
    always @(posedge clk or negedge reset) begin
        
        if (!reset) begin
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;

            awaddr_reg      <= 32'b0;
            wdata_reg       <= 32'b0;
            wstrb_reg       <= 4'b0;

            aw_done         <= 1'b0;
            w_done          <= 1'b0;

            wr_state        <= WR_IDLE;
        end

        else begin
            // -------------------------------------------------
            // Capture AW
            // -------------------------------------------------
            if (aw_fire) begin
                awaddr_reg <= s_axi_awaddr;
                aw_done    <= 1'b1;
            end

            // -------------------------------------------------
            // Capture W
            // -------------------------------------------------
            if (w_fire) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                w_done    <= 1'b1;
            end

            // -------------------------------------------------
            // FSM
            // -------------------------------------------------
            case (wr_state)

                // =============================================
                // IDLE
                // =============================================
                WR_IDLE: begin

                    if (aw_done && w_done) begin

                        // ROM is read-only.
                        // Any write transaction returns SLVERR.
                        s_axi_bresp  <= RESP_SLVERR;
                        s_axi_bvalid <= 1'b1;

                        wr_state <= WR_RESP;

                    end

                end

                // =============================================
                // RESPONSE
                // =============================================
                WR_RESP: begin

                    if (s_axi_bvalid && s_axi_bready) begin

                        s_axi_bvalid <= 1'b0;
                        s_axi_bresp  <= RESP_OKAY;

                        aw_done      <= 1'b0;
                        w_done       <= 1'b0;

                        wr_state     <= WR_IDLE;

                    end

                end

                default: begin

                    wr_state <= WR_IDLE;

                end

            endcase
        end

    end

    // =====================================================
    // READ FSM
    // Read word from Instr_Memory
    // =====================================================
    always @(posedge clk or negedge reset) begin
        
        if (!reset) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rdata  <= 32'b0;

            araddr_reg   <= 32'b0;

            rd_state     <= RD_IDLE;
        end

        else begin
            case (rd_state) 

                // =============================================
                // IDLE
                // =============================================
                RD_IDLE: begin

                    if (ar_fire) begin

                        araddr_reg <= s_axi_araddr;

                        rd_state <= RD_WAIT;

                    end

                end

                // =============================================
                // WAIT
                // Give Instr_Memory combinational read path
                // one cycle to settle after araddr_reg update.
                // =============================================
                RD_WAIT: begin

                    rd_state <= RD_LATCH;

                end

                // =============================================
                // LATCH
                // =============================================
                RD_LATCH: begin

                    if (addr_valid(araddr_reg)) begin

                        s_axi_rdata <= rom_instruction;
                        s_axi_rresp <= RESP_OKAY;

                    end

                    else begin

                        s_axi_rdata <= 32'b0;
                        s_axi_rresp <= RESP_SLVERR;

                    end

                    s_axi_rvalid <= 1'b1;

                    rd_state <= RD_VALID;

                end

                // =============================================
                // VALID
                // =============================================
                RD_VALID: begin

                    if (s_axi_rvalid && s_axi_rready) begin

                        s_axi_rvalid <= 1'b0;
                        s_axi_rresp  <= RESP_OKAY;

                        rd_state <= RD_IDLE;

                    end

                end

                default: begin

                    rd_state <= RD_IDLE;

                end

            endcase
        end

    end

endmodule