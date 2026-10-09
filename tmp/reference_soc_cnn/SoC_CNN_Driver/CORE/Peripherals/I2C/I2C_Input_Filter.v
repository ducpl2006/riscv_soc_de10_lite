// ============================================================================
// Module I2C_Input_Filter
// ----------------------------------------------------------------------------
// Điều hoà 1 line ngõ vào I2C (SDA hoặc SCL) trước khi vào FSM (mục J của plan).
//
//   line (async) -> [SYNC_STAGES FF] (đồng bộ) -> [spike filter] -> line_clean
//
// 1. Synchronizer:
//    Chuỗi SYNC_STAGES flip-flop nối tiếp -> chống metastability khi lấy mẫu
//    tín hiệu bất đồng bộ từ chân I2C.
//
// 2. Digital spike filter (theo chuẩn Fast-mode: loại spike ≤ 50ns):
//    line_clean chỉ đổi khi mẫu đồng bộ giữ ỔN ĐỊNH liên tiếp SPIKE_LEN chu kỳ
//    clk. Glitch ngắn hơn SPIKE_LEN bị nuốt.
//    SPIKE_LEN = 0 -> bỏ qua filter, chỉ đồng bộ.
//
// Reset: active-low. Sau reset, các FF và line_clean khởi tạo = 1 (mức nghỉ
// của bus I2C là high nhờ pull-up) để tránh tạo START/STOP giả.
// ============================================================================
module I2C_Input_Filter #(

    parameter SYNC_STAGES = 2,
    parameter SPIKE_LEN   = 3
)
(
    input   clk,
    input   reset,          // active-low

    input   line_async,     // tín hiệu thô từ chân SDA/SCL
    output  line_clean      // tín hiệu đã đồng bộ + lọc glitch
);

    // ========================================================================
    // 1) SYNCHRONIZER — chuỗi SYNC_STAGES flip-flop
    // ========================================================================
    reg [SYNC_STAGES - 1:0] sync_ff;

    always @(posedge clk) begin
        if (!reset)
            sync_ff <= {SYNC_STAGES{1'b1}};             // idle = high
        else
            sync_ff <= {sync_ff[SYNC_STAGES - 2:0], line_async};
    end

    // Mẫu đã đồng bộ (tầng cuối)
    wire sampled = sync_ff[SYNC_STAGES - 1];

    // ========================================================================
    // 2) SPIKE FILTER
    // ========================================================================
    generate
        if (SPIKE_LEN == 0) begin : g_no_filter
            // Không lọc glitch: chỉ lấy tín hiệu đã đồng bộ
            assign line_clean = sampled;
        end
        else begin : g_filter

            // Đếm số chu kỳ mẫu đồng bộ khác với giá trị đang giữ.
            // Đủ SPIKE_LEN chu kỳ liên tiếp -> chấp nhận giá trị mới.
            reg                     filt;
            reg [15:0]              cnt;

            always @(posedge clk) begin
                if (!reset) begin
                    filt <= 1'b1;                       // idle = high
                    cnt  <= 16'd0;
                end
                else if (sampled == filt) begin
                    cnt  <= 16'd0;                      // ổn định -> reset đếm
                end
                else if (cnt == (SPIKE_LEN - 1)) begin
                    filt <= sampled;                    // đủ dài -> chấp nhận
                    cnt  <= 16'd0;
                end
                else begin
                    cnt  <= cnt + 16'd1;                // đang tích luỹ
                end
            end

            assign line_clean = filt;
        end
    endgenerate

endmodule
