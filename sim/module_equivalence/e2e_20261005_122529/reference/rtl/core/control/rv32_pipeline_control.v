`default_nettype none

// Điều khiển pipeline tổ hợp; lỗi/redirect của lệnh già hơn chặn sự kiện trẻ hơn.
// MEM chờ thì giữ EX/MEM và ID/EX; WB cũ vẫn được commit đúng một lần.
// ifid_consumed xác nhận lấy đầu FIFO tại cạnh lên; không phải tín hiệu ready
// của memory. Core áp dụng reset và trap WB với ưu tiên cao nhất.
// Chi tiết ưu tiên và điều kiện chuyển: docs/giao_tiep_rtl_vi.md, mục 5.
module eq_reference_rv32_pipeline_control (
    // Nguồn thực sự được lệnh ID sử dụng để kiểm tra phụ thuộc load-use.
    input  wire [4:0]   id_rs1_addr_i,
    input  wire [4:0]   id_rs2_addr_i,
    input  wire         id_uses_rs1_i,
    input  wire         id_uses_rs2_i,

    // Lệnh đang ở EX: trạng thái ngoại lệ, đích load và hai nguồn thực thi.
    input  wire         idex_valid_i,
    input  wire         idex_exc_valid_i,
    input  wire         idex_load_i,
    input  wire [4:0]   idex_rd_addr_i,
    input  wire [4:0]   idex_rs1_addr_i,
    input  wire [4:0]   idex_rs2_addr_i,

    // Lệnh đang ở MEM: nguồn forwarding sớm, loại load và lệnh có ngoại lệ.
    input  wire         exmem_valid_i,
    input  wire         exmem_exc_valid_i,
    input  wire         exmem_reg_write_i,
    input  wire         exmem_load_i,
    input  wire [4:0]   exmem_rd_addr_i,

    // Lệnh đang ở WB: nguồn forwarding sau khi kết quả đã sẵn sàng.
    input  wire         memwb_valid_i,
    input  wire         memwb_exc_valid_i,
    input  wire         memwb_reg_write_i,
    input  wire [4:0]   memwb_rd_addr_i,

    // Sự kiện MEM: lỗi chỉ xuất hiện tại req && ready; chờ MEM giữ các tầng trước.
    input  wire         mem_fault_raw_i,
    input  wire         mem_stall_i,

    // Sự kiện EX: lỗi căn chỉnh đã xét valid/ngoại lệ; nhánh còn cần phân xử
    // với MEM. Đích nhánh lệch hàng tạo lỗi, không tạo redirect.
    input  wire         ex_fault_raw_i,
    input  wire         ex_control_taken_i,
    input  wire         ex_target_misaligned_i,

    // Lệnh ID và lỗi giải mã mới; lỗi fetch đi kèm được chuyển tiếp riêng.
    input  wire         ifid_valid_i,
    input  wire         ifid_exc_valid_i,
    input  wire         id_decode_exc_i,

    // Dừng core hoặc chốt trap WB: ngăn ID lấy thêm lệnh từ FIFO.
    input  wire         halted_i,
    input  wire         wb_trap_event_i,

    // Chọn hai nguồn EX: 00=ID/EX, 01=MEM/WB, 10=EX/MEM; MEM ưu tiên WB.
    output wire [1:0]   forward_rs1_sel_o,
    output wire [1:0]   forward_rs2_sel_o,

    // Sự kiện sau phân xử: MEM chặn EX; lỗi/redirect EX chặn ngoại lệ ID
    // và stall load-use. Reset/trap WB được ưu tiên tại core.
    output wire         mem_fault_event_o,
    output wire         ex_fault_event_o,
    output wire         ex_redirect_event_o,
    output wire         id_exception_event_o,
    output wire         load_use_stall_o,

    // Lấy đầu FIFO IF/ID tại cạnh lên khi ID được tiến; không phải ready bus.
    output wire         ifid_consumed_o
);

    // Hazard load-use trước khi phân xử với stall MEM và flush do lỗi/redirect.
    wire load_use_stall_raw;

    // Loại lệnh có ngoại lệ khỏi mọi nguồn hazard/forwarding.
    eq_reference_rv32_hazard_unit u_hazard_unit (
        .id_rs1_addr_i    (id_rs1_addr_i),
        .id_rs2_addr_i    (id_rs2_addr_i),
        .id_uses_rs1_i    (id_uses_rs1_i),
        .id_uses_rs2_i    (id_uses_rs2_i),
        .ex_valid_i       (idex_valid_i && !idex_exc_valid_i),
        .ex_load_i        (idex_load_i),
        .ex_rd_addr_i     (idex_rd_addr_i),
        .ex_rs1_addr_i    (idex_rs1_addr_i),
        .ex_rs2_addr_i    (idex_rs2_addr_i),
        .mem_valid_i      (exmem_valid_i && !exmem_exc_valid_i),
        .mem_reg_write_i  (exmem_reg_write_i),
        .mem_load_i       (exmem_load_i),
        .mem_rd_addr_i    (exmem_rd_addr_i),
        .wb_valid_i       (memwb_valid_i && !memwb_exc_valid_i),
        .wb_reg_write_i   (memwb_reg_write_i),
        .wb_rd_addr_i     (memwb_rd_addr_i),
        .stall_load_use_o (load_use_stall_raw),
        .forward_rs1_o    (forward_rs1_sel_o),
        .forward_rs2_o    (forward_rs2_sel_o)
    );

    // MEM chứa lệnh già hơn EX: lỗi MEM thắng lỗi/redirect EX.
    // Khi MEM chờ, EX chưa được phát lỗi hoặc đổi luồng điều khiển.
    assign mem_fault_event_o = mem_fault_raw_i;
    assign ex_fault_event_o = ex_fault_raw_i && !mem_stall_i &&
                              !mem_fault_event_o;
    assign ex_redirect_event_o = idex_valid_i && !idex_exc_valid_i &&
                                 ex_control_taken_i && !ex_target_misaligned_i &&
                                 !mem_stall_i && !mem_fault_event_o;

    // Chỉ xét ID sau khi đã loại mọi sự kiện ưu tiên ở MEM/EX.
    assign id_exception_event_o = ifid_valid_i && !ifid_exc_valid_i &&
                                  id_decode_exc_i && !mem_stall_i &&
                                  !mem_fault_event_o && !ex_fault_event_o &&
                                  !ex_redirect_event_o;
    assign load_use_stall_o = load_use_stall_raw && !mem_stall_i &&
                              !mem_fault_event_o && !ex_fault_event_o &&
                              !ex_redirect_event_o;

    // Cho phép ID tiến khi không halt, trap, stall hoặc sự kiện MEM/EX ưu tiên.
    wire id_can_advance;

    assign id_can_advance = !halted_i && !wb_trap_event_i && !mem_stall_i &&
                            !mem_fault_event_o && !ex_fault_event_o &&
                            !ex_redirect_event_o && !load_use_stall_o;

    // Ngoại lệ mới tại ID vẫn tiêu thụ lệnh: metadata lỗi được chuyển sang EX.
    assign ifid_consumed_o = ifid_valid_i && id_can_advance;

endmodule

`default_nettype wire
