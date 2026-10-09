`default_nettype none

`include "rv32_defs.vh"

// =============================================================================
// Module      : rv32_core
// Chức năng   : Core RV32I pipeline 5 tầng, in-order, single-issue.
// Pipeline    : IF -> ID -> EX -> MEM -> WB.
// ISA         : RV32I v2.1; không gồm C, M, A, Zicsr hay Zifencei.
//
// Giao tiếp bộ nhớ
//   - Instruction request được nhận tại req && gnt; response có rvalid riêng,
//     trả đúng thứ tự, sớm nhất ở cạnh kế tiếp. Không có rready.
//   - rdata/err instruction chỉ được lấy mẫu khi rvalid=1.
//   - Data bus giữ req và payload tới cạnh req && ready; tối đa một giao dịch.
//   - imem_addr_o là địa chỉ byte, luôn căn 4 khi phát request.
//   - dmem_addr_o là địa chỉ word đã căn; wstrb chọn byte lane little-endian.
//   - Pipeline dừng phía trước MEM khi data bus có wait-state. Instruction bus
//     dành trước chỗ trong FIFO hai phần tử cho mọi yêu cầu đã phát.
//   - Tổng FIFO, yêu cầu chờ đáp ứng và yêu cầu chờ grant không vượt hai.
//
// Hazard và control flow
//   - Forward EX/MEM -> EX và MEM/WB -> EX; EX/MEM có ưu tiên cao hơn.
//   - Load-use chèn một bubble. Nếu load bị wait-state, các tầng trước giữ lại.
//   - Branch/JAL/JALR được giải quyết tại EX; lệnh trẻ hơn bị flush khi redirect.
//   - Register file có bypass WB -> ID cho phụ thuộc cùng chu kỳ ghi.
//
// Ngoại lệ và retirement
//   - Hỗ trợ instruction/data access fault, địa chỉ lệch hàng, illegal,
//     EBREAK và ECALL. Ngoại lệ đi theo pipeline tới WB để giữ tính precise.
//   - Ngoại lệ đến WB chốt trap_valid_o và dừng core tới reset; không retire.
//   - FENCE là NOP hợp lệ: core in-order, không cache, chỉ có một data request.
//   - retire_* tạo giao tiếp trace một chu kỳ cho mỗi lệnh hoàn tất thành công.
//
// Reset
//   - rst_i tích cực mức cao, đồng bộ. PC fetch về RESET_VECTOR; pipeline rỗng.
//   - Core và memory phải reset đồng thời để hủy mọi đáp ứng cũ.
//   - Ngoài reset, yêu cầu lấy lệnh giữ tới grant, yêu cầu dữ liệu giữ tới ready.
//
// Cách đọc tên tín hiệu:
//   - _i/_o: hướng vào/ra tính tại module đang khai báo; _q: giá trị đã chốt.
//   - idex/exmem/memwb: ranh giới ID/EX, EX/MEM, MEM/WB chứa lệnh đang xử lý.
//   - ifid_*_q và halted_q là wire nối trạng thái chốt trong module con.
//   - Payload từng ranh giới chỉ có nghĩa khi valid tương ứng bằng 1;
//     exc_valid đánh dấu lệnh lỗi, không phải lệnh được phép gây tác dụng phụ.
// Đặc tả      : docs/giao_tiep_rtl_vi.md; hướng dẫn đọc: docs/doc_hieu_core_vi.md.
// =============================================================================
module rv32_core #(
    // PC khởi động (địa chỉ byte); nên căn 4, lệch hàng sẽ tạo trap tại IF.
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
) (
    // Nhịp hệ thống và reset đồng bộ, tích cực cao.
    input  wire        clk_i,
    input  wire        rst_i,

    // Lấy lệnh tách pha: req/gnt nhận yêu cầu; rvalid trả lệnh/err.
    // Giữ req và addr đến grant; dữ liệu/err chỉ có nghĩa khi rvalid=1.
    output wire        imem_req_o,
    output wire [31:0] imem_addr_o,
    input  wire        imem_gnt_i,
    input  wire        imem_rvalid_i,
    input  wire [31:0] imem_rdata_i,
    input  wire        imem_err_i,

    // Load/store: giữ req, we, addr, wdata, wstrb đến req && ready.
    // addr căn 4 byte; wstrb[n] chọn byte [8*n +: 8], little-endian.
    // rdata chỉ dùng khi đọc thành công; err chỉ xét tại hoàn tất.
    output wire        dmem_req_o,
    output wire        dmem_we_o,
    output wire [31:0] dmem_addr_o,
    output wire [31:0] dmem_wdata_o,
    output wire [3:0]  dmem_wstrb_o,
    input  wire [31:0] dmem_rdata_i,
    input  wire        dmem_ready_i,
    input  wire        dmem_err_i,

    // Trạng thái trap chốt tại WB và giữ đến reset.
    // cause/pc/instr có nghĩa khi trap_valid; instr=0 nếu lỗi fetch.
    output wire        halted_o,
    output wire        trap_valid_o,
    output wire [4:0]  trap_cause_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_instr_o,

    // Vết lệnh hoàn tất: mỗi cạnh retire_valid=1 ứng với một lệnh.
    // Thông tin rd chỉ có nghĩa khi retire_valid && retire_rd_we.
    output wire        retire_valid_o,
    output wire [31:0] retire_pc_o,
    output wire [31:0] retire_instr_o,
    output wire        retire_rd_we_o,
    output wire [4:0]  retire_rd_addr_o,
    output wire [31:0] retire_rd_data_o,

    // PC để tạo yêu cầu mới; khác PC retire và địa chỉ đang chờ grant.
    output wire [31:0] debug_fetch_pc_o
);

    localparam [1:0] OP_A_RS1 = `RV32_OP_A_RS1;
    localparam [1:0] WB_ALU = `RV32_WB_ALU;
    localparam [4:0] CAUSE_LOAD_ACCESS_FAULT = `RV32_CAUSE_LOAD_ACCESS_FAULT;
    localparam [4:0] CAUSE_STORE_ACCESS_FAULT = `RV32_CAUSE_STORE_ACCESS_FAULT;

    // =========================================================================
    // 1. Trạng thái pipeline do core giữ
    // =========================================================================
    // ID/EX: lệnh đang ở EX. valid=0 là ô rỗng; các trường còn lại bị bỏ qua.
    wire         valid_ex;
    wire  [31:0] pc_ex;
    wire  [31:0] instr_ex;
    wire  [31:0] pc4_ex;             // PC + 4, địa chỉ trở về của JAL/JALR

    // Toán hạng từ ID; giữ chỉ số rs1/rs2 để chọn dữ liệu chuyển tiếp tại EX.
    wire  [4:0]  rs1_addr_ex;
    wire  [4:0]  rs2_addr_ex;
    wire  [4:0]  rd_addr_ex;
    wire  [31:0] rs1_data_ex;
    wire  [31:0] rs2_data_ex;
    wire  [31:0] imm_ex;             // Mở rộng dấu I/S/B/J; U có 12 bit thấp bằng 0

    // Điều khiển thực thi; các mã ALU/nguồn toán hạng/ghi về ở rv32_defs.vh.
    wire  [2:0]  funct3_ex;          // Điều kiện nhánh hoặc cỡ/kiểu load-store
    wire  [3:0]  alu_op_ex;
    wire  [1:0]  op_a_sel_ex;
    wire         op_b_imm_ex;        // 1: dùng immediate; 0: dùng rs2
    wire         reg_write_ex;       // Ý định ghi rd; chưa phải tín hiệu commit
    wire  [1:0]  wb_sel_ex;
    wire         branch_ex;
    wire         jal_ex;
    wire         jalr_ex;
    wire         load_ex;
    wire         store_ex;

    // Ngoại lệ đi cùng lệnh; chặn ghi rd, nhánh và load/store thông thường.
    wire         exc_valid_ex;
    wire  [4:0]  exc_cause_ex;

    // EX/MEM: lệnh đang ở MEM. Giữ cả nhóm khi mem_stall=1.
    wire         valid_mem;
    wire  [31:0] pc_mem;
    wire  [31:0] instr_mem;
    wire  [31:0] pc4_mem;
    wire  [4:0]  rd_addr_mem;
    wire         reg_write_mem;
    wire  [1:0]  wb_sel_mem;

    // Kết quả EX và dữ liệu store sau chuyển tiếp; load chưa có dữ liệu đọc.
    wire  [31:0] alu_result_mem;     // Với load/store: địa chỉ byte hiệu dụng
    wire  [31:0] store_data_mem;     // Giá trị rs2 đã chuyển tiếp, chưa xếp byte lane
    wire  [2:0]  funct3_mem;
    wire         load_mem;
    wire         store_mem;

    // Ngoại lệ từ ID/EX được mang tiếp tới WB.
    wire         exc_valid_mem;
    wire  [4:0]  exc_cause_mem;

    // MEM/WB: lệnh đang ở WB; kết quả đã được chọn tại MEM.
    wire         valid_wb;
    wire  [31:0] pc_wb;
    wire  [31:0] instr_wb;
    wire  [4:0]  rd_addr_wb;
    wire         reg_write_wb;
    wire  [31:0] wb_data_wb;

    // Lệnh có ngoại lệ sẽ chốt trap, không ghi thanh ghi và không retire.
    wire         exc_valid_wb;
    wire  [4:0]  exc_cause_wb;

    // =========================================================================
    // 2. Đường dữ liệu tổ hợp và trạng thái từ các module tầng
    // =========================================================================
    // IF -> ID: bí danh của đầu FIFO trong u_if_stage; đây không phải reg tại core.
    wire         valid_id;
    wire [31:0]  pc_id;
    wire [31:0]  instr_id;
    wire         exc_valid_id;
    wire [4:0]   exc_cause_id;

    // ID -> ID/EX: giải mã, đọc thanh ghi có đường tắt WB -> ID, tạo immediate.
    wire [4:0]   id_rs1_addr;
    wire [4:0]   id_rs2_addr;
    wire [4:0]   id_rd_addr;
    wire [2:0]   id_funct3;
    wire [31:0]  id_rs1_data;
    wire [31:0]  id_rs2_data;
    wire [31:0]  id_imm;
    wire [3:0]   id_alu_op;
    wire [1:0]   id_op_a_sel;
    wire         id_op_b_imm;
    wire         id_reg_write;
    wire [1:0]   id_wb_sel;
    wire         id_branch;
    wire         id_jal;
    wire         id_jalr;
    wire         id_load;
    wire         id_store;

    // ID -> điều khiển: chỉ kiểm tra phụ thuộc của nguồn mà lệnh thực sự đọc.
    wire         id_uses_rs1;
    wire         id_uses_rs2;

    // Ngoại lệ ID: lỗi fetch có ưu tiên hơn illegal/EBREAK/ECALL khi chọn cause.
    wire         id_decode_exc;
    wire         id_any_exc;            // Gộp lỗi fetch và lỗi giải mã
    wire [4:0]   id_any_exc_cause;

    // EX -> EX/MEM: chọn toán hạng, thực thi ALU/nhánh và kiểm tra căn hàng.
    wire [31:0]  ex_rs1_value;
    wire [31:0]  ex_rs2_value;
    wire [31:0]  ex_alu_result;
    wire [31:0]  ex_control_target;     // JALR đã xóa bit 0
    wire         ex_control_taken;      // Nhánh được lấy hoặc JAL/JALR; chưa phân xử
    wire         ex_target_misaligned;  // Đích nhảy được lấy nhưng không căn 4 byte

    // Lỗi EX đã xét valid/ngoại lệ; điều khiển còn phải xét lệnh già hơn tại MEM.
    wire         ex_fault_raw;
    wire [4:0]   ex_fault_cause;        // Cause 0/4/6 khi ex_fault_raw=1

    // MEM -> điều khiển/WB: chờ giao dịch, lỗi lúc hoàn tất và kết quả ghi về.
    wire         mem_stall;             // Giữ phía trước MEM; WB cũ vẫn hoàn tất một lần
    wire         mem_fault_raw;         // Lỗi dữ liệu chỉ tại req && ready
    wire [31:0]  mem_wb_data;

    // WB -> ID/điều khiển: cho phép ghi rd, sự kiện trap và trạng thái dừng.
    wire         wb_regfile_we;         // Đã chặn reset, halt, ngoại lệ và rd=x0
    wire         wb_trap_event;
    wire         halted_q;              // Trạng thái chốt tại u_wb_stage

    // =========================================================================
    // 3. Điều khiển chung giữa các tầng
    // =========================================================================
    // Chọn chuyển tiếp: 00=ID/EX, 01=MEM/WB, 10=EX/MEM; EX/MEM ưu tiên hơn.
    // Không lấy địa chỉ của load tại EX/MEM làm dữ liệu chuyển tiếp.
    wire [1:0]   forward_rs1_sel;
    wire [1:0]   forward_rs2_sel;

    // Sự kiện sau phân xử; lệnh già hơn tại MEM/EX được xử lý trước ID.
    wire         mem_fault_event;
    wire         ex_fault_event;
    wire         ex_redirect_event;
    wire         id_exception_event;

    // Load-use: giữ đầu FIFO IF/ID và chèn ô rỗng vào ID/EX.
    wire         load_use_stall;
    wire         ifid_consumed;         // ID lấy đầu FIFO tại cạnh lên; không phải grant bộ nhớ

    assign halted_o = halted_q;

    // =========================================================================
    // 4. Kết nối theo luồng IF -> ID -> EX -> MEM -> WB, rồi điều khiển
    // =========================================================================

    // IF: quản lý yêu cầu, FIFO lệnh và nhận/bỏ đáp ứng sai đường.
    rv32_if_stage #(.RESET_VECTOR(RESET_VECTOR)) u_if_stage (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .halted_i             (halted_q),
        .wb_trap_event_i      (wb_trap_event),
        .mem_fault_event_i    (mem_fault_event),
        .ex_fault_event_i     (ex_fault_event),
        .ex_redirect_event_i  (ex_redirect_event),
        .id_exception_event_i (id_exception_event),
        .ex_control_target_i  (ex_control_target),
        .consumed_id_i      (ifid_consumed),
        .imem_gnt_i           (imem_gnt_i),
        .imem_rvalid_i        (imem_rvalid_i),
        .imem_rdata_i         (imem_rdata_i),
        .imem_err_i           (imem_err_i),
        .imem_req_o           (imem_req_o),
        .imem_addr_o          (imem_addr_o),
        .debug_fetch_pc_o     (debug_fetch_pc_o),
        .valid_id_o         (valid_id),
        .pc_id_o            (pc_id),
        .instr_id_o         (instr_id),
        .exc_valid_id_o     (exc_valid_id),
        .exc_cause_id_o     (exc_cause_id)
    );

    // ID: giải mã RV32I, tạo immediate, đọc thanh ghi và bypass từ WB.
    rv32_id_stage u_id_stage (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .instr_i         (instr_id),
        .exc_valid_i     (exc_valid_id),
        .exc_cause_i     (exc_cause_id),
        .wb_regfile_we_i (wb_regfile_we),
        .memwb_rd_addr_i (rd_addr_wb),
        .memwb_wb_data_i (wb_data_wb),
        .rs1_addr_o      (id_rs1_addr),
        .rs2_addr_o      (id_rs2_addr),
        .rd_addr_o       (id_rd_addr),
        .funct3_o        (id_funct3),
        .rs1_data_o      (id_rs1_data),
        .rs2_data_o      (id_rs2_data),
        .imm_o           (id_imm),
        .alu_op_o        (id_alu_op),
        .op_a_sel_o      (id_op_a_sel),
        .op_b_imm_o      (id_op_b_imm),
        .reg_write_o     (id_reg_write),
        .wb_sel_o        (id_wb_sel),
        .branch_o        (id_branch),
        .jal_o           (id_jal),
        .jalr_o          (id_jalr),
        .load_o          (id_load),
        .store_o         (id_store),
        .uses_rs1_o      (id_uses_rs1),
        .uses_rs2_o      (id_uses_rs2),
        .decode_exc_o    (id_decode_exc),
        .any_exc_o       (id_any_exc),
        .any_exc_cause_o (id_any_exc_cause)
    );

    // EX: forwarding toán hạng, ALU/nhánh và phát hiện địa chỉ lệch hàng.
    rv32_ex_stage u_ex_stage (
        .valid_i             (valid_ex),
        .exc_valid_i         (exc_valid_ex),
        .rs1_data_i          (rs1_data_ex),
        .rs2_data_i          (rs2_data_ex),
        .op_a_sel_i          (op_a_sel_ex),
        .op_b_imm_i          (op_b_imm_ex),
        .pc_i                (pc_ex),
        .imm_i               (imm_ex),
        .alu_op_i            (alu_op_ex),
        .branch_i            (branch_ex),
        .funct3_i            (funct3_ex),
        .jal_i               (jal_ex),
        .jalr_i              (jalr_ex),
        .load_i              (load_ex),
        .store_i             (store_ex),
        .exmem_wb_sel_i      (wb_sel_mem),
        .exmem_pc4_i         (pc4_mem),
        .exmem_alu_result_i  (alu_result_mem),
        .memwb_wb_data_i     (wb_data_wb),
        .forward_rs1_sel_i   (forward_rs1_sel),
        .forward_rs2_sel_i   (forward_rs2_sel),
        .rs1_value_o         (ex_rs1_value),
        .rs2_value_o         (ex_rs2_value),
        .alu_result_o        (ex_alu_result),
        .control_target_o    (ex_control_target),
        .control_taken_o     (ex_control_taken),
        .target_misaligned_o (ex_target_misaligned),
        .fault_raw_o         (ex_fault_raw),
        .fault_cause_o       (ex_fault_cause)
    );

    // MEM: giao dịch dữ liệu, chờ đáp ứng, phát hiện lỗi và chọn kết quả load.
    rv32_mem_stage u_mem_stage (
        .rst_i           (rst_i),
        .halted_i        (halted_q),
        .wb_trap_event_i (wb_trap_event),
        .valid_i         (valid_mem),
        .exc_valid_i     (exc_valid_mem),
        .load_i          (load_mem),
        .store_i         (store_mem),
        .alu_result_i    (alu_result_mem),
        .store_data_i    (store_data_mem),
        .funct3_i        (funct3_mem),
        .wb_sel_i        (wb_sel_mem),
        .pc4_i           (pc4_mem),
        .dmem_rdata_i    (dmem_rdata_i),
        .dmem_ready_i    (dmem_ready_i),
        .dmem_err_i      (dmem_err_i),
        .dmem_req_o      (dmem_req_o),
        .dmem_we_o       (dmem_we_o),
        .dmem_addr_o     (dmem_addr_o),
        .dmem_wdata_o    (dmem_wdata_o),
        .dmem_wstrb_o    (dmem_wstrb_o),
        .stall_o         (mem_stall),
        .fault_raw_o     (mem_fault_raw),
        .wb_data_o       (mem_wb_data)
    );

    // WB: ghi thanh ghi, trace lệnh hoàn tất và chốt ngoại lệ chính xác.
    rv32_wb_stage u_wb_stage (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .valid_i          (valid_wb),
        .exc_valid_i      (exc_valid_wb),
        .reg_write_i      (reg_write_wb),
        .rd_addr_i        (rd_addr_wb),
        .wb_data_i        (wb_data_wb),
        .pc_i             (pc_wb),
        .instr_i          (instr_wb),
        .exc_cause_i      (exc_cause_wb),
        .wb_regfile_we_o  (wb_regfile_we),
        .wb_trap_event_o  (wb_trap_event),
        .halted_o         (halted_q),
        .trap_valid_o     (trap_valid_o),
        .trap_cause_o     (trap_cause_o),
        .trap_pc_o        (trap_pc_o),
        .trap_instr_o     (trap_instr_o),
        .retire_valid_o   (retire_valid_o),
        .retire_pc_o      (retire_pc_o),
        .retire_instr_o   (retire_instr_o),
        .retire_rd_we_o   (retire_rd_we_o),
        .retire_rd_addr_o (retire_rd_addr_o),
        .retire_rd_data_o (retire_rd_data_o)
    );

    // Điều khiển: hazard/forwarding; sự kiện của lệnh già hơn có ưu tiên cao hơn.
    rv32_pipeline_control u_control (
        .id_rs1_addr_i          (id_rs1_addr),
        .id_rs2_addr_i          (id_rs2_addr),
        .id_uses_rs1_i          (id_uses_rs1),
        .id_uses_rs2_i          (id_uses_rs2),
        .valid_ex_i           (valid_ex),
        .exc_valid_ex_i       (exc_valid_ex),
        .load_ex_i            (load_ex),
        .rd_addr_ex_i         (rd_addr_ex),
        .rs1_addr_ex_i        (rs1_addr_ex),
        .rs2_addr_ex_i        (rs2_addr_ex),
        .valid_mem_i          (valid_mem),
        .exc_valid_mem_i      (exc_valid_mem),
        .reg_write_mem_i      (reg_write_mem),
        .load_mem_i           (load_mem),
        .rd_addr_mem_i        (rd_addr_mem),
        .valid_wb_i          (valid_wb),
        .exc_valid_wb_i      (exc_valid_wb),
        .reg_write_wb_i      (reg_write_wb),
        .rd_addr_wb_i        (rd_addr_wb),
        .mem_fault_raw_i        (mem_fault_raw),
        .mem_stall_i            (mem_stall),
        .ex_fault_raw_i         (ex_fault_raw),
        .ex_control_taken_i     (ex_control_taken),
        .ex_target_misaligned_i (ex_target_misaligned),
        .valid_id_i           (valid_id),
        .exc_valid_id_i       (exc_valid_id),
        .id_decode_exc_i        (id_decode_exc),
        .halted_i               (halted_q),
        .wb_trap_event_i        (wb_trap_event),
        .forward_rs1_sel_o      (forward_rs1_sel),
        .forward_rs2_sel_o      (forward_rs2_sel),
        .mem_fault_event_o      (mem_fault_event),
        .ex_fault_event_o       (ex_fault_event),
        .ex_redirect_event_o    (ex_redirect_event),
        .id_exception_event_o   (id_exception_event),
        .load_use_stall_o       (load_use_stall),
        .consumed_id_o        (ifid_consumed)
    );

    // =========================================================================
    // 5. Cập nhật pipeline tại cạnh lên (Instantiations)
    // =========================================================================
    rv32_idex_reg u_idex_reg (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .trap_flush_i     (wb_trap_event),
        .stage_flush_i    (mem_fault_event || ex_fault_event || ex_redirect_event),
        .mem_stall_i      (mem_stall),
        .load_use_stall_i (load_use_stall),
        .valid_id_i       (valid_id),
        .pc_id_i          (pc_id),
        .instr_id_i       (instr_id),
        .rs1_addr_id_i    (id_rs1_addr),
        .rs2_addr_id_i    (id_rs2_addr),
        .rd_addr_id_i     (id_rd_addr),
        .rs1_data_id_i    (id_rs1_data),
        .rs2_data_id_i    (id_rs2_data),
        .imm_id_i         (id_imm),
        .funct3_id_i      (id_funct3),
        .alu_op_id_i      (id_alu_op),
        .op_a_sel_id_i    (id_op_a_sel),
        .op_b_imm_id_i    (id_op_b_imm),
        .reg_write_id_i   (id_reg_write),
        .wb_sel_id_i      (id_wb_sel),
        .branch_id_i      (id_branch),
        .jal_id_i         (id_jal),
        .jalr_id_i        (id_jalr),
        .load_id_i        (id_load),
        .store_id_i       (id_store),
        .exc_valid_id_i   (exc_valid_id),
        .exc_cause_id_i   (exc_cause_id),
        .rs1_fwd_i        (ex_rs1_value),
        .rs2_fwd_i        (ex_rs2_value),
        .valid_ex_o       (valid_ex),
        .pc_ex_o          (pc_ex),
        .instr_ex_o       (instr_ex),
        .pc4_ex_o         (pc4_ex),
        .rs1_addr_ex_o    (rs1_addr_ex),
        .rs2_addr_ex_o    (rs2_addr_ex),
        .rd_addr_ex_o     (rd_addr_ex),
        .rs1_data_ex_o    (rs1_data_ex),
        .rs2_data_ex_o    (rs2_data_ex),
        .imm_ex_o         (imm_ex),
        .funct3_ex_o      (funct3_ex),
        .alu_op_ex_o      (alu_op_ex),
        .op_a_sel_ex_o    (op_a_sel_ex),
        .op_b_imm_ex_o    (op_b_imm_ex),
        .reg_write_ex_o   (reg_write_ex),
        .wb_sel_ex_o      (wb_sel_ex),
        .branch_ex_o      (branch_ex),
        .jal_ex_o         (jal_ex),
        .jalr_ex_o        (jalr_ex),
        .load_ex_o        (load_ex),
        .store_ex_o       (store_ex),
        .exc_valid_ex_o   (exc_valid_ex),
        .exc_cause_ex_o   (exc_cause_ex)
    );

    rv32_exmem_reg u_exmem_reg (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .trap_flush_i     (wb_trap_event),
        .stage_flush_i    (mem_fault_event),
        .mem_stall_i      (mem_stall),
        .valid_ex_i       (valid_ex),
        .pc_ex_i          (pc_ex),
        .instr_ex_i       (instr_ex),
        .pc4_ex_i         (pc4_ex),
        .rd_addr_ex_i     (rd_addr_ex),
        .reg_write_ex_i   (reg_write_ex),
        .wb_sel_ex_i      (wb_sel_ex),
        .alu_result_ex_i  (ex_alu_result),
        .store_data_ex_i  (ex_rs2_value),
        .funct3_ex_i      (funct3_ex),
        .load_ex_i        (load_ex),
        .store_ex_i       (store_ex),
        .exc_valid_ex_i   (exc_valid_ex),
        .exc_cause_ex_i   (exc_cause_ex),
        .ex_fault_raw_i   (ex_fault_raw),
        .ex_fault_cause_i (ex_fault_cause),
        .valid_mem_o      (valid_mem),
        .pc_mem_o         (pc_mem),
        .instr_mem_o      (instr_mem),
        .pc4_mem_o        (pc4_mem),
        .rd_addr_mem_o    (rd_addr_mem),
        .reg_write_mem_o  (reg_write_mem),
        .wb_sel_mem_o     (wb_sel_mem),
        .alu_result_mem_o (alu_result_mem),
        .store_data_mem_o (store_data_mem),
        .funct3_mem_o     (funct3_mem),
        .load_mem_o       (load_mem),
        .store_mem_o      (store_mem),
        .exc_valid_mem_o  (exc_valid_mem),
        .exc_cause_mem_o  (exc_cause_mem)
    );

    rv32_memwb_reg u_memwb_reg (
        .clk_i             (clk_i),
        .rst_i             (rst_i),
        .trap_flush_i      (wb_trap_event),
        .mem_stall_i       (mem_stall),
        .valid_mem_i       (valid_mem),
        .pc_mem_i          (pc_mem),
        .instr_mem_i       (instr_mem),
        .rd_addr_mem_i     (rd_addr_mem),
        .reg_write_mem_i   (reg_write_mem),
        .mem_wb_data_i     (mem_wb_data),
        .exc_valid_mem_i   (exc_valid_mem),
        .exc_cause_mem_i   (exc_cause_mem),
        .load_mem_i        (load_mem),
        .mem_fault_event_i (mem_fault_event),
        .valid_wb_o        (valid_wb),
        .pc_wb_o           (pc_wb),
        .instr_wb_o        (instr_wb),
        .rd_addr_wb_o      (rd_addr_wb),
        .reg_write_wb_o    (reg_write_wb),
        .wb_data_wb_o      (wb_data_wb),
        .exc_valid_wb_o    (exc_valid_wb),
        .exc_cause_wb_o    (exc_cause_wb)
    );

endmodule

`default_nettype wire
