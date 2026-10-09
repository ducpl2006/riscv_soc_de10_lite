`default_nettype none

// =============================================================================
// Module      : qnn_soc_accelerator
// Chức năng   : Gia tốc suy luận mạng nơ-ron lượng tử 80-16-8-1.
// Purpose: giữ datapath QNN, bảo toàn giao dịch MMIO khi bận.
// Clock: clk_i cạnh lên. Reset: rst_i synchronous active-high, không reset model.
// Inputs: native bus offset 12 bit. Outputs: response, busy/done/result.
// Protocol: write chỉ commit tại req && ready && !err với lane0 được chọn.
// Latency: zero wait trừ feature write/START khi busy; các ghi đó chờ hết suy luận.
// Error behavior: offset sai/lệch word/ghi RO trả ready+err, reset chặn handshake.
//
// Kiến trúc số học
//   - Đầu vào, trọng số và activation ẩn là số nguyên có dấu 8 bit.
//   - Bias và bộ tích lũy là số nguyên có dấu 32 bit.
//   - Một chu kỳ fetch ROM và một chu kỳ MAC cho mỗi trọng số; tổng cộng 1416
//     phép nhân cho một mẫu. Nhịp tách này bảo đảm trọng số suy luận vào M9K.
//   - Hai lớp ẩn dùng ReLU, dịch phải số học rồi bão hòa về [0, 127].
//   - Đầu ra tuyến tính được dịch phải và chặn về [0, 1000], đơn vị 0,1 %SOC.
//
// Giao tiếp thanh ghi (địa chỉ byte cục bộ)
//   0x000 CONTROL : ghi bit 0=1 để start; ghi bit 1=1 để xóa cờ done.
//   0x004 STATUS  : bit 0 busy, bit 1 done, bit 2 model_loaded.
//   0x008 RESULT  : kết quả 0..1000 (0,1 %SOC/LSB).
//   0x00C CYCLES  : số chu kỳ của lần suy luận gần nhất/đang chạy.
//   0x010 CONFIG  : {8'd80, 8'd16, 8'd8, 8'd1}.
//   0x100..0x23C : 80 feature, mỗi feature ở byte thấp của một word.
//
// Tích hợp model
//   - Các file hex chứa từng byte trọng số dạng bù hai; bias là word 32 bit.
//   - Đặt USE_INIT_FILES=1 khi tổng hợp thiết kế thật. Testbench có thể đặt bằng
//     hierarchical access để tạo vector vàng nhỏ, độc lập với model huấn luyện.
//   - Thứ tự flatten: weight_l1[neuron*80 + feature], tương tự cho lớp 2.
// =============================================================================
module qnn_soc_accelerator #(
    // Khác 0: nạp model từ file; ROM trọng số backend Quartus dùng tên file trực tiếp.
    parameter integer USE_INIT_FILES = 0,
    // Số bit dịch phải số học sau MAC lớp 1, trước ReLU/bão hòa INT8.
    parameter integer L1_SHIFT = 0,
    // Số bit dịch phải số học sau MAC lớp 2, trước ReLU/bão hòa INT8.
    parameter integer L2_SHIFT = 0,
    // Số bit dịch phải số học đầu ra trước khi chặn về 0..1000.
    parameter integer OUT_SHIFT = 0,
    // File trọng số INT8 lớp 1, thứ tự neuron*80 + feature.
    parameter         L1_WEIGHT_FILE = "",
    // File HEX bias INT32 cho 16 neuron lớp 1.
    parameter         L1_BIAS_FILE   = "",
    // File trọng số INT8 lớp 2, thứ tự neuron*16 + đầu vào.
    parameter         L2_WEIGHT_FILE = "",
    // File HEX bias INT32 cho 8 neuron lớp 2.
    parameter         L2_BIAS_FILE   = "",
    // File HEX 8 trọng số INT8 của neuron đầu ra.
    parameter         OUT_WEIGHT_FILE = "",
    // File HEX một bias INT32 của neuron đầu ra.
    parameter         OUT_BIAS_FILE   = ""
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset trạng thái suy luận tại cạnh lên; không xóa feature/model, bus_ready vẫn theo req.
    input  wire        rst_i,

    // Yêu cầu MMIO từ decoder; lớp SoC khóa request trong reset.
    input  wire        bus_req_i,
    // 1: ghi thanh ghi/feature, 0: đọc; xét khi bus_req=1.
    input  wire        bus_we_i,
    // Offset byte 12 bit trong page QNN; feature ở 0x100..0x23C, bước 4 byte.
    input  wire [11:0] bus_addr_i,
    // Dữ liệu ghi; CONTROL và mỗi feature chỉ sử dụng byte thấp.
    input  wire [31:0] bus_wdata_i,
    // Byte-enable; bit 0 cho phép cập nhật CONTROL hoặc feature INT8.
    input  wire [3:0]  bus_wstrb_i,
    // Dữ liệu MMIO; feature INT8 được mở rộng dấu lên 32 bit khi đọc.
    output reg  [31:0] bus_rdata_o,
    // Bằng bus_req: MMIO hoàn tất ngay, không chờ suy luận kết thúc.
    output wire        bus_ready_o,
    // Địa chỉ/quyền truy cập MMIO không hợp lệ; khác với trạng thái busy.
    output reg         bus_err_o,

    // 1: đang suy luận; START/ghi feature lane0 chờ hết busy rồi mới handshake.
    output wire        busy_o,
    // Cờ hoàn tất giữ đến start mới, clear-done hoặc reset.
    output wire        done_o,
    // Kết quả gần nhất 0..1000, đơn vị 0,1 %SOC; cập nhật khi suy luận xong.
    output wire [31:0] result_o
);

    // Kích thước mạng cố định: 20 mẫu x 4 feature -> 16 -> 8 -> 1 output.
    localparam integer INPUT_COUNT = 80;
    localparam integer L1_COUNT    = 16;
    localparam integer L2_COUNT    = 8;

    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_L1_FETCH  = 4'd1,
        ST_L1_MAC    = 4'd2,
        ST_L1_STORE  = 4'd3,
        ST_L2_FETCH  = 4'd4,
        ST_L2_MAC    = 4'd5,
        ST_L2_STORE  = 4'd6,
        ST_OUT_MAC   = 4'd7,
        ST_OUT_DONE  = 4'd8;

    // 80 feature INT8 có dấu; mỗi phần tử chiếm byte thấp của một word MMIO.
    (* ramstyle = "logic" *) reg signed [7:0] feature_mem [0:INPUT_COUNT-1];
    // 16 đầu ra lớp 1 sau dịch phải, ReLU và bão hòa 0..127.
    (* ramstyle = "logic" *) reg signed [7:0] l1_activation [0:L1_COUNT-1];
    // 8 đầu ra lớp 2 sau dịch phải, ReLU và bão hòa 0..127.
    (* ramstyle = "logic" *) reg signed [7:0] l2_activation [0:L2_COUNT-1];

    // 16 bias INT32 có dấu, giá trị khởi đầu accumulator từng neuron lớp 1.
    (* romstyle = "logic" *) reg signed [31:0] l1_biases  [0:L1_COUNT-1];
    // 8 bias INT32 có dấu, giá trị khởi đầu accumulator từng neuron lớp 2.
    (* romstyle = "logic" *) reg signed [31:0] l2_biases  [0:L2_COUNT-1];
    // 8 trọng số INT8 có dấu nối lớp 2 tới đầu ra.
    (* romstyle = "logic" *) reg signed [7:0]  out_weights [0:L2_COUNT-1];
    // Một bias INT32 có dấu của neuron đầu ra.
    (* romstyle = "logic" *) reg signed [31:0] out_biases  [0:0];

    // FSM lần lượt fetch trọng số, MAC, lưu activation và hoàn tất output.
    reg [3:0] state_q;
    // Chỉ số đầu vào đang MAC: 0..79 ở L1, 0..15 ở L2, 0..7 ở output.
    reg [6:0] input_index_q;
    // Chỉ số neuron đang tính: 0..15 ở L1 hoặc 0..7 ở L2.
    reg [4:0] neuron_index_q;
    // Tổng bias và các tích INT8*INT8, tích lũy có dấu 32 bit.
    reg signed [31:0] accumulator_q;
    // Đang chạy suy luận; dùng khóa start/ghi feature trong thời gian tính.
    reg busy_q;
    // Cờ suy luận hoàn tất, giữ đến khi phần mềm xóa hoặc khởi động lần mới.
    reg done_q;
    // Kết quả đã chặn về 0..1000; giữ kết quả cũ trong lần suy luận tiếp theo.
    reg [31:0] result_q;
    // Số chu kỳ suy luận đang chạy/gần nhất; xóa khi nhận start.
    reg [31:0] cycle_count_q;

    // Chỉ số tuyến tính neuron*80 + input trước khi thu gọn độ rộng địa chỉ.
    wire [11:0] l1_weight_addr_full = neuron_index_q * 7'd80 + input_index_q;
    // Chỉ số tuyến tính neuron*16 + input trước khi thu gọn độ rộng địa chỉ.
    wire [8:0]  l2_weight_addr_full = neuron_index_q * 5'd16 + input_index_q;
    // Địa chỉ phần tử ROM L1 (0..1279 trong pha L1), không phải địa chỉ byte CPU.
    wire [10:0] l1_weight_addr = l1_weight_addr_full[10:0];
    // Địa chỉ phần tử ROM L2 (0..127 trong pha L2), không phải địa chỉ byte CPU.
    wire [6:0]  l2_weight_addr = l2_weight_addr_full[6:0];
    // 8 bit trọng số trả từ ROM L1 sau cạnh fetch.
    wire [7:0]  l1_weight_raw;
    // 8 bit trọng số trả từ ROM L2 sau cạnh fetch.
    wire [7:0]  l2_weight_raw;
    // Diễn giải trọng số L1 là số có dấu; đây là wire, không thêm thanh ghi.
    wire signed [7:0] l1_weight_q = l1_weight_raw;
    // Diễn giải trọng số L2 là số có dấu; đây là wire, không thêm thanh ghi.
    wire signed [7:0] l2_weight_q = l2_weight_raw;

    // Chỉ số vòng lặp khởi tạo feature, activation và model mặc định.
    integer init_index;

    function signed [7:0] relu_saturate_int8;
        // Giá trị INT32 có dấu đưa vào hàm bão hòa/chặn kết quả.
        input signed [31:0] value;
        // Biến tạm có dấu dùng so sánh giới hạn; hàm output áp dụng OUT_SHIFT trước.
        reg signed [31:0] shifted;
        begin
            shifted = value;
            if (shifted <= 0)
                relu_saturate_int8 = 8'sd0;
            else if (shifted > 127)
                relu_saturate_int8 = 8'sd127;
            else
                relu_saturate_int8 = shifted[7:0];
        end
    endfunction

    function [31:0] clamp_soc_result;
        // Giá trị INT32 có dấu đưa vào hàm bão hòa/chặn kết quả.
        input signed [31:0] value;
        // Biến tạm có dấu dùng so sánh giới hạn; hàm output áp dụng OUT_SHIFT trước.
        reg signed [31:0] shifted;
        begin
            shifted = value >>> OUT_SHIFT;
            if (shifted < 0)
                clamp_soc_result = 32'd0;
            else if (shifted > 1000)
                clamp_soc_result = 32'd1000;
            else
                clamp_soc_result = shifted[31:0];
        end
    endfunction

    initial begin
        for (init_index = 0; init_index < INPUT_COUNT; init_index = init_index + 1)
            feature_mem[init_index] = 8'sd0;
        for (init_index = 0; init_index < L1_COUNT; init_index = init_index + 1) begin
            l1_biases[init_index] = 32'sd0;
            l1_activation[init_index] = 8'sd0;
        end
        for (init_index = 0; init_index < L2_COUNT; init_index = init_index + 1) begin
            l2_biases[init_index] = 32'sd0;
            l2_activation[init_index] = 8'sd0;
            out_weights[init_index] = 8'sd0;
        end
        out_biases[0] = 32'sd0;

        if (USE_INIT_FILES != 0) begin
            $readmemh(L1_BIAS_FILE, l1_biases);
            $readmemh(L2_BIAS_FILE, l2_biases);
            $readmemh(OUT_WEIGHT_FILE, out_weights);
            $readmemh(OUT_BIAS_FILE, out_biases);
        end
    end

    intel_sync_rom_1p #(
        .WIDTH(8), .WORDS(INPUT_COUNT*L1_COUNT), .ADDR_WIDTH(11),
        .USE_INIT_FILE(USE_INIT_FILES), .INIT_FILE(L1_WEIGHT_FILE)
    ) u_l1_weight_rom (
        .clk_i(clk_i), .en_i(state_q == ST_L1_FETCH),
        .addr_i(l1_weight_addr), .q_o(l1_weight_raw)
    );

    intel_sync_rom_1p #(
        .WIDTH(8), .WORDS(L1_COUNT*L2_COUNT), .ADDR_WIDTH(7),
        .USE_INIT_FILE(USE_INIT_FILES), .INIT_FILE(L2_WEIGHT_FILE)
    ) u_l2_weight_rom (
        .clk_i(clk_i), .en_i(state_q == ST_L2_FETCH),
        .addr_i(l2_weight_addr), .q_o(l2_weight_raw)
    );

    // Protocol: hoàn tất tại req && ready. Feature lane0 hoặc START khi busy
    // phải chờ; đọc, clear-done và no-op strobe không chờ. Reset chặn handshake.
    // Latency: 0 wait khi rảnh, đến hết suy luận nếu write cần snapshot mới.
    // Error behavior: offset sai/lệch word và ghi RO hoàn tất với err, không ghi.
    wire feature_addr = (bus_addr_i >= 12'h100) && (bus_addr_i <= 12'h23C) &&
                        (bus_addr_i[1:0] == 2'b00);
    wire write_needs_idle = bus_we_i && bus_wstrb_i[0] &&
                            (feature_addr || (bus_addr_i == 0 && bus_wdata_i[0]));
    assign bus_ready_o = bus_req_i && !rst_i && !(busy_q && write_needs_idle);
    assign busy_o      = busy_q;
    assign done_o      = done_q;
    assign result_o    = result_q;

    always @* begin
        bus_rdata_o = 32'd0;
        bus_err_o   = 1'b0;

        case (bus_addr_i)
            12'h000: bus_rdata_o = 32'd0;
            12'h004: bus_rdata_o = {29'd0, USE_INIT_FILES != 0, done_q, busy_q};
            12'h008: bus_rdata_o = result_q;
            12'h00C: bus_rdata_o = cycle_count_q;
            12'h010: bus_rdata_o = {8'd80, 8'd16, 8'd8, 8'd1};
            default: begin
                if ((bus_addr_i >= 12'h100) && (bus_addr_i <= 12'h23C) &&
                    (bus_addr_i[1:0] == 2'b00)) begin
                    bus_rdata_o = {{24{feature_mem[(bus_addr_i - 12'h100) >> 2][7]}},
                                   feature_mem[(bus_addr_i - 12'h100) >> 2]};
                end
                else begin
                    bus_err_o = bus_req_i;
                end
            end
        endcase

        if (bus_req_i && bus_we_i) begin
            if ((bus_addr_i == 12'h000) ||
                ((bus_addr_i >= 12'h100) && (bus_addr_i <= 12'h23C) &&
                 (bus_addr_i[1:0] == 2'b00))) begin
                bus_err_o = 1'b0;
            end
            else begin
                bus_err_o = 1'b1;
            end
        end
        if (rst_i || !bus_req_i)
            bus_err_o = 1'b0;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q         <= ST_IDLE;
            input_index_q   <= 7'd0;
            neuron_index_q  <= 5'd0;
            accumulator_q   <= 32'sd0;
            busy_q          <= 1'b0;
            done_q          <= 1'b0;
            result_q        <= 32'd0;
            cycle_count_q   <= 32'd0;
        end
        else begin
            if (bus_req_i && bus_ready_o && bus_we_i && !bus_err_o && bus_wstrb_i[0]) begin
                if (bus_addr_i == 12'h000) begin
                    if (bus_wdata_i[1])
                        done_q <= 1'b0;
                    if (bus_wdata_i[0] && !busy_q) begin
                        state_q        <= ST_L1_FETCH;
                        input_index_q  <= 7'd0;
                        neuron_index_q <= 5'd0;
                        accumulator_q  <= l1_biases[0];
                        busy_q         <= 1'b1;
                        done_q         <= 1'b0;
                        cycle_count_q  <= 32'd0;
                    end
                end
                else if (!busy_q && (bus_addr_i >= 12'h100) &&
                         (bus_addr_i <= 12'h23C)) begin
                    feature_mem[(bus_addr_i - 12'h100) >> 2] <= bus_wdata_i[7:0];
                end
            end

            if (busy_q)
                cycle_count_q <= cycle_count_q + 32'd1;

            case (state_q)
                ST_IDLE: begin
                    // Chờ lệnh start từ CPU.
                end

                ST_L1_FETCH: begin
                    state_q <= ST_L1_MAC;
                end

                ST_L1_MAC: begin
                    accumulator_q <= accumulator_q +
                        $signed(feature_mem[input_index_q]) *
                        $signed(l1_weight_q);
                    if (input_index_q == INPUT_COUNT-1) begin
                        input_index_q <= 7'd0;
                        state_q       <= ST_L1_STORE;
                    end
                    else begin
                        input_index_q <= input_index_q + 7'd1;
                        state_q       <= ST_L1_FETCH;
                    end
                end

                ST_L1_STORE: begin
                    l1_activation[neuron_index_q] <=
                        relu_saturate_int8(accumulator_q >>> L1_SHIFT);
                    if (neuron_index_q == L1_COUNT-1) begin
                        neuron_index_q <= 5'd0;
                        input_index_q  <= 7'd0;
                        accumulator_q  <= l2_biases[0];
                        state_q        <= ST_L2_FETCH;
                    end
                    else begin
                        neuron_index_q <= neuron_index_q + 5'd1;
                        input_index_q  <= 7'd0;
                        accumulator_q  <= l1_biases[neuron_index_q + 5'd1];
                        state_q        <= ST_L1_FETCH;
                    end
                end

                ST_L2_FETCH: begin
                    state_q <= ST_L2_MAC;
                end

                ST_L2_MAC: begin
                    accumulator_q <= accumulator_q +
                        $signed(l1_activation[input_index_q]) *
                        $signed(l2_weight_q);
                    if (input_index_q == L1_COUNT-1) begin
                        input_index_q <= 7'd0;
                        state_q       <= ST_L2_STORE;
                    end
                    else begin
                        input_index_q <= input_index_q + 7'd1;
                        state_q       <= ST_L2_FETCH;
                    end
                end

                ST_L2_STORE: begin
                    l2_activation[neuron_index_q] <=
                        relu_saturate_int8(accumulator_q >>> L2_SHIFT);
                    if (neuron_index_q == L2_COUNT-1) begin
                        neuron_index_q <= 5'd0;
                        input_index_q  <= 7'd0;
                        accumulator_q  <= out_biases[0];
                        state_q        <= ST_OUT_MAC;
                    end
                    else begin
                        neuron_index_q <= neuron_index_q + 5'd1;
                        input_index_q  <= 7'd0;
                        accumulator_q  <= l2_biases[neuron_index_q + 5'd1];
                        state_q        <= ST_L2_FETCH;
                    end
                end

                ST_OUT_MAC: begin
                    accumulator_q <= accumulator_q +
                        $signed(l2_activation[input_index_q]) *
                        $signed(out_weights[input_index_q]);
                    if (input_index_q == L2_COUNT-1) begin
                        input_index_q <= 7'd0;
                        state_q       <= ST_OUT_DONE;
                    end
                    else begin
                        input_index_q <= input_index_q + 7'd1;
                    end
                end

                ST_OUT_DONE: begin
                    result_q <= clamp_soc_result(accumulator_q);
                    busy_q   <= 1'b0;
                    done_q   <= 1'b1;
                    state_q  <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_IDLE;
                    busy_q  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
