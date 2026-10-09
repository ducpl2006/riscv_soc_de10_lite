// ============================================================================
// Module I2C_Timeout
// ----------------------------------------------------------------------------
// Monitor SCL kẹt low (mục A/E của plan). Đếm số chu kỳ clk khi scl_in=0; nếu
// đạt `timeout_val` -> phát 1 xung `timeout` (slave giữ SCL quá lâu / bus treo).
//
//   - SCL lên cao HOẶC timeout_val=0 (tắt) -> reset bộ đếm.
//   - `fired` chặn phát lặp lại khi SCL vẫn giữ low.
//   - timeout_val phải LỚN HƠN chu kỳ SCL-low bình thường (1 pha) để không
//     báo nhầm; firmware set đủ lớn.
//
// Reset: active-low.
// ============================================================================
module I2C_Timeout (
    input           clk,
    input           reset,          // active-low
    input           core_en,

    input           scl_in,         // đã lọc
    input  [23:0]   timeout_val,    // 0 = tắt

    output          timeout         // pulse
);

    reg [23:0]  cnt;
    reg         fired;
    reg         timeout_r;

    wire enabled = core_en && (timeout_val != 24'd0);

    always @(posedge clk) begin
        if (!reset) begin
            cnt       <= 24'd0;
            fired     <= 1'b0;
            timeout_r <= 1'b0;
        end
        else begin
            timeout_r <= 1'b0;

            if (!enabled || scl_in) begin
                // SCL cao hoặc tắt -> reset
                cnt   <= 24'd0;
                fired <= 1'b0;
            end
            else begin
                // SCL đang low
                if (!fired) begin
                    if (cnt >= (timeout_val - 24'd1)) begin
                        timeout_r <= 1'b1;
                        fired     <= 1'b1;
                    end
                    else
                        cnt <= cnt + 24'd1;
                end
            end
        end
    end

    assign timeout = timeout_r;

endmodule
