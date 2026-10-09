`default_nettype none

// =============================================================================
// Hàng đợi hai yêu cầu lấy lệnh đã được bộ nhớ nhận, còn chờ đáp ứng theo thứ tự.
// - Phần tử đầu giữ PC và cờ hủy của đáp ứng kế tiếp, kể cả đáp ứng sai đường.
// - Thêm/lấy đồng thời giữ số lượng; cờ hủy đi cùng PC khi dịch hàng đợi.
// - Hủy toàn bộ ưu tiên sau thêm/lấy, nên cả yêu cầu vừa nhận cũng bị hủy.
// Tầng IF chịu trách nhiệm cấp chỗ trống và chỉ lấy khi hàng đợi có phần tử.
// Reset đồng bộ, tích cực cao; không thêm chu kỳ vào đường yêu cầu/đáp ứng.
// =============================================================================
module rv32_if_request_queue (
    input  wire         clk_i,
    input  wire         rst_i,

    // Thêm khi bộ nhớ nhận yêu cầu; lấy khi đáp ứng đầu hàng đợi trở về.
    input  wire         request_accept_i,
    input  wire         response_pop_i,
    input  wire [31:0]  request_pc_i,
    input  wire         request_kill_i,
    // Đánh dấu hủy, giữ nguyên số lượng để tiếp tục nhận và loại đáp ứng cũ.
    input  wire         kill_all_i,

    // Thông tin đầu chỉ có nghĩa khi count_o khác 0.
    output wire [1:0]   count_o,
    output wire [31:0]  head_pc_o,
    output wire         head_kill_o
);
    reg  [1:0]  req_count_q;
    reg  [31:0] req_pc0_q;
    reg  [31:0] req_pc1_q;
    reg         req_kill0_q;
    reg         req_kill1_q;

    assign count_o     = req_count_q;
    assign head_pc_o   = req_pc0_q;
    assign head_kill_o = req_kill0_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            req_count_q <= 2'd0;
            req_pc0_q   <= 32'b0;
            req_pc1_q   <= 32'b0;
            req_kill0_q <= 1'b0;
            req_kill1_q <= 1'b0;
        end
        else begin
            // Khi thêm/lấy đồng thời, thay đầu nếu có một phần tử; nếu có hai
            // phần tử, dồn đuôi lên đầu rồi ghi yêu cầu mới vào đuôi.
            case ({request_accept_i, response_pop_i})
                2'b10: begin
                    if (req_count_q == 2'd0) begin
                        req_pc0_q   <= request_pc_i;
                        req_kill0_q <= request_kill_i;
                    end
                    else begin
                        req_pc1_q   <= request_pc_i;
                        req_kill1_q <= request_kill_i;
                    end
                    req_count_q <= req_count_q + 2'd1;
                end
                2'b01: begin
                    if (req_count_q == 2'd2) begin
                        req_pc0_q   <= req_pc1_q;
                        req_kill0_q <= req_kill1_q;
                    end
                    req_count_q <= req_count_q - 2'd1;
                end
                2'b11: begin
                    if (req_count_q == 2'd1) begin
                        req_pc0_q   <= request_pc_i;
                        req_kill0_q <= request_kill_i;
                    end
                    else begin
                        req_pc0_q   <= req_pc1_q;
                        req_kill0_q <= req_kill1_q;
                        req_pc1_q   <= request_pc_i;
                        req_kill1_q <= request_kill_i;
                    end
                end
                default: begin end
            endcase

            // Gán sau các cập nhật phía trên để hủy thắng thêm/lấy trong cùng
            // chu kỳ; nhiều lần hủy không làm sống lại yêu cầu đã bị hủy.
            if (kill_all_i) begin
                req_kill0_q <= 1'b1;
                req_kill1_q <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
