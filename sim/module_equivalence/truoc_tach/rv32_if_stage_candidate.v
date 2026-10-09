`default_nettype none
`include "rv32_defs.vh"

// =============================================================================
// Tầng IF: lấy lệnh qua kênh yêu cầu/đáp ứng độc lập, đệm IF/ID hai phần tử.
// - Nhận yêu cầu tại cạnh req && gnt; giữ req/addr tới cạnh đó, kể cả khi flush.
// - Mỗi yêu cầu đã nhận có đúng một đáp ứng theo thứ tự, sớm nhất ở cạnh kế tiếp.
//   Kênh đáp ứng không có cơ chế chặn; chỉ dùng rdata/err khi rvalid=1.
// - Tổng FIFO + yêu cầu đã nhận + yêu cầu đang giữ không vượt quá hai phần tử.
// - ID chỉ phát ifid_consumed_i khi được tiến. Flush ưu tiên hơn cập nhật FIFO.
// - Cờ kill đi cùng từng yêu cầu, chỉ xóa khi thay bằng yêu cầu mới; nhiều lần
//   flush liên tiếp không được làm sống lại yêu cầu đã hủy.
// Reset đồng bộ, tích cực cao; áp dụng đồng thời cho core và memory để hủy
// mọi đáp ứng chưa trả. Hợp đồng đầy đủ: docs/giao_tiep_rtl_vi.md.
// =============================================================================
module eq_candidate_rv32_if_stage #(
    // Địa chỉ byte khởi động; PC lệch hàng tạo ngoại lệ tại IF.
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
) (
    // Đồng hồ và reset đồng bộ, tích cực cao.
    input  wire         clk_i,
    input  wire         rst_i,

    // Điều khiển đã phân xử theo tuổi lệnh ở pipeline: halt/trap WB, lỗi MEM/EX,
    // đổi hướng EX, rồi ngoại lệ ID. halted_i giữ mức 1 đến reset.
    input  wire         halted_i,
    input  wire         wb_trap_event_i,
    input  wire         mem_fault_event_i,
    input  wire         ex_fault_event_i,
    input  wire         ex_redirect_event_i,
    input  wire         id_exception_event_i,
    // Đích nhánh/jump từ EX; JALR đã xóa bit 0.
    input  wire [31:0]  ex_control_target_i,

    // ID xác nhận lấy đầu FIFO tại cạnh lên; phải chặn khi stall hoặc bị hủy.
    input  wire         ifid_consumed_i,

    // Kênh bộ nhớ lệnh: gnt nhận yêu cầu; rvalid báo đáp ứng, không có rready.
    // rdata chỉ dùng khi rvalid && !err; err đúng đường tạo lỗi truy cập lệnh.
    input  wire         imem_gnt_i,
    input  wire         imem_rvalid_i,
    input  wire [31:0]  imem_rdata_i,
    input  wire         imem_err_i,
    // Giữ yêu cầu và địa chỉ byte căn 4 ổn định trong khi req && !gnt.
    output wire         imem_req_o,
    output wire [31:0]  imem_addr_o,

    // PC cho yêu cầu mới, khác PC đang giữ chờ grant hoặc PC hoàn tất lệnh.
    output wire [31:0]  debug_fetch_pc_o,

    // Đầu FIFO sang ID: PC, mã lệnh và ngoại lệ chỉ có nghĩa khi valid=1.
    // cause chỉ có nghĩa khi exc_valid=1; ngoại lệ chặn tác dụng phụ của lệnh.
    output wire         ifid_valid_o,
    output wire [31:0]  ifid_pc_o,
    output wire [31:0]  ifid_instr_o,
    output wire         ifid_exc_valid_o,
    output wire [4:0]   ifid_exc_cause_o
);
    localparam [4:0] CAUSE_INSTR_ADDR_MISALIGNED =
        `RV32_CAUSE_INSTR_ADDR_MISALIGNED;
    localparam [4:0] CAUSE_INSTR_ACCESS_FAULT =
        `RV32_CAUSE_INSTR_ACCESS_FAULT;

    // Trạng thái phát lệnh: dừng khi gặp lỗi/halt, cho phép chạy lại khi đổi hướng.
    // fetch_pc_q tăng 4 khi yêu cầu đúng đường được nhận, hoặc nạp đích mới.
    reg         front_stop_q;
    reg  [31:0] fetch_pc_q;

    // Yêu cầu đã phát nhưng chưa được nhận: giữ PC qua cả đổi hướng.
    // Nếu kill=1, vẫn hoàn tất bắt tay rồi loại đáp ứng.
    reg         req_hold_valid_q;
    reg  [31:0] req_hold_pc_q;
    reg         req_hold_kill_q;

    // Hàng đợi yêu cầu đã nhận, còn chờ đáp ứng (0..2 phần tử).
    // Phần tử 0 lâu nhất; mỗi PC đi cùng cờ kill, giữ qua các lần đổi hướng.
    reg  [1:0]  req_count_q;
    reg  [31:0] req_pc0_q;
    reg  [31:0] req_pc1_q;
    reg         req_kill0_q;
    reg         req_kill1_q;

    // FIFO IF/ID (0..2 phần tử): phần tử 0 là đầu ra, phần tử 1 là đuôi.
    // Mỗi phần tử gồm PC, mã lệnh, cờ ngoại lệ và cause; lỗi fetch có mã lệnh 0.
    reg  [1:0]  fifo_count_q;
    reg  [31:0] fifo_pc0_q;
    reg  [31:0] fifo_pc1_q;
    reg  [31:0] fifo_instr0_q;
    reg  [31:0] fifo_instr1_q;
    reg         fifo_exc0_q;
    reg         fifo_exc1_q;
    reg  [4:0]  fifo_cause0_q;
    reg  [4:0]  fifo_cause1_q;

    // Phân biệt xóa đường lệnh cũ với dừng phát: đổi hướng chỉ gây flush.
    wire        external_flush_event;
    wire        stop_event;

    // Chỗ đệm đã dùng gồm FIFO, yêu cầu chờ đáp ứng và yêu cầu đang giữ.
    // ID lấy đầu FIFO có thể giải phóng một chỗ ngay trong cùng chu kỳ.
    wire        fifo_pop;
    wire [2:0]  frontend_used;
    wire        issue_has_credit;

    // Phát yêu cầu mới hoặc tiếp tục yêu cầu đang giữ; ghi nhớ PC và cờ hủy.
    wire        new_request_valid;
    wire        request_accept;
    wire        request_capture_hold;
    wire [31:0] request_pc;
    wire        request_kill;
    wire        request_live;

    // Lấy thông tin đầu hàng đợi cho mọi đáp ứng; chỉ đáp ứng đúng đường vào FIFO.
    wire        response_pop;
    wire        response_live;
    wire        response_push;

    // Lỗi PC cục bộ tạo phần tử ngoại lệ mà không phát yêu cầu bộ nhớ.
    // Dữ liệu đẩy vào FIFO lấy từ đáp ứng hoặc từ lỗi PC cục bộ.
    wire        local_misaligned_push;
    wire        fifo_push;
    wire [31:0] push_pc;
    wire [31:0] push_instr;
    wire        push_exc;
    wire [4:0]  push_cause;
    // Đáp ứng đúng đường báo lỗi: dừng phát yêu cầu trẻ hơn.
    wire        fetch_exception_event;

    // -------------------------------------------------------------------------
    // Điều khiển flush/dừng và đầu ra IF/ID
    // -------------------------------------------------------------------------
    assign external_flush_event     = wb_trap_event_i || halted_i ||
                                      mem_fault_event_i || ex_fault_event_i ||
                                      ex_redirect_event_i ||
                                      id_exception_event_i;
    assign stop_event               = wb_trap_event_i || halted_i ||
                                      mem_fault_event_i || ex_fault_event_i ||
                                      id_exception_event_i;

    assign ifid_valid_o             = (fifo_count_q != 2'd0);
    assign ifid_pc_o                = fifo_pc0_q;
    assign ifid_instr_o             = fifo_instr0_q;
    assign ifid_exc_valid_o         = fifo_exc0_q;
    assign ifid_exc_cause_o         = fifo_cause0_q;

    // -------------------------------------------------------------------------
    // Tính chỗ còn trống và bắt tay yêu cầu bộ nhớ
    // -------------------------------------------------------------------------
    assign fifo_pop                 = ifid_consumed_i && ifid_valid_o;
    assign frontend_used            = {1'b0, fifo_count_q} +
                                      {1'b0, req_count_q} +
                                      {2'b0, req_hold_valid_q};
    assign issue_has_credit         = (frontend_used < 3'd2) || fifo_pop;

    assign new_request_valid        = !halted_i && !front_stop_q &&
                                      !external_flush_event && issue_has_credit &&
                                      (fetch_pc_q[1:0] == 2'b00);
    // Flush chỉ chặn yêu cầu mới; yêu cầu đang giữ vẫn phải hoàn tất bắt tay.
    assign imem_req_o               = !rst_i && (req_hold_valid_q || new_request_valid);
    assign imem_addr_o              = req_hold_valid_q ? req_hold_pc_q : fetch_pc_q;
    assign request_accept           = imem_req_o && imem_gnt_i;
    assign request_capture_hold     = !rst_i && !req_hold_valid_q &&
                                      new_request_valid && !imem_gnt_i;
    assign request_pc               = req_hold_valid_q ? req_hold_pc_q : fetch_pc_q;
    assign request_kill             = req_hold_valid_q && req_hold_kill_q;
    assign request_live             = !request_kill &&
                                      !external_flush_event;

    // -------------------------------------------------------------------------
    // Nhận đáp ứng và tạo phần tử FIFO
    // -------------------------------------------------------------------------
    // Luôn lấy thông tin đầu hàng đợi, kể cả đáp ứng bị hủy, để trả lại chỗ đệm.
    assign response_pop             = imem_rvalid_i && (req_count_q != 2'd0);
    assign response_live            = response_pop &&
                                      !req_kill0_q &&
                                      !external_flush_event && !front_stop_q;
    assign response_push            = response_live;
    assign fetch_exception_event    = response_push && imem_err_i;

    // Vector reset lệch hàng tạo ngoại lệ tại IF; đích nhánh được kiểm tra ở EX.
    assign local_misaligned_push    = !rst_i && !halted_i &&
                                      !front_stop_q &&
                                      !external_flush_event &&
                                      (req_count_q == 2'd0) &&
                                      !req_hold_valid_q &&
                                      issue_has_credit &&
                                      (fetch_pc_q[1:0] != 2'b00);
    assign fifo_push                = response_push || local_misaligned_push;
    assign push_pc                  = response_push ? req_pc0_q : fetch_pc_q;
    assign push_instr               = (response_push && !imem_err_i)
                                      ? imem_rdata_i : 32'b0;
    assign push_exc                 = local_misaligned_push || imem_err_i;
    assign push_cause               = local_misaligned_push
                                      ? CAUSE_INSTR_ADDR_MISALIGNED
                                      : CAUSE_INSTR_ACCESS_FAULT;

    assign debug_fetch_pc_o         = fetch_pc_q;

    // -------------------------------------------------------------------------
    // Cập nhật trạng thái tại cạnh lên
    // -------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            front_stop_q     <= 1'b0;
            fetch_pc_q       <= RESET_VECTOR;
            req_hold_valid_q <= 1'b0;
            req_hold_pc_q    <= 32'b0;
            req_hold_kill_q  <= 1'b0;
            req_count_q      <= 2'd0;
            req_pc0_q        <= 32'b0;
            req_pc1_q        <= 32'b0;
            req_kill0_q      <= 1'b0;
            req_kill1_q      <= 1'b0;
            fifo_count_q     <= 2'd0;
            fifo_pc0_q       <= 32'b0;
            fifo_pc1_q       <= 32'b0;
            fifo_instr0_q    <= 32'b0;
            fifo_instr1_q    <= 32'b0;
            fifo_exc0_q      <= 1'b0;
            fifo_exc1_q      <= 1'b0;
            fifo_cause0_q    <= 5'b0;
            fifo_cause1_q    <= 5'b0;
        end
        else begin
            // Đổi hướng ưu tiên hơn tăng PC sau bắt tay.
            if (ex_redirect_event_i)
                fetch_pc_q       <= ex_control_target_i;
            else if (request_accept && request_live)
                fetch_pc_q       <= request_pc + 32'd4;

            // Giải phóng yêu cầu đã nhận, hoặc chốt yêu cầu mới chưa được nhận.
            if (request_accept)
                req_hold_valid_q <= 1'b0;
            else if (request_capture_hold) begin
                req_hold_valid_q <= 1'b1;
                req_hold_pc_q    <= fetch_pc_q;
                req_hold_kill_q  <= 1'b0;
            end

            // Dừng do lỗi ưu tiên hơn cho phép phát lại sau đổi hướng.
            if (stop_event || fetch_exception_event ||
                local_misaligned_push)
                front_stop_q     <= 1'b1;
            else if (ex_redirect_event_i)
                front_stop_q     <= 1'b0;

            // Hàng đợi yêu cầu: thêm khi nhận, bỏ đầu khi có đáp ứng.
            // Khi cả hai cùng xảy ra, giữ số lượng và thay/chuyển thông tin theo thứ tự.
            case ({request_accept, response_pop})
                2'b10: begin
                    if (req_count_q == 2'd0) begin
                        req_pc0_q        <= request_pc;
                        req_kill0_q      <= request_kill;
                    end
                    else begin
                        req_pc1_q        <= request_pc;
                        req_kill1_q      <= request_kill;
                    end
                    req_count_q      <= req_count_q + 2'd1;
                end
                2'b01: begin
                    if (req_count_q == 2'd2) begin
                        req_pc0_q        <= req_pc1_q;
                        req_kill0_q      <= req_kill1_q;
                    end
                    req_count_q      <= req_count_q - 2'd1;
                end
                2'b11: begin
                    if (req_count_q == 2'd1) begin
                        req_pc0_q        <= request_pc;
                        req_kill0_q      <= request_kill;
                    end
                    else begin
                        req_pc0_q        <= req_pc1_q;
                        req_kill0_q      <= req_kill1_q;
                        req_pc1_q        <= request_pc;
                        req_kill1_q      <= request_kill;
                    end
                end
                default: begin end
            endcase

            // Hủy được ghi sau cập nhật hàng đợi nên thắng các phép gán ở trên.
            // Cả yêu cầu vừa được nhận hoặc vừa chuyển sang giữ trong chu kỳ lỗi
            // đều bị hủy; giữ thông tin yêu cầu khi vẫn còn đáp ứng chưa trả.
            if (external_flush_event || fetch_exception_event ||
                local_misaligned_push) begin
                req_hold_kill_q  <= 1'b1;
                req_kill0_q      <= 1'b1;
                req_kill1_q      <= 1'b1;
            end

            // Flush xóa FIFO, ưu tiên hơn thêm/lấy phần tử; thông tin yêu cầu vẫn
            // được giữ để nhận và loại bỏ đáp ứng cũ.
            if (external_flush_event) begin
                fifo_count_q     <= 2'd0;
            end
            else begin
                // Thêm và lấy đồng thời: số lượng giữ nguyên; thay đầu nếu chỉ có
                // một phần tử, còn khi có hai phần tử thì dồn đuôi lên rồi thêm mới.
                case ({fifo_push, fifo_pop})
                    2'b10: begin
                        if (fifo_count_q == 2'd0) begin
                            fifo_pc0_q       <= push_pc;
                            fifo_instr0_q    <= push_instr;
                            fifo_exc0_q      <= push_exc;
                            fifo_cause0_q    <= push_cause;
                        end
                        else begin
                            fifo_pc1_q       <= push_pc;
                            fifo_instr1_q    <= push_instr;
                            fifo_exc1_q      <= push_exc;
                            fifo_cause1_q    <= push_cause;
                        end
                        fifo_count_q     <= fifo_count_q + 2'd1;
                    end
                    2'b01: begin
                        if (fifo_count_q == 2'd2) begin
                            fifo_pc0_q       <= fifo_pc1_q;
                            fifo_instr0_q    <= fifo_instr1_q;
                            fifo_exc0_q      <= fifo_exc1_q;
                            fifo_cause0_q    <= fifo_cause1_q;
                        end
                        fifo_count_q     <= fifo_count_q - 2'd1;
                    end
                    2'b11: begin
                        if (fifo_count_q == 2'd1) begin
                            fifo_pc0_q       <= push_pc;
                            fifo_instr0_q    <= push_instr;
                            fifo_exc0_q      <= push_exc;
                            fifo_cause0_q    <= push_cause;
                        end
                        else begin
                            fifo_pc0_q       <= fifo_pc1_q;
                            fifo_instr0_q    <= fifo_instr1_q;
                            fifo_exc0_q      <= fifo_exc1_q;
                            fifo_cause0_q    <= fifo_cause1_q;
                            fifo_pc1_q       <= push_pc;
                            fifo_instr1_q    <= push_instr;
                            fifo_exc1_q      <= push_exc;
                            fifo_cause1_q    <= push_cause;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
