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

    // Đầu hàng đợi yêu cầu đã nhận, còn chờ đáp ứng (0..2 phần tử).
    // Trạng thái nằm trong u_request_queue; giữ tên tín hiệu để dễ đọc dạng sóng.
    wire [1:0]  req_count_q;
    wire [31:0] req_pc0_q;
    wire        req_kill0_q;

    // Số phần tử FIFO IF/ID, dùng chung với hàng đợi để tính chỗ trống.
    // PC, mã lệnh và ngoại lệ từ u_ifid_fifo đi thẳng đến các cổng IF/ID.
    wire [1:0]  fifo_count_q;

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
    // Cùng một điều kiện hủy cho yêu cầu đang giữ và mọi yêu cầu đã nhận.
    wire        kill_requests_event;

    // -------------------------------------------------------------------------
    // Điều khiển flush/dừng
    // -------------------------------------------------------------------------
    assign external_flush_event     = wb_trap_event_i || halted_i ||
                                      mem_fault_event_i || ex_fault_event_i ||
                                      ex_redirect_event_i ||
                                      id_exception_event_i;
    assign stop_event               = wb_trap_event_i || halted_i ||
                                      mem_fault_event_i || ex_fault_event_i ||
                                      id_exception_event_i;

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
    assign kill_requests_event      = external_flush_event ||
                                      fetch_exception_event ||
                                      local_misaligned_push;

    // -------------------------------------------------------------------------
    // Hai khối lưu trữ độc lập; không thêm tầng thanh ghi hoặc chu kỳ chờ
    // -------------------------------------------------------------------------
    // Mỗi yêu cầu đã nhận giữ PC/cờ hủy đến khi đáp ứng trở về. Hủy được áp dụng
    // sau thêm/lấy bên trong hàng đợi, nên cả yêu cầu vừa được nhận cũng bị hủy.
    rv32_if_request_queue u_request_queue (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .request_accept_i (request_accept),
        .response_pop_i   (response_pop),
        .request_pc_i     (request_pc),
        .request_kill_i   (request_kill),
        .kill_all_i       (kill_requests_event),
        .count_o          (req_count_q),
        .head_pc_o        (req_pc0_q),
        .head_kill_o      (req_kill0_q)
    );

    // Flush chỉ xóa số lượng FIFO; vẫn giữ payload như trước, kể cả khi invalid.
    // Thông tin yêu cầu ở hàng đợi trên còn nguyên để loại bỏ các đáp ứng cũ.
    rv32_if_fifo u_ifid_fifo (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .flush_i          (external_flush_event),
        .push_i           (fifo_push),
        .push_pc_i        (push_pc),
        .push_instr_i     (push_instr),
        .push_exc_i       (push_exc),
        .push_cause_i     (push_cause),
        .pop_i            (fifo_pop),
        .count_o          (fifo_count_q),
        .valid_o          (ifid_valid_o),
        .pc_o             (ifid_pc_o),
        .instr_o          (ifid_instr_o),
        .exc_valid_o      (ifid_exc_valid_o),
        .exc_cause_o      (ifid_exc_cause_o)
    );

    // -------------------------------------------------------------------------
    // Cập nhật PC, trạng thái dừng và yêu cầu đang giữ tại cạnh lên
    // -------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            front_stop_q     <= 1'b0;
            fetch_pc_q       <= RESET_VECTOR;
            req_hold_valid_q <= 1'b0;
            req_hold_pc_q    <= 32'b0;
            req_hold_kill_q  <= 1'b0;
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

            // Hủy ưu tiên hơn chốt yêu cầu đang giữ ở trên, kể cả yêu cầu vừa
            // chuyển sang giữ trong chu kỳ lỗi. Hàng đợi dùng cùng điều kiện này.
            if (kill_requests_event)
                req_hold_kill_q  <= 1'b1;
        end
    end

endmodule

`default_nettype wire
