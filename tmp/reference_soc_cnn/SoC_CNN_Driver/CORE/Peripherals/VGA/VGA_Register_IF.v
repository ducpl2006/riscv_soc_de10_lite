// ============================================================================
// Module VGA_Register_IF
// ----------------------------------------------------------------------------
// Register Interface cho VGA subsystem
//
// Chức năng:
//   + Address decode
//   + TEXT RAM access
//   + CTRL register access
//   + STATUS register access
//   + Readback mux
//
// NOTE:
//   + Giữ nguyên VGA_CORE cũ
//   + KHÔNG thay đổi render/timing logic
//   + Dùng cho AXI_VGA_Slave
// ============================================================================

module VGA_Register_IF (

    input clk,
    input reset,

    // ======================================================
    // Register Interface
    // ======================================================
    input [31:0]        addr,
    input [31:0]        wr_data,
    input               write_en,
    input               read_en,
    
    output reg [31:0]   rd_data,

    // ======================================================
    // VGA CORE Interface
    // ======================================================

    // TEXT RAM
    output reg          text_we,
    output reg [11:0]   text_addr_cpu,
    output reg [15:0]   text_data_cpu,

    // CONTROL REGISTER
    output reg          ctrl_we,
    output reg [31:0]   ctrl_data,

    // READBACK
    input [31:0]        ctrl_rd_data,
    input [31:0]        stat_rd_data
);

    // ============================================================
    // ADDRESS MAP
    // ============================================================
    //
    // BASE : 0x3000_0000
    //
    // ----------------------------------------------------
    // TEXT RAM
    // ----------------------------------------------------
    // 0x3000_0000 ~ 0x3000_257F
    //
    // 2400 cells
    // mỗi cell = 16-bit
    // word aligned
    //
    // ----------------------------------------------------
    // CONTROL REGISTER
    // ----------------------------------------------------
    // 0x3000_4000
    //
    // ----------------------------------------------------
    // STATUS REGISTER
    // ----------------------------------------------------
    // 0x3000_4004
    //
    // ===============================================================
    localparam BASE_ADDR        = 32'h3000_0000;

    localparam TEXT_RAM_START   = 32'h0000;
    localparam TEXT_RAM_END     = 32'h257F;

    localparam CTRL_REG_ADDR    = 32'h4000;
    localparam STAT_REG_ADDR    = 32'h4004;

    // ======================================================
    // OFFSET
    // ======================================================
    wire [15:0] offset;

    assign offset = addr - BASE_ADDR;

    // ======================================================
    // REGION SELECT
    // ======================================================
    wire sel_text_ram;
    wire sel_ctrl_reg;
    wire sel_stat_reg;

    assign sel_text_ram = (offset >= TEXT_RAM_START) && (offset <= TEXT_RAM_END);

    assign sel_ctrl_reg = (offset == CTRL_REG_ADDR);

    assign sel_stat_reg = (offset == STAT_REG_ADDR);

    // ======================================================
    // TEXT RAM ADDRESS
    // ======================================================
    //
    // Word aligned
    //
    // Example:
    //   0x3000_0000 -> addr 0
    //   0x3000_0004 -> addr 1
    //
    // ======================================================

    wire [11:0] text_addr_next;

    assign text_addr_next = offset[13:2];

    // ======================================================
    // WRITE LOGIC
    // ======================================================
    always @(posedge clk or negedge reset) begin
        
        if (!reset) begin
            text_we         <= 1'b0;
            text_addr_cpu   <= 12'b0;
            text_data_cpu   <= 16'b0;

            ctrl_we         <= 1'b0;
            ctrl_data       <= 32'b0;
        end

        else begin
            
            // =============== DEFAULT ===============
            text_we         <= 1'b0;
            ctrl_we         <= 1'b0;

            // =============== TEXT RAM WRITE ===============
            if (write_en && sel_text_ram) begin
                text_we         <= 1'b1;
                text_addr_cpu   <= text_addr_next;
                text_data_cpu   <= wr_data[15:0];
            end

            // =============== CONTROL REGISTER WRITE ===============
            if (write_en && sel_ctrl_reg) begin
                ctrl_we         <= 1'b1;
                ctrl_data       <= wr_data;
            end
        end

    end

    // ======================================================
    // READ LOGIC
    // ======================================================
    always @(*) begin
        
        rd_data = 32'b0;

        if (read_en) begin
            
            // =============== CONTROL REGISTER ===============
            if (sel_ctrl_reg) begin
                rd_data = ctrl_rd_data;
            end

            // =============== STATUS REGISTER ===============
            else if (sel_stat_reg) begin
                rd_data = stat_rd_data;
            end

            // =============== TEXT RAM READBACK ===============
            else if (sel_text_ram) begin
                rd_data = {16'b0, text_data_cpu};
            end
        end

    end

endmodule