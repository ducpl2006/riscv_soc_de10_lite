// ============================================================================
// Module APB4_GPIO_Slave
// ----------------------------------------------------------------------------
// APB4 GPIO Peripheral
//
// External address region:
// 0x1000_0000 - 0x1000_00FF
//
// Internal Register Map:
// ----------------------------------------------------------------------------
// Offset 0x00 : LEDR Register      R/W
// Offset 0x04 : HEX Data Register  R/W
// Offset 0x0C : Switch Register    R
//
// Architecture:
// APB4_Interconnect
//        |
//        v
// APB4_GPIO_Slave
//        |
//        +---- LEDR[9:0]
//        +---- SW[9:0]
//        +---- Hex7_Seg
//
// APB4 characteristics:
// - Zero wait-state peripheral
// - PREADY is always 1
// - Supports PSLVERR
// - PPROT is accepted but not used
//
// Reset:
// PRESETn = 0 : reset active
// PRESETn = 1 : normal operation
// ============================================================================
module APB4_GPIO_Slave #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input                       clk,
    input                       reset,

    // ================================
    // APB4 Slave Interface
    // ================================
    input [ADDR_WIDTH - 1:0]    PADDR,
    input                       PSEL,
    input                       PENABLE,
    input                       PWRITE,

    input [DATA_WIDTH - 1:0]    PWDATA,
    input [DATA_WIDTH/8-1:0]    PSTRB,
    input [2:0]                 PPROT,

    output [DATA_WIDTH - 1:0]   PRDATA,
    output                      PREADY,
    output                      PSLVERR,

    // ================================
    // FPGA I/O
    // ================================
    input [9:0]                 SW,

    output [9:0]                LEDR,

    output [6:0]                HEX0,
    output [6:0]                HEX1,
    output [6:0]                HEX2,
    output [6:0]                HEX3,
    output [6:0]                HEX4,
    output [6:0]                HEX5
);

    // Register Offset
    localparam LEDR_OFFSET      = 8'h00;
    localparam HEX_OFFSET       = 8'h04;
    localparam SWITCH_OFFSET    = 8'h0C;

    // ==================================================
    // ADDRESS OFFSET
    // ==================================================
    // APB4_Interconnect đã decode vùng:
    //
    // 0x1000_0000 - 0x1000_00FF
    //
    // Bên trong GPIO chỉ cần dùng 8 bit thấp làm offset.
    // ==================================================
    wire [7:0] gpio_offset;

    assign gpio_offset = PADDR[7:0];

    // =================================================
    // APB Phase Detection
    // =================================================
    wire apb_setup;
    wire apb_access;

    assign apb_setup  = PSEL && !PENABLE;
    assign apb_access = PSEL && PENABLE;

    // ==================================================
    // ADDRESS VALIDATION
    // LEDR, HEX, SW đều có thể đọc
    // ==================================================
    wire read_addr_valid;

    assign read_addr_valid = (gpio_offset == LEDR_OFFSET) || (gpio_offset == HEX_OFFSET) || (gpio_offset == SWITCH_OFFSET);

    // Chỉ LEDR và HEX có thể write
    wire write_addr_valid;

    assign write_addr_valid = (gpio_offset == LEDR_OFFSET) || (gpio_offset == HEX_OFFSET);

    // Kiểm tra địa chỉ truy cập không hợp lệ
    wire access_error;

    assign access_error = PWRITE ? !write_addr_valid : !read_addr_valid;

    // ==================================================
    // APB RESPONSE
    // GPIO hoàn thành trasaction ngay trong ACCESS phase
    // PREADY có thể giữ liên tục bằng 1:
    // + PREADY chỉ có ý nghĩa khi PSEL, PENABLE = 1
    // ==================================================
    assign PREADY = 1'b1;

    // PSLVERR chỉ có ý nghĩa tại chu kỳ hoàn thành ACCESS.
    //
    // Các trường hợp lỗi:
    // - Đọc offset không tồn tại
    // - Ghi offset không tồn tại
    // - Ghi vào SWITCH vì SWITCH là read-only
    assign PSLVERR = apb_access && PREADY && access_error;

    // ==================================================
    // GPIO BUS INTERFACE
    // ==================================================
    wire [31:0] gpio_addr;
    wire [31:0] gpio_wr_data;

    wire        gpio_write_en;
    wire        gpio_read_en;

    wire [31:0] gpio_rd_data;

    wire [23:0] hex_data;

    assign gpio_addr = PADDR[31:0];

    assign gpio_wr_data = PWDATA[31:0];

    // ==================================================
    // GPIO WRITE ENABLE
    // ==================================================
    // Write chỉ xảy ra tại cạnh clock kết thúc ACCESS:
    //
    // PSEL    = 1
    // PENABLE = 1
    // PWRITE  = 1
    // PREADY  = 1
    //
    // Nếu địa chỉ không hợp lệ thì không ghi GPIO core.
    // ==================================================
    assign gpio_write_en = apb_access && PREADY && PWRITE && write_addr_valid;

    // ==================================================
    // GPIO READ ENABLE
    // ==================================================
    // Read mux trong GPIO là combinational.
    //
    // Có thể bật read_en ngay từ SETUP để rd_data có đủ
    // thời gian ổn định trước khi kết thúc ACCESS.
    // ==================================================
    assign gpio_read_en = PSEL && !PWRITE && read_addr_valid;

    // ==================================================
    // GPIO MODULE
    // ==================================================
    GPIO gpio (

        .clk            (clk),
        .reset          (reset),

        .addr           (gpio_addr),
        .wr_data        (gpio_wr_data),

        .write_en       (gpio_write_en),
        .read_en        (gpio_read_en),

        .SW             (SW),

        .LEDR           (LEDR),
        
        .hex_data_out   (hex_data),

        .rd_data        (gpio_rd_data)
    );

    // ==================================================
    // APB READ DATA
    // ==================================================
    // GPIO core tạo gpio_rd_data bằng read mux tổ hợp.
    //
    // Khi không phải read hợp lệ, PRDATA trả về 0.
    // ==================================================
    assign PRDATA = (PSEL && !PWRITE && read_addr_valid) ? gpio_rd_data : {DATA_WIDTH{1'b0}};

    // ==================================================
    // HEX DISPLAY
    // ==================================================
    Hex7_Seg hex_display (

        .clk            (clk),
        .reset          (reset),

        .write_en       (1'b1),

        .wr_data        ({8'b0, hex_data}),

        .HEX0           (HEX0),
        .HEX1           (HEX1),
        .HEX2           (HEX2),
        .HEX3           (HEX3),
        .HEX4           (HEX4),
        .HEX5           (HEX5)
    );
    
endmodule