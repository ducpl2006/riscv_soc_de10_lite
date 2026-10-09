// ============================================================================
// Module APB4_I2C_Slave
// ----------------------------------------------------------------------------
// APB4 I2C Peripheral (mục A/L của plan).
//
// APB4_Interconnect
//        |
//        v
// APB4_I2C_Slave  --(addr/wr/rd/write_en/read_en)-->  I2C_Register_IF -> I2C_Master
//
// I2C Address Region: 0x4000_0000 - 0x4000_00FF
// Register offset: 0x00..0x34 (xem I2C_Register_IF).
//
// Vì I2C_Register_IF có rd_data COMBINATIONAL, mọi transfer hoàn tất trong 1 chu
// kỳ ACCESS (zero wait state):
//   - PREADY = 1 ngay khi vào ACCESS.
//   - Write: write_en xung 1 cycle (ACCESS), PSTRB mask PWDATA.
//   - Read : read_en xung 1 cycle (ACCESS); RXDATA pop đúng 1 lần.
//   - Địa chỉ ngoài dải hợp lệ: PREADY=1 + PSLVERR=1 (kết thúc, tránh treo).
//
// Reset: active-low (PRESETn dùng chung `reset`).
// ============================================================================
module APB4_I2C_Slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input                       clk,
    input                       reset,

    // ================================
    // APB4 Slave Interface
    // ================================
    input  [ADDR_WIDTH - 1:0]   PADDR,
    input                       PSEL,
    input                       PENABLE,
    input                       PWRITE,
    input  [DATA_WIDTH - 1:0]    PWDATA,
    input  [DATA_WIDTH/8 - 1:0]  PSTRB,
    input  [2:0]                PPROT,

    output [DATA_WIDTH - 1:0]    PRDATA,
    output                      PREADY,
    output                      PSLVERR,

    // ================================
    // Interrupt + I2C pins
    // ================================
    output                      irq,
    inout                       scl,
    inout                       sda
);

    // ========================================================================
    // APB phase
    // ========================================================================
    wire access = PSEL && PENABLE;

    // ========================================================================
    // Address / permission
    // ========================================================================
    wire [7:0] off        = {PADDR[7:2], 2'b00};
    wire       addr_valid = (off <= 8'h34);

    // ========================================================================
    // PSTRB masking (giữ pattern apply_pstrb của UART slave)
    // ========================================================================
    function automatic [DATA_WIDTH - 1:0] apply_pstrb;
        input [DATA_WIDTH - 1:0] data;
        input [DATA_WIDTH/8 - 1:0] strb;
        integer i;
        begin
            apply_pstrb = {DATA_WIDTH{1'b0}};
            for (i = 0; i < DATA_WIDTH/8; i = i + 1)
                if (strb[i]) apply_pstrb[i*8 +: 8] = data[i*8 +: 8];
        end
    endfunction

    // ========================================================================
    // Register IF strobes
    // ========================================================================
    wire        write_en = access && PWRITE  && addr_valid;
    wire        read_en  = access && !PWRITE && addr_valid;
    wire [31:0] wr_data  = apply_pstrb(PWDATA, PSTRB);
    wire [31:0] rd_data;

    I2C_Register_IF u_reg (
        .clk(clk), .reset(reset),
        .addr(PADDR), .wr_data(wr_data),
        .write_en(write_en), .read_en(read_en), .rd_data(rd_data),
        .irq(irq), .scl_pad(scl), .sda_pad(sda)
    );

    // ========================================================================
    // APB response
    // ========================================================================
    assign PRDATA  = rd_data;
    assign PREADY  = access ? 1'b1 : 1'b0;
    assign PSLVERR = access && !addr_valid;

endmodule
