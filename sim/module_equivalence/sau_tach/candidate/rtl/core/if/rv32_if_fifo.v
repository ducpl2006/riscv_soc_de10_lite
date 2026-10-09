`default_nettype none

// =============================================================================
// FIFO IF/ID hai phần tử: giữ PC, mã lệnh và ngoại lệ cho tầng ID.
// - Phần tử 0 là đầu ra; phần tử 1 là đuôi. Đầu ra không thêm tầng thanh ghi.
// - Flush ưu tiên hơn thêm/lấy, chỉ xóa số lượng; dữ liệu cũ không còn hợp lệ.
// - Thêm/lấy đồng thời giữ số lượng và bảo toàn thứ tự của các phần tử.
// Tầng IF chịu trách nhiệm cấp chỗ trống và chỉ lấy khi valid_o=1.
// Reset đồng bộ, tích cực cao; dữ liệu/cause chỉ có nghĩa khi valid tương ứng.
// =============================================================================
module rv32_if_fifo (
    input  wire         clk_i,
    input  wire         rst_i,
    input  wire         flush_i,

    // Phần tử mới lấy từ đáp ứng bộ nhớ hoặc ngoại lệ PC lệch hàng tại IF.
    input  wire         push_i,
    input  wire [31:0]  push_pc_i,
    input  wire [31:0]  push_instr_i,
    input  wire         push_exc_i,
    input  wire [4:0]   push_cause_i,
    input  wire         pop_i,

    // Số lượng dùng để cấp chỗ trống; đầu FIFO được nối trực tiếp sang ID.
    output wire [1:0]   count_o,
    output wire         valid_o,
    output wire [31:0]  pc_o,
    output wire [31:0]  instr_o,
    output wire         exc_valid_o,
    output wire [4:0]   exc_cause_o
);
    reg  [1:0]  fifo_count_q;
    reg  [31:0] fifo_pc0_q;
    reg  [31:0] fifo_pc1_q;
    reg  [31:0] fifo_instr0_q;
    reg  [31:0] fifo_instr1_q;
    reg         fifo_exc0_q;
    reg         fifo_exc1_q;
    reg  [4:0]  fifo_cause0_q;
    reg  [4:0]  fifo_cause1_q;

    assign count_o     = fifo_count_q;
    assign valid_o     = (fifo_count_q != 2'd0);
    assign pc_o        = fifo_pc0_q;
    assign instr_o     = fifo_instr0_q;
    assign exc_valid_o = fifo_exc0_q;
    assign exc_cause_o = fifo_cause0_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            fifo_count_q  <= 2'd0;
            fifo_pc0_q    <= 32'b0;
            fifo_pc1_q    <= 32'b0;
            fifo_instr0_q <= 32'b0;
            fifo_instr1_q <= 32'b0;
            fifo_exc0_q   <= 1'b0;
            fifo_exc1_q   <= 1'b0;
            fifo_cause0_q <= 5'b0;
            fifo_cause1_q <= 5'b0;
        end
        else if (flush_i) begin
            fifo_count_q <= 2'd0;
        end
        else begin
            // Thêm/lấy đồng thời: thay đầu khi có một phần tử, hoặc dồn đuôi
            // lên rồi thêm mới khi có hai phần tử. Các trường luôn đi cùng nhau.
            case ({push_i, pop_i})
                2'b10: begin
                    if (fifo_count_q == 2'd0) begin
                        fifo_pc0_q    <= push_pc_i;
                        fifo_instr0_q <= push_instr_i;
                        fifo_exc0_q   <= push_exc_i;
                        fifo_cause0_q <= push_cause_i;
                    end
                    else begin
                        fifo_pc1_q    <= push_pc_i;
                        fifo_instr1_q <= push_instr_i;
                        fifo_exc1_q   <= push_exc_i;
                        fifo_cause1_q <= push_cause_i;
                    end
                    fifo_count_q <= fifo_count_q + 2'd1;
                end
                2'b01: begin
                    if (fifo_count_q == 2'd2) begin
                        fifo_pc0_q    <= fifo_pc1_q;
                        fifo_instr0_q <= fifo_instr1_q;
                        fifo_exc0_q   <= fifo_exc1_q;
                        fifo_cause0_q <= fifo_cause1_q;
                    end
                    fifo_count_q <= fifo_count_q - 2'd1;
                end
                2'b11: begin
                    if (fifo_count_q == 2'd1) begin
                        fifo_pc0_q    <= push_pc_i;
                        fifo_instr0_q <= push_instr_i;
                        fifo_exc0_q   <= push_exc_i;
                        fifo_cause0_q <= push_cause_i;
                    end
                    else begin
                        fifo_pc0_q    <= fifo_pc1_q;
                        fifo_instr0_q <= fifo_instr1_q;
                        fifo_exc0_q   <= fifo_exc1_q;
                        fifo_cause0_q <= fifo_cause1_q;
                        fifo_pc1_q    <= push_pc_i;
                        fifo_instr1_q <= push_instr_i;
                        fifo_exc1_q   <= push_exc_i;
                        fifo_cause1_q <= push_cause_i;
                    end
                end
                default: begin end
            endcase
        end
    end

endmodule

`default_nettype wire
