`default_nettype none
`include "../accelerator/qnn_model_config.vh"

// =============================================================================
// Module      : de10_lite_top
// Chức năng   : Top-level vật lý cho Terasic DE10-Lite (MAX 10 10M50).
// Purpose: POR, đồng bộ input, pinout và open-drain cho SoC.
// Clock: MAX10_CLK1_50. Reset: POR hoặc KEY[0], assert async/release sync 3 FF.
// Inputs: KEY/SW/UART_RX, chân hai chiều I2C. Outputs: LEDR/UART_TX và drive-low.
// Protocol: không MMIO ở lớp board; I2C chỉ lái 0 hoặc Z, UART 8N1.
// Latency: POR_CYCLES+3 trước chạy SoC; SW/I2C qua 2 FF.
// Error behavior: trap hiện ở LEDR[9], QNN busy ở LEDR[8].
//
// Kết nối mặc định:
//   - MAX10_CLK1_50: clock hệ thống 50 MHz.
//   - KEY[0]: reset nhấn mức thấp, assert nhanh và nhả đồng bộ qua 3 FF.
//   - SW: GPIO input; LEDR[7:0]: GPIO output; LEDR[8]: QNN busy;
//     LEDR[9]: trap/halt để chẩn đoán tại bàn thử.
//   - GPIO[0]: I2C SCL, GPIO[1]: I2C SDA (open-drain, cần pull-up ngoài).
//   - UART_TX được gán vào chân vật lý GPIO header số 2 (PIN_V9) trong QSF.
//   - UART_RX nối GPIO header số 3 (PIN_W9); FF đồng bộ nằm trong uart_rx.
// =============================================================================
module de10_lite_top #(
    // Số clock giữ POR sau cấu hình, chưa tính ba tầng đồng bộ nhả reset.
    parameter integer POR_CYCLES = 1024
) (
    // Clock 50 MHz từ oscillator trên board; nguồn clock chung của SoC.
    input  wire        MAX10_CLK1_50,
    // Nút nhấn active-low: KEY[0] reset, KEY[1] hiện không sử dụng.
    input  wire [1:0]  KEY,
    // 10 switch vật lý bất đồng bộ; đi qua hai tầng FF trước khi vào SoC.
    input  wire [9:0]  SW,
    // [7:0] GPIO LED, [8] QNN busy, [9] trap; bit 1 làm sáng LED tương ứng.
    output wire [9:0]  LEDR,
    // [0] SCL, [1] SDA: chân hai chiều open-drain, cần pull-up.
    inout  wire [1:0]  GPIO,
    // Chân phát UART 8N1 115200 baud, nối header PIN_V9 theo QSF.
    input wire UART_RX, // GPIO header [3], PIN_W9; 3.3-V UART RX.
    output wire        UART_TX
);

    // Tầng FF thứ nhất nhận SW bất đồng bộ; không dùng trực tiếp trong SoC.
    reg [9:0] switch_meta_q;
    // Tầng FF thứ hai đưa mức SW đã đồng bộ vào SoC.
    reg [9:0] switch_sync_q;
    // Tầng FF thứ nhất nhận mức SCL/SDA thực tế từ pad.
    reg [1:0] i2c_meta_q;
    // Tầng FF thứ hai; [0] SCL và [1] SDA đưa vào I2C master.
    reg [1:0] i2c_sync_q;
    // POR và KEY cùng đi qua bộ đồng bộ nhả reset, dùng chung cho toàn SoC.
    wire rst;
    // 8 bit LED phần mềm; LED[8:9] chỉ có nguồn debug riêng.
    wire [7:0] soc_leds;
    // Đường UART phát 8N1, LSB trước; mức rảnh là 1.
    wire uart_tx;
    // Yêu cầu kéo chân SCL thấp; bằng 0 thì nhả chân high-Z.
    wire i2c_scl_low;
    // Yêu cầu kéo chân SDA thấp; bằng 0 thì nhả chân high-Z.
    wire i2c_sda_low;
    // Ngoại lệ đã commit tại WB; giữ 1 cùng metadata trap đến reset.
    wire trap_valid;
    // 1: accelerator đang suy luận; 0: rảnh.
    wire qnn_busy;

    reset_controller #(.POR_CYCLES(POR_CYCLES)) u_reset (
        .clk_i(MAX10_CLK1_50), .key_reset_n_i(KEY[0]), .rst_o(rst));

    // SW và hai đường I2C không đồng bộ với clock hệ thống. Hai FF đầu vào giảm
    // xác suất metastability lan vào bus fabric/FSM; I2C 100 kHz dư ngân sách
    // cho độ trễ hai chu kỳ 50 MHz.
    always @(posedge MAX10_CLK1_50) begin
        if (rst) begin
            switch_meta_q <= 10'd0;
            switch_sync_q <= 10'd0;
            i2c_meta_q    <= 2'b11;
            i2c_sync_q    <= 2'b11;
        end
        else begin
            switch_meta_q <= SW;
            switch_sync_q <= switch_meta_q;
            i2c_meta_q    <= GPIO;
            i2c_sync_q    <= i2c_meta_q;
        end
    end

    assign GPIO[0] = i2c_scl_low ? 1'b0 : 1'bz;
    assign GPIO[1] = i2c_sda_low ? 1'b0 : 1'bz;
    assign UART_TX = uart_tx;
    assign LEDR[7:0] = soc_leds[7:0];
    assign LEDR[8]   = qnn_busy;
    assign LEDR[9]   = trap_valid;

    rv32_soc #(
        .CLOCK_HZ(50000000),
        .USE_ROM_INIT_FILE(1),
        .ROM_INIT_FILE("../firmware/build/boot.mif"),
        .USE_QNN_INIT_FILES(1),
        .QNN_L1_SHIFT(`QNN_MODEL_L1_SHIFT),
        .QNN_L2_SHIFT(`QNN_MODEL_L2_SHIFT),
        .QNN_OUT_SHIFT(`QNN_MODEL_OUT_SHIFT),
        .QNN_L1_WEIGHT_FILE("../firmware/model/l1_weights.mif"),
        .QNN_L1_BIAS_FILE("../firmware/model/l1_biases.hex"),
        .QNN_L2_WEIGHT_FILE("../firmware/model/l2_weights.mif"),
        .QNN_L2_BIAS_FILE("../firmware/model/l2_biases.hex"),
        .QNN_OUT_WEIGHT_FILE("../firmware/model/out_weights.hex"),
        .QNN_OUT_BIAS_FILE("../firmware/model/out_bias.hex")
    ) u_soc (
        .clk_i(MAX10_CLK1_50), .rst_i(rst), .switches_i(switch_sync_q), .leds_o(soc_leds),
        .uart_rx_i(UART_RX), .uart_tx_o(uart_tx), .i2c_scl_i(i2c_sync_q[0]), .i2c_sda_i(i2c_sync_q[1]),
        .i2c_scl_drive_low_o(i2c_scl_low), .i2c_sda_drive_low_o(i2c_sda_low),
        .halted_o(), .trap_valid_o(trap_valid), .trap_cause_o(), .trap_pc_o(),
        .qnn_busy_o(qnn_busy), .qnn_done_o(), .qnn_result_o()
    );

endmodule

`default_nettype wire
