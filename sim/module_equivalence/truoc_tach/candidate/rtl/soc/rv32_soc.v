`default_nettype none

`include "soc_map.vh"

// =============================================================================
// Module      : rv32_soc
// Chức năng   : SoC 32 bit cho bài toán ước lượng SOC pin trên DE10-Lite.
// Purpose: nối core RV32I với memory/MMIO qua bus request/response đã đăng ký.
// Clock: clk_i. Reset: rst_i synchronous active-high chung cho toàn hệ thống.
// Inputs: switch/I2C đã đồng bộ, UART RX bất đồng bộ có synchronizer riêng.
// Outputs: GPIO_LED_WIDTH LED, serial/open-drain, trap và trạng thái QNN.
// Protocol: instruction req/gnt+rvalid; data req/ready/err, một giao dịch outstanding.
// Latency: data thêm hai cạnh qua bus so với slave; instruction giữ nguyên.
// Error behavior: lỗi data/fetch truyền về precise trap-and-halt của core.
//
// Thành phần:
//   - rv32_core: RV32I pipeline 5 tầng, Harvard, có wait-state và precise trap.
//   - ROM 32 KiB hai cổng, SRAM 8 KiB.
//   - GPIO, UART TX/RX, I2C master, timer 64 bit và QNN accelerator 80-16-8-1.
//
// Memory map:
//   0x0000_0000..0x0000_7FFF : ROM 32 KiB, execute/read-only
//   0x1000_0000..0x1000_1FFF : SRAM
//   0x2000_0000..0x2000_0FFF : GPIO
//   0x2000_1000..0x2000_1FFF : UART TX/RX
//   0x2000_2000..0x2000_2FFF : I2C master
//   0x2000_3000..0x2000_3FFF : QNN accelerator
//   0x2000_4000..0x2000_4FFF : timer
//
// Bus dữ liệu chốt request/response; địa chỉ sai và ghi ROM kết thúc bằng fault.
// Cổng lấy lệnh nối thẳng ROM, nhận req/gnt và trả rvalid sau một chu kỳ.
// Core và các slave cùng clock/reset. Các chân bất đồng bộ phải được đồng bộ
// ở lớp board, ngoại trừ UART RX đồng bộ ngay trong uart_rx. Đặc tả: docs/giao_tiep_rtl_vi.md.
// =============================================================================
module rv32_soc #(
    // Tần số clk_i tính bằng Hz, dùng tính bộ chia UART/I2C.
    parameter integer CLOCK_HZ = 50000000,
    // Board dành LED[8:9] cho debug; phần mềm mặc định chỉ điều khiển 8 LED.
    parameter integer GPIO_LED_WIDTH = 8,
    // Dung lượng ROM theo số word 32 bit; số byte bằng ROM_WORDS*4.
    parameter integer ROM_WORDS = 8192,
    // Dung lượng SRAM theo số word 32 bit; số byte bằng RAM_WORDS*4.
    parameter integer RAM_WORDS = 2048,
    // Chuyển cờ nạp ROM tới wrapper; mô phỏng bật nạp file khi khác 0.
    parameter integer USE_ROM_INIT_FILE = 0,
    // File khởi tạo ROM chương trình, chuyển tới soc_rom_dp.
    parameter         ROM_INIT_FILE = "",
    // Chuyển cờ nạp các file model xuống QNN accelerator.
    parameter integer USE_QNN_INIT_FILES = 0,
    // Số bit dịch phải số học sau MAC lớp 1, trước ReLU/bão hòa INT8.
    parameter integer QNN_L1_SHIFT = 0,
    // Số bit dịch phải số học sau MAC lớp 2, trước ReLU/bão hòa INT8.
    parameter integer QNN_L2_SHIFT = 0,
    // Số bit dịch phải số học đầu ra trước khi chặn về 0..1000.
    parameter integer QNN_OUT_SHIFT = 0,
    // File trọng số INT8 lớp 1, thứ tự neuron*80 + feature.
    parameter         QNN_L1_WEIGHT_FILE = "",
    // File HEX bias INT32 cho 16 neuron lớp 1.
    parameter         QNN_L1_BIAS_FILE = "",
    // File trọng số INT8 lớp 2, thứ tự neuron*16 + đầu vào.
    parameter         QNN_L2_WEIGHT_FILE = "",
    // File HEX bias INT32 cho 8 neuron lớp 2.
    parameter         QNN_L2_BIAS_FILE = "",
    // File HEX 8 trọng số INT8 của neuron đầu ra.
    parameter         QNN_OUT_WEIGHT_FILE = "",
    // File HEX một bias INT32 của neuron đầu ra.
    parameter         QNN_OUT_BIAS_FILE = ""
) (
    // Nhóm clock/reset dùng chung cho core, decoder và mọi slave.
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire       clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire       rst_i,

    // Nhóm GPIO và UART nối tới lớp board.
    // Mức của 10 switch đã đồng bộ với clk_i tại lớp board.
    input  wire [9:0] switches_i,
    // Giá trị thanh ghi GPIO GPIO_LED_WIDTH bit; lớp board quyết định ánh xạ ra LED vật lý.
    output wire [GPIO_LED_WIDTH-1:0] leds_o,
    // Đường UART phát 8N1, LSB trước; mức rảnh là 1.
    output wire       uart_tx_o,
    // RX bất đồng bộ; uart_rx sở hữu synchronizer hai FF.
    input wire uart_rx_i,

    // Nhóm I2C open-drain: đầu vào là mức chân, đầu ra là yêu cầu kéo thấp.
    // Mức SCL thực tế đã đồng bộ; dùng để phát hiện clock stretching.
    input  wire       i2c_scl_i,
    // Mức SDA thực tế đã đồng bộ; dùng để nhận dữ liệu/ACK và kiểm tra bus.
    input  wire       i2c_sda_i,
    // 1: yêu cầu kéo SCL xuống 0; 0: nhả chân ở high-Z qua lớp board.
    output wire       i2c_scl_drive_low_o,
    // 1: yêu cầu kéo SDA xuống 0; 0: nhả chân để điện trở pull-up kéo cao.
    output wire       i2c_sda_drive_low_o,

    // Nhóm trạng thái lỗi CPU đã chốt tại WB.
    // Core đã dừng do trap; giữ mức 1 đến reset.
    output wire       halted_o,
    // Ngoại lệ đã commit tại WB; giữ 1 cùng metadata trap đến reset.
    output wire       trap_valid_o,
    // Mã ngoại lệ đã chốt; có nghĩa khi trap_valid=1.
    output wire [4:0] trap_cause_o,
    // PC của lệnh gây trap; có nghĩa khi trap_valid=1.
    output wire [31:0] trap_pc_o,

    // Nhóm trạng thái và kết quả accelerator.
    // 1: accelerator đang suy luận; 0: rảnh.
    output wire       qnn_busy_o,
    // Cờ hoàn tất, giữ tới start mới, lệnh clear-done hoặc reset.
    output wire       qnn_done_o,
    // Kết quả suy luận gần nhất, 0..1000; mỗi đơn vị bằng 0,1 %SOC.
    output wire [31:0] qnn_result_o
);

    // Kênh lấy lệnh core <-> ROM: request/grant trước, response sau.
    // Yêu cầu lấy lệnh; giữ mức 1 cùng địa chỉ tới cạnh req && gnt.
    wire        imem_req;
    // Địa chỉ byte lấy lệnh, căn 4; giữ ổn định khi req && !gnt.
    wire [31:0] imem_addr;
    // Memory nhận yêu cầu tại cạnh req && gnt; chưa phải dữ liệu trả về.
    wire        imem_gnt;
    // Có đáp ứng cho yêu cầu đã grant trước đó; không có rready.
    wire        imem_rvalid;
    // Word lệnh trả về; chỉ dùng khi rvalid=1 và err=0.
    wire [31:0] imem_rdata;
    // Lỗi lấy lệnh; chỉ xét cùng rvalid, tạo cause 1 nếu đúng đường.
    wire        imem_err;

    // Kênh dữ liệu core <-> decoder: giữ request đến khi ready.
    // Yêu cầu load/store; giữ nguyên payload tới cạnh req && ready.
    wire        dmem_req;
    // 1: ghi, 0: đọc; bằng 0 khi không có yêu cầu dữ liệu.
    wire        dmem_we;
    // Địa chỉ byte đã căn xuống biên 4 byte; LSU xử lý byte lane riêng.
    wire [31:0] dmem_addr;
    // Dữ liệu store đã đặt vào đúng byte lane của word 32 bit.
    wire [31:0] dmem_wdata;
    // Bit n cho phép ghi byte [8*n +: 8]; bằng 0 khi không ghi.
    wire [3:0]  dmem_wstrb;
    // Word đọc từ bus; chỉ dùng khi req && ready && !we && !err.
    wire [31:0] dmem_rdata;
    // Hoàn tất giao dịch tại cạnh req && ready, kể cả khi err=1.
    wire        dmem_ready;
    // Lỗi data bus; chỉ có nghĩa khi req && ready, sinh cause 5/7.
    wire        dmem_err;

    // Payload sau thanh ghi request của bus; slave không dùng trực tiếp dmem_*.
    wire bus_we;
    wire [31:0] bus_addr, bus_wdata;
    wire [3:0] bus_wstrb;
    // Request và response của mỗi slave nối vào cùng một lane có tên.
    // Bit SOC_SLAVE_* chọn slave; tối đa một bit bằng 1, reset/idle bằng 0.
    wire [`SOC_SLAVE_COUNT-1:0]    slave_req;
    // Lane n dùng [n*32 +: 32]; response phải khớp lane request được chọn.
    wire [`SOC_SLAVE_COUNT*32-1:0] slave_rdata;
    // Bit n báo hoàn tất từ slave n; chỉ lane được chọn được trả về master.
    wire [`SOC_SLAVE_COUNT-1:0]    slave_ready;
    // Bit n báo lỗi từ slave n; chỉ xét cùng ready của chính lane đó.
    wire [`SOC_SLAVE_COUNT-1:0]    slave_err;

    // 1. Core CPU: nguồn phát yêu cầu lấy lệnh và truy cập dữ liệu.
    rv32_core #(
        .RESET_VECTOR(`SOC_ROM_BASE)
    ) u_core (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .imem_req_o(imem_req),
        .imem_addr_o(imem_addr),
        .imem_gnt_i(imem_gnt),
        .imem_rvalid_i(imem_rvalid),
        .imem_rdata_i(imem_rdata),
        .imem_err_i(imem_err),
        .dmem_req_o(dmem_req),
        .dmem_we_o(dmem_we),
        .dmem_addr_o(dmem_addr),
        .dmem_wdata_o(dmem_wdata),
        .dmem_wstrb_o(dmem_wstrb),
        .dmem_rdata_i(dmem_rdata),
        .dmem_ready_i(dmem_ready),
        .dmem_err_i(dmem_err),
        .halted_o(halted_o),
        .trap_valid_o(trap_valid_o),
        .trap_cause_o(trap_cause_o),
        .trap_pc_o(trap_pc_o),
        .trap_instr_o(),
        .retire_valid_o(),
        .retire_pc_o(),
        .retire_instr_o(),
        .retire_rd_we_o(),
        .retire_rd_addr_o(),
        .retire_rd_data_o(),
        .debug_fetch_pc_o()
    );

    // 2. Decoder dữ liệu: chọn một slave và lấy đúng response của slave đó.
    soc_bus #(
        .ROM_WORDS(ROM_WORDS),
        .RAM_WORDS(RAM_WORDS)
    ) u_bus (
        .clk_i(clk_i),
        .wdata_i(dmem_wdata),
        .wstrb_i(dmem_wstrb),
        .slave_we_o(bus_we),
        .slave_addr_o(bus_addr),
        .slave_wdata_o(bus_wdata),
        .slave_wstrb_o(bus_wstrb),
        .rst_i(rst_i),
        .req_i(dmem_req),
        .we_i(dmem_we),
        .addr_i(dmem_addr),
        .rdata_o(dmem_rdata),
        .ready_o(dmem_ready),
        .err_o(dmem_err),
        .slave_req_o(slave_req),
        .slave_rdata_i(slave_rdata),
        .slave_ready_i(slave_ready),
        .slave_err_i(slave_err)
    );

    // 3. Bộ nhớ: cổng instruction của ROM nối trực tiếp core, không qua decoder.
    soc_rom_dp #(
        .WORDS(ROM_WORDS),
        .USE_INIT_FILE(USE_ROM_INIT_FILE),
        .INIT_FILE(ROM_INIT_FILE)
    ) u_rom (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .i_req_i(imem_req),
        .i_addr_i(imem_addr),
        .i_gnt_o(imem_gnt),
        .i_rvalid_o(imem_rvalid),
        .i_rdata_o(imem_rdata),
        .i_err_o(imem_err),
        .d_req_i(slave_req[`SOC_SLAVE_ROM]),
        .d_addr_i(bus_addr),
        .d_rdata_o(slave_rdata[`SOC_SLAVE_ROM*32 +: 32]),
        .d_ready_o(slave_ready[`SOC_SLAVE_ROM]),
        .d_err_o(slave_err[`SOC_SLAVE_ROM])
    );

    soc_ram #(.WORDS(RAM_WORDS)) u_ram (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(slave_req[`SOC_SLAVE_RAM]),
        .we_i(bus_we),
        .addr_i(bus_addr - `SOC_RAM_BASE),
        .wdata_i(bus_wdata),
        .wstrb_i(bus_wstrb),
        .rdata_o(slave_rdata[`SOC_SLAVE_RAM*32 +: 32]),
        .ready_o(slave_ready[`SOC_SLAVE_RAM]),
        .err_o(slave_err[`SOC_SLAVE_RAM])
    );

    // 4. Slave MMIO theo thứ tự lane; địa chỉ đầu vào là offset byte cục bộ.
    soc_gpio #(.GPIO_LED_WIDTH(GPIO_LED_WIDTH)) u_gpio (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(slave_req[`SOC_SLAVE_GPIO]),
        .we_i(bus_we),
        .addr_i(bus_addr[11:0]),
        .wdata_i(bus_wdata),
        .wstrb_i(bus_wstrb),
        .rdata_o(slave_rdata[`SOC_SLAVE_GPIO*32 +: 32]),
        .ready_o(slave_ready[`SOC_SLAVE_GPIO]),
        .err_o(slave_err[`SOC_SLAVE_GPIO]),
        .switches_i(switches_i),
        .leds_o(leds_o)
    );

    soc_uart #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD(115200)
    ) u_uart (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(slave_req[`SOC_SLAVE_UART]),
        .we_i(bus_we),
        .addr_i(bus_addr[11:0]),
        .wdata_i(bus_wdata),
        .wstrb_i(bus_wstrb),
        .rdata_o(slave_rdata[`SOC_SLAVE_UART*32 +: 32]),
        .ready_o(slave_ready[`SOC_SLAVE_UART]),
        .err_o(slave_err[`SOC_SLAVE_UART]),
        .tx_o(uart_tx_o),
        .rx_i(uart_rx_i),
        .busy_o()
    );

    soc_i2c_master #(
        .CLOCK_HZ(CLOCK_HZ),
        .I2C_HZ(100000)
    ) u_i2c (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(slave_req[`SOC_SLAVE_I2C]),
        .we_i(bus_we),
        .addr_i(bus_addr[11:0]),
        .wdata_i(bus_wdata),
        .wstrb_i(bus_wstrb),
        .rdata_o(slave_rdata[`SOC_SLAVE_I2C*32 +: 32]),
        .ready_o(slave_ready[`SOC_SLAVE_I2C]),
        .err_o(slave_err[`SOC_SLAVE_I2C]),
        .scl_i(i2c_scl_i),
        .sda_i(i2c_sda_i),
        .scl_drive_low_o(i2c_scl_drive_low_o),
        .sda_drive_low_o(i2c_sda_drive_low_o),
        .busy_o()
    );

    qnn_soc_accelerator #(
        .USE_INIT_FILES(USE_QNN_INIT_FILES),
        .L1_SHIFT(QNN_L1_SHIFT),
        .L2_SHIFT(QNN_L2_SHIFT),
        .OUT_SHIFT(QNN_OUT_SHIFT),
        .L1_WEIGHT_FILE(QNN_L1_WEIGHT_FILE),
        .L1_BIAS_FILE(QNN_L1_BIAS_FILE),
        .L2_WEIGHT_FILE(QNN_L2_WEIGHT_FILE),
        .L2_BIAS_FILE(QNN_L2_BIAS_FILE),
        .OUT_WEIGHT_FILE(QNN_OUT_WEIGHT_FILE),
        .OUT_BIAS_FILE(QNN_OUT_BIAS_FILE)
    ) u_qnn (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .bus_req_i(slave_req[`SOC_SLAVE_QNN]),
        .bus_we_i(bus_we),
        .bus_addr_i(bus_addr[11:0]),
        .bus_wdata_i(bus_wdata),
        .bus_wstrb_i(bus_wstrb),
        .bus_rdata_o(slave_rdata[`SOC_SLAVE_QNN*32 +: 32]),
        .bus_ready_o(slave_ready[`SOC_SLAVE_QNN]),
        .bus_err_o(slave_err[`SOC_SLAVE_QNN]),
        .busy_o(qnn_busy_o),
        .done_o(qnn_done_o),
        .result_o(qnn_result_o)
    );

    soc_timer u_timer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req_i(slave_req[`SOC_SLAVE_TIMER]),
        .we_i(bus_we),
        .addr_i(bus_addr[11:0]),
        .wdata_i(bus_wdata),
        .wstrb_i(bus_wstrb),
        .rdata_o(slave_rdata[`SOC_SLAVE_TIMER*32 +: 32]),
        .ready_o(slave_ready[`SOC_SLAVE_TIMER]),
        .err_o(slave_err[`SOC_SLAVE_TIMER]),
        .irq_o()
    );

endmodule

`default_nettype wire
