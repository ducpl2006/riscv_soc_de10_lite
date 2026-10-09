// ============================================================================
// APB4 Interconnect
// ----------------------------------------------------------------------------
// Single APB4 Master -> Two APB4 Slaves
//
// Architecture:
//
// AXI_to_APB4_Bridge
//          |
//          | APB4 Master Interface
//          v
//   APB4_Interconnect
//          |
//          +---------------- APB4_GPIO_Slave
//          |
//          +---------------- APB4_UART_Slave
//          |
//          +---------------- APB4_I2C_Slave
//
// Memory Map:
// ----------------------------------------------------------------------------
// 0x1000_0000 - 0x1000_00FF : APB Slave 0 - GPIO
// 0x2000_0000 - 0x2000_00FF : APB Slave 1 - UART
// 0x4000_0000 - 0x4000_00FF : APB Slave 2 - I2C
//
// Characteristics:
// ----------------------------------------------------------------------------
// - Pure combinational interconnect
// - No internal FSM
// - No internal clock or reset required
// - Address/control/data signals are broadcast to both slaves
// - Only PSEL is generated separately for each slave
// - PRDATA/PREADY/PSLVERR are multiplexed from the selected slave
// - Invalid address returns PREADY = 1 and PSLVERR = 1
// - Supports APB4 PSTRB and PPROT
// ============================================================================
module APB4_Interconnect #(

    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32
)
(
    // =============================================
    // APB4 MASTER SIDE
    // + Connected to AXI_to_APB4_Bridge
    // =============================================
    input [ADDR_WIDTH - 1:0]    m_apb_paddr,
    input                       m_apb_psel,
    input                       m_apb_penable,
    input                       m_apb_pwrite,
    input [DATA_WIDTH - 1:0]    m_apb_pwdata,
    input [DATA_WIDTH/8-1:0]    m_apb_pstrb,
    input [2:0]                 m_apb_pprot,

    output [DATA_WIDTH - 1:0]   m_apb_prdata,
    output                      m_apb_pready,
    output                      m_apb_pslverr,

    // =============================================
    // APB4 Slave 0: GPIO
    // =============================================
    output [ADDR_WIDTH - 1:0]   gpio_apb_paddr,
    output                      gpio_apb_psel,
    output                      gpio_apb_penable,
    output                      gpio_apb_pwrite,
    output [DATA_WIDTH - 1:0]   gpio_apb_pwdata,
    output [DATA_WIDTH/8-1:0]   gpio_apb_pstrb,
    output [2:0]                gpio_apb_pprot,

    input  [DATA_WIDTH - 1:0]   gpio_apb_prdata,
    input                       gpio_apb_pready,
    input                       gpio_apb_pslverr,

    // =============================================
    // APB4 Slave 1: UART
    // =============================================
    output [ADDR_WIDTH - 1:0]   uart_apb_paddr,
    output                      uart_apb_psel,
    output                      uart_apb_penable,
    output                      uart_apb_pwrite,
    output [DATA_WIDTH - 1:0]   uart_apb_pwdata,
    output [DATA_WIDTH/8-1:0]   uart_apb_pstrb,
    output [2:0]                uart_apb_pprot,

    input  [DATA_WIDTH - 1:0]   uart_apb_prdata,
    input                       uart_apb_pready,
    input                       uart_apb_pslverr,

    // =============================================
    // APB4 Slave 2: I2C
    // =============================================
    output [ADDR_WIDTH - 1:0]   i2c_apb_paddr,
    output                      i2c_apb_psel,
    output                      i2c_apb_penable,
    output                      i2c_apb_pwrite,
    output [DATA_WIDTH - 1:0]   i2c_apb_pwdata,
    output [DATA_WIDTH/8-1:0]   i2c_apb_pstrb,
    output [2:0]                i2c_apb_pprot,

    input  [DATA_WIDTH - 1:0]   i2c_apb_prdata,
    input                       i2c_apb_pready,
    input                       i2c_apb_pslverr
);

    // =============================================
    // APB4 MEMORY MAP
    // =============================================
    localparam GPIO_BASE = 32'h1000_0000;
    localparam GPIO_SIZE = 32'h0000_0100;
    localparam GPIO_END  = GPIO_BASE + GPIO_SIZE - 1;

    localparam UART_BASE = 32'h2000_0000;
    localparam UART_SIZE = 32'h0000_0100;
    localparam UART_END  = UART_BASE + UART_SIZE - 1;

    localparam I2C_BASE  = 32'h4000_0000;
    localparam I2C_SIZE  = 32'h0000_0100;
    localparam I2C_END   = I2C_BASE + I2C_SIZE - 1;

    // =============================================
    // ADDRESS DECODE
    // + Các tín hiệu hit chỉ kiểm tra PADDR
    // + Chưa bao gồm PSEL của APB MASTER
    // =============================================
    wire hit_gpio;
    wire hit_uart;
    wire hit_i2c;

    assign hit_gpio = (m_apb_paddr >= GPIO_BASE) && (m_apb_paddr <= GPIO_END);
    assign hit_uart = (m_apb_paddr >= UART_BASE) && (m_apb_paddr <= UART_END);
    assign hit_i2c  = (m_apb_paddr >= I2C_BASE)  && (m_apb_paddr <= I2C_END);

    // =============================================
    // SLAVE SELECTION 
    // + Chỉ bật PSEL cho Slave được chọn
    // + Độ ưu tiên: GPIO > UART
    // + Tín hiệu ưu tiên tránh việc chọn đồng thời 
    //   2 slave nếu memory map bị cấu hình sai
    // =============================================
    wire select_gpio;
    wire select_uart;
    wire select_i2c;

    assign select_gpio = m_apb_psel && hit_gpio;
    assign select_uart = m_apb_psel && hit_uart;
    assign select_i2c  = m_apb_psel && hit_i2c;

    // Có ít nhất một Slave được chọn
    wire decode_hit;

    assign decode_hit = hit_gpio | hit_uart | hit_i2c;

    // Trường hợp Master đang thực hiện Transaction nhưng địa chỉ không hợp lệ
    wire decode_miss;

    assign decode_miss = m_apb_psel && !decode_hit;

    // ========================================================================
    // FORWARD MASTER SIGNALS TO GPIO
    // ========================================================================
    // Các tín hiệu chung được broadcast đến GPIO.
    // GPIO chỉ được phép sử dụng chúng khi gpio_apb_psel = 1.
    // ========================================================================
    assign gpio_apb_paddr       = m_apb_paddr;
    assign gpio_apb_psel        = select_gpio;
    assign gpio_apb_penable     = m_apb_penable;
    assign gpio_apb_pwrite      = m_apb_pwrite;
    assign gpio_apb_pwdata      = m_apb_pwdata;
    assign gpio_apb_pstrb       = m_apb_pstrb;
    assign gpio_apb_pprot       = m_apb_pprot;

    // ========================================================================
    // FORWARD MASTER SIGNALS TO UART
    // ========================================================================
    assign uart_apb_paddr       = m_apb_paddr;
    assign uart_apb_psel        = select_uart;
    assign uart_apb_penable     = m_apb_penable;
    assign uart_apb_pwrite      = m_apb_pwrite;
    assign uart_apb_pwdata      = m_apb_pwdata;
    assign uart_apb_pstrb       = m_apb_pstrb;
    assign uart_apb_pprot       = m_apb_pprot;

    // ========================================================================
    // FORWARD MASTER SIGNALS TO I2C
    // ========================================================================
    assign i2c_apb_paddr        = m_apb_paddr;
    assign i2c_apb_psel         = select_i2c;
    assign i2c_apb_penable      = m_apb_penable;
    assign i2c_apb_pwrite       = m_apb_pwrite;
    assign i2c_apb_pwdata       = m_apb_pwdata;
    assign i2c_apb_pstrb        = m_apb_pstrb;
    assign i2c_apb_pprot        = m_apb_pprot;

    // ========================================================================
    // RETURN PATH MULTIPLEXER
    // ========================================================================
    // Chọn PRDATA, PREADY và PSLVERR từ slave đang được chọn.
    // ========================================================================
    wire [DATA_WIDTH - 1:0] selected_prdata;
    wire                    selected_pready;
    wire                    selected_pslverr;

    // Read Data MUX
    assign selected_prdata =
                             select_gpio ? gpio_apb_prdata :
                             select_uart ? uart_apb_prdata :
                             select_i2c  ? i2c_apb_prdata  :
                                            {DATA_WIDTH{1'b0}};

    // Ready MUX
    assign selected_pready =
                             select_gpio ? gpio_apb_pready :
                             select_uart ? uart_apb_pready :
                             select_i2c  ? i2c_apb_pready  :
                                            1'b0;

    // Slave ERROR MUX
    assign selected_pslverr =
                              select_gpio ? gpio_apb_pslverr :
                              select_uart ? uart_apb_pslverr :
                              select_i2c  ? i2c_apb_pslverr  :
                                            1'b0;
                                        
    // ========================================================================
    // RESPONSE TO APB MASTER
    // ========================================================================

    // ====================================================
    // Read Data
    // + Khi address miss, trả về dữ liệu bằng 0
    // Với write transaction, PRDATA không được sử dụng
    // ====================================================
    assign m_apb_prdata = selected_prdata;

    // ====================================================
    // PREADY
    // - Trường hợp bus IDLE:
    // + PSEL = 0
    // + PENABLE = 0
    // 
    // - Địa chỉ hợp lệ:
    // + PREADY lấy từ Slave được chọn
    //
    // - Địa chỉ không hợp lệ:
    // + PREADY = 1 --> Để kết thúc transaction ngay
    // + Tránh trường hợp Bridge bị treo trong ACCESS
    // ====================================================
    assign m_apb_pready = 
                         !m_apb_psel ? 1'b0 :
                         decode_miss ? 1'b1 :
                                        selected_pready;
                                    
    // =====================================================
    // PSLVERR
    // + PSLVERR chỉ có ý nghĩa tại chu kỳ cuối của ACCESS
    // PSEL = 1
    // PENABLE = 1
    // PREADY = 1
    //
    // ERROR có thể đến từ:
    // 1. Address miss tại APB4_Interconnect
    // 2. PSLVERR từ Slave
    // =====================================================
    assign m_apb_pslverr = 
                           m_apb_psel    &&
                           m_apb_penable &&
                           m_apb_pready  &&
                           (decode_miss || selected_pslverr);

endmodule