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
//   - Các dây *_q nối trạng thái chốt trong module tầng/thanh ghi con.
//   - Payload từng ranh giới chỉ có nghĩa khi valid tương ứng bằng 1;
//     exc_valid đánh dấu lệnh lỗi, không phải lệnh được phép gây tác dụng phụ.
// Đặc tả      : docs/giao_tiep_rtl_vi.md; hướng dẫn đọc: docs/doc_hieu_core_vi.md.
// =============================================================================
module eq_candidate_rv32_core #(
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

    // =========================================================================
    // 1. Trạng thái từ ba module thanh ghi pipeline
    // =========================================================================
    // ID/EX: lệnh đang ở EX. valid=0 là ô rỗng; các trường còn lại bị bỏ qua.
    wire        idex_valid_q;
    wire [31:0] idex_pc_q;
    wire [31:0] idex_instr_q;
    wire [31:0] idex_pc4_q;             // PC + 4, địa chỉ trở về của JAL/JALR

    // Toán hạng từ ID; giữ chỉ số rs1/rs2 để chọn dữ liệu chuyển tiếp tại EX.
    wire [4:0]  idex_rs1_addr_q;
    wire [4:0]  idex_rs2_addr_q;
    wire [4:0]  idex_rd_addr_q;
    wire [31:0] idex_rs1_data_q;
    wire [31:0] idex_rs2_data_q;
    wire [31:0] idex_imm_q;             // Mở rộng dấu I/S/B/J; U có 12 bit thấp bằng 0

    // Điều khiển thực thi; các mã ALU/nguồn toán hạng/ghi về ở rv32_defs.vh.
    wire [2:0]  idex_funct3_q;          // Điều kiện nhánh hoặc cỡ/kiểu load-store
    wire [3:0]  idex_alu_op_q;
    wire [1:0]  idex_op_a_sel_q;
    wire        idex_op_b_imm_q;        // 1: dùng immediate; 0: dùng rs2
    wire        idex_reg_write_q;       // Ý định ghi rd; chưa phải tín hiệu commit
    wire [1:0]  idex_wb_sel_q;
    wire        idex_branch_q;
    wire        idex_jal_q;
    wire        idex_jalr_q;
    wire        idex_load_q;
    wire        idex_store_q;

    // Ngoại lệ đi cùng lệnh; chặn ghi rd, nhánh và load/store thông thường.
    wire        idex_exc_valid_q;
    wire [4:0]  idex_exc_cause_q;

    // EX/MEM: lệnh đang ở MEM. Giữ cả nhóm khi mem_stall=1.
    wire        exmem_valid_q;
    wire [31:0] exmem_pc_q;
    wire [31:0] exmem_instr_q;
    wire [31:0] exmem_pc4_q;
    wire [4:0]  exmem_rd_addr_q;
    wire        exmem_reg_write_q;
    wire [1:0]  exmem_wb_sel_q;

    // Kết quả EX và dữ liệu store sau chuyển tiếp; load chưa có dữ liệu đọc.
    wire [31:0] exmem_alu_result_q;     // Với load/store: địa chỉ byte hiệu dụng
    wire [31:0] exmem_store_data_q;     // Giá trị rs2 đã chuyển tiếp, chưa xếp byte lane
    wire [2:0]  exmem_funct3_q;
    wire        exmem_load_q;
    wire        exmem_store_q;

    // Ngoại lệ từ ID/EX được mang tiếp tới WB.
    wire        exmem_exc_valid_q;
    wire [4:0]  exmem_exc_cause_q;

    // MEM/WB: lệnh đang ở WB; kết quả đã được chọn tại MEM.
    wire        memwb_valid_q;
    wire [31:0] memwb_pc_q;
    wire [31:0] memwb_instr_q;
    wire [4:0]  memwb_rd_addr_q;
    wire        memwb_reg_write_q;
    wire [31:0] memwb_wb_data_q;

    // Lệnh có ngoại lệ sẽ chốt trap, không ghi thanh ghi và không retire.
    wire        memwb_exc_valid_q;
    wire [4:0]  memwb_exc_cause_q;

    // =========================================================================
    // 2. Đường dữ liệu tổ hợp và trạng thái từ các module tầng
    // =========================================================================
    // IF -> ID: bí danh của đầu FIFO trong u_if_stage; đây không phải reg tại core.
    wire        ifid_valid_q;
    wire [31:0] ifid_pc_q;
    wire [31:0] ifid_instr_q;
    wire        ifid_exc_valid_q;
    wire [4:0]  ifid_exc_cause_q;

    // ID -> ID/EX: giải mã, đọc thanh ghi có đường tắt WB -> ID, tạo immediate.
    wire [4:0]  id_rs1_addr;
    wire [4:0]  id_rs2_addr;
    wire [4:0]  id_rd_addr;
    wire [2:0]  id_funct3;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [31:0] id_imm;
    wire [3:0]  id_alu_op;
    wire [1:0]  id_op_a_sel;
    wire        id_op_b_imm;
    wire        id_reg_write;
    wire [1:0]  id_wb_sel;
    wire        id_branch;
    wire        id_jal;
    wire        id_jalr;
    wire        id_load;
    wire        id_store;

    // ID -> điều khiển: chỉ kiểm tra phụ thuộc của nguồn mà lệnh thực sự đọc.
    wire        id_uses_rs1;
    wire        id_uses_rs2;

    // Ngoại lệ ID: lỗi fetch có ưu tiên hơn illegal/EBREAK/ECALL khi chọn cause.
    wire        id_decode_exc;
    wire        id_any_exc;            // Gộp lỗi fetch và lỗi giải mã
    wire [4:0]  id_any_exc_cause;

    // EX -> EX/MEM: chọn toán hạng, thực thi ALU/nhánh và kiểm tra căn hàng.
    wire [31:0] ex_rs1_value;
    wire [31:0] ex_rs2_value;
    wire [31:0] ex_alu_result;
    wire [31:0] ex_control_target;     // JALR đã xóa bit 0
    wire        ex_control_taken;      // Nhánh được lấy hoặc JAL/JALR; chưa phân xử
    wire        ex_target_misaligned;  // Đích nhảy được lấy nhưng không căn 4 byte

    // Lỗi EX đã xét valid/ngoại lệ; điều khiển còn phải xét lệnh già hơn tại MEM.
    wire        ex_fault_raw;
    wire [4:0]  ex_fault_cause;        // Cause 0/4/6 khi ex_fault_raw=1

    // MEM -> điều khiển/WB: chờ giao dịch, lỗi lúc hoàn tất và kết quả ghi về.
    wire        mem_stall;             // Giữ phía trước MEM; WB cũ vẫn hoàn tất một lần
    wire        mem_fault_raw;         // Lỗi dữ liệu chỉ tại req && ready
    wire [31:0] mem_wb_data;

    // WB -> ID/điều khiển: cho phép ghi rd, sự kiện trap và trạng thái dừng.
    wire        wb_regfile_we;         // Đã chặn reset, halt, ngoại lệ và rd=x0
    wire        wb_trap_event;
    wire        halted_q;              // Trạng thái chốt tại u_wb_stage

    // =========================================================================
    // 3. Điều khiển chung giữa các tầng
    // =========================================================================
    // Chọn chuyển tiếp: 00=ID/EX, 01=MEM/WB, 10=EX/MEM; EX/MEM ưu tiên hơn.
    // Không lấy địa chỉ của load tại EX/MEM làm dữ liệu chuyển tiếp.
    wire [1:0]  forward_rs1_sel;
    wire [1:0]  forward_rs2_sel;

    // Sự kiện sau phân xử; lệnh già hơn tại MEM/EX được xử lý trước ID.
    wire        mem_fault_event;
    wire        ex_fault_event;
    wire        ex_redirect_event;
    wire        id_exception_event;

    // Load-use: giữ đầu FIFO IF/ID và chèn ô rỗng vào ID/EX.
    wire        load_use_stall;
    wire        ifid_consumed;         // ID lấy đầu FIFO tại cạnh lên; không phải grant bộ nhớ

    assign halted_o = halted_q;

    // =========================================================================
    // 4. Kết nối tầng xử lý xen kẽ thanh ghi pipeline, rồi điều khiển
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
        .ifid_consumed_i      (ifid_consumed),
        .imem_gnt_i           (imem_gnt_i),
        .imem_rvalid_i        (imem_rvalid_i),
        .imem_rdata_i         (imem_rdata_i),
        .imem_err_i           (imem_err_i),
        .imem_req_o           (imem_req_o),
        .imem_addr_o          (imem_addr_o),
        .debug_fetch_pc_o     (debug_fetch_pc_o),
        .ifid_valid_o         (ifid_valid_q),
        .ifid_pc_o            (ifid_pc_q),
        .ifid_instr_o         (ifid_instr_q),
        .ifid_exc_valid_o     (ifid_exc_valid_q),
        .ifid_exc_cause_o     (ifid_exc_cause_q)
    );

    // ID: giải mã RV32I, tạo immediate, đọc thanh ghi và bypass từ WB.
    rv32_id_stage u_id_stage (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .instr_i         (ifid_instr_q),
        .exc_valid_i     (ifid_exc_valid_q),
        .exc_cause_i     (ifid_exc_cause_q),
        .wb_regfile_we_i (wb_regfile_we),
        .memwb_rd_addr_i (memwb_rd_addr_q),
        .memwb_wb_data_i (memwb_wb_data_q),
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

    // Thanh ghi ID/EX: giữ/hủy lệnh tại ranh giới, không thêm chu kỳ pipeline.
    rv32_id_ex_reg u_id_ex_reg (
        .clk_i               (clk_i),
        .rst_i               (rst_i),
        .wb_trap_event_i     (wb_trap_event),
        .halted_i            (halted_q),
        .mem_stall_i         (mem_stall),
        .mem_fault_event_i   (mem_fault_event),
        .ex_fault_event_i    (ex_fault_event),
        .ex_redirect_event_i (ex_redirect_event),
        .load_use_stall_i    (load_use_stall),
        .valid_i             (ifid_valid_q),
        .pc_i                (ifid_pc_q),
        .instr_i             (ifid_instr_q),
        .rs1_addr_i          (id_rs1_addr),
        .rs2_addr_i          (id_rs2_addr),
        .rd_addr_i           (id_rd_addr),
        .funct3_i            (id_funct3),
        .rs1_data_i          (id_rs1_data),
        .rs2_data_i          (id_rs2_data),
        .imm_i               (id_imm),
        .alu_op_i            (id_alu_op),
        .op_a_sel_i          (id_op_a_sel),
        .op_b_imm_i          (id_op_b_imm),
        .reg_write_i         (id_reg_write),
        .wb_sel_i            (id_wb_sel),
        .branch_i            (id_branch),
        .jal_i               (id_jal),
        .jalr_i              (id_jalr),
        .load_i              (id_load),
        .store_i             (id_store),
        .exc_valid_i         (id_any_exc),
        .exc_cause_i         (id_any_exc_cause),
        .forwarded_rs1_i     (ex_rs1_value),
        .forwarded_rs2_i     (ex_rs2_value),
        .valid_o             (idex_valid_q),
        .pc_o                (idex_pc_q),
        .instr_o             (idex_instr_q),
        .pc4_o               (idex_pc4_q),
        .rs1_addr_o          (idex_rs1_addr_q),
        .rs2_addr_o          (idex_rs2_addr_q),
        .rd_addr_o           (idex_rd_addr_q),
        .rs1_data_o          (idex_rs1_data_q),
        .rs2_data_o          (idex_rs2_data_q),
        .imm_o               (idex_imm_q),
        .funct3_o            (idex_funct3_q),
        .alu_op_o            (idex_alu_op_q),
        .op_a_sel_o          (idex_op_a_sel_q),
        .op_b_imm_o          (idex_op_b_imm_q),
        .reg_write_o         (idex_reg_write_q),
        .wb_sel_o            (idex_wb_sel_q),
        .branch_o            (idex_branch_q),
        .jal_o               (idex_jal_q),
        .jalr_o              (idex_jalr_q),
        .load_o              (idex_load_q),
        .store_o             (idex_store_q),
        .exc_valid_o         (idex_exc_valid_q),
        .exc_cause_o         (idex_exc_cause_q)
    );

    // EX: forwarding toán hạng, ALU/nhánh và phát hiện địa chỉ lệch hàng.
    rv32_ex_stage u_ex_stage (
        .valid_i             (idex_valid_q),
        .exc_valid_i         (idex_exc_valid_q),
        .rs1_data_i          (idex_rs1_data_q),
        .rs2_data_i          (idex_rs2_data_q),
        .op_a_sel_i          (idex_op_a_sel_q),
        .op_b_imm_i          (idex_op_b_imm_q),
        .pc_i                (idex_pc_q),
        .imm_i               (idex_imm_q),
        .alu_op_i            (idex_alu_op_q),
        .branch_i            (idex_branch_q),
        .funct3_i            (idex_funct3_q),
        .jal_i               (idex_jal_q),
        .jalr_i              (idex_jalr_q),
        .load_i              (idex_load_q),
        .store_i             (idex_store_q),
        .exmem_wb_sel_i      (exmem_wb_sel_q),
        .exmem_pc4_i         (exmem_pc4_q),
        .exmem_alu_result_i  (exmem_alu_result_q),
        .memwb_wb_data_i     (memwb_wb_data_q),
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

    // Thanh ghi EX/MEM: giữ/hủy lệnh tại ranh giới, không thêm chu kỳ pipeline.
    rv32_ex_mem_reg u_ex_mem_reg (
        .clk_i             (clk_i),
        .rst_i             (rst_i),
        .wb_trap_event_i   (wb_trap_event),
        .halted_i          (halted_q),
        .mem_stall_i       (mem_stall),
        .mem_fault_event_i (mem_fault_event),
        .valid_i           (idex_valid_q),
        .pc_i              (idex_pc_q),
        .instr_i           (idex_instr_q),
        .pc4_i             (idex_pc4_q),
        .rd_addr_i         (idex_rd_addr_q),
        .funct3_i          (idex_funct3_q),
        .reg_write_i       (idex_reg_write_q),
        .wb_sel_i          (idex_wb_sel_q),
        .load_i            (idex_load_q),
        .store_i           (idex_store_q),
        .exc_valid_i       (idex_exc_valid_q),
        .exc_cause_i       (idex_exc_cause_q),
        .store_data_i      (ex_rs2_value),
        .alu_result_i      (ex_alu_result),
        .fault_raw_i       (ex_fault_raw),
        .fault_cause_i     (ex_fault_cause),
        .valid_o           (exmem_valid_q),
        .pc_o              (exmem_pc_q),
        .instr_o           (exmem_instr_q),
        .pc4_o             (exmem_pc4_q),
        .rd_addr_o         (exmem_rd_addr_q),
        .reg_write_o       (exmem_reg_write_q),
        .wb_sel_o          (exmem_wb_sel_q),
        .alu_result_o      (exmem_alu_result_q),
        .store_data_o      (exmem_store_data_q),
        .funct3_o          (exmem_funct3_q),
        .load_o            (exmem_load_q),
        .store_o           (exmem_store_q),
        .exc_valid_o       (exmem_exc_valid_q),
        .exc_cause_o       (exmem_exc_cause_q)
    );

    // MEM: giao dịch dữ liệu, chờ đáp ứng, phát hiện lỗi và chọn kết quả load.
    rv32_mem_stage u_mem_stage (
        .rst_i           (rst_i),
        .halted_i        (halted_q),
        .wb_trap_event_i (wb_trap_event),
        .valid_i         (exmem_valid_q),
        .exc_valid_i     (exmem_exc_valid_q),
        .load_i          (exmem_load_q),
        .store_i         (exmem_store_q),
        .alu_result_i    (exmem_alu_result_q),
        .store_data_i    (exmem_store_data_q),
        .funct3_i        (exmem_funct3_q),
        .wb_sel_i        (exmem_wb_sel_q),
        .pc4_i           (exmem_pc4_q),
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

    // Thanh ghi MEM/WB: giữ/hủy lệnh tại ranh giới, không thêm chu kỳ pipeline.
    rv32_mem_wb_reg u_mem_wb_reg (
        .clk_i             (clk_i),
        .rst_i             (rst_i),
        .wb_trap_event_i   (wb_trap_event),
        .halted_i          (halted_q),
        .mem_stall_i       (mem_stall),
        .mem_fault_event_i (mem_fault_event),
        .valid_i           (exmem_valid_q),
        .pc_i              (exmem_pc_q),
        .instr_i           (exmem_instr_q),
        .rd_addr_i         (exmem_rd_addr_q),
        .reg_write_i       (exmem_reg_write_q),
        .load_i            (exmem_load_q),
        .exc_valid_i       (exmem_exc_valid_q),
        .exc_cause_i       (exmem_exc_cause_q),
        .wb_data_i         (mem_wb_data),
        .valid_o           (memwb_valid_q),
        .pc_o              (memwb_pc_q),
        .instr_o           (memwb_instr_q),
        .rd_addr_o         (memwb_rd_addr_q),
        .reg_write_o       (memwb_reg_write_q),
        .wb_data_o         (memwb_wb_data_q),
        .exc_valid_o       (memwb_exc_valid_q),
        .exc_cause_o       (memwb_exc_cause_q)
    );

    // WB: ghi thanh ghi, trace lệnh hoàn tất và chốt ngoại lệ chính xác.
    rv32_wb_stage u_wb_stage (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .valid_i          (memwb_valid_q),
        .exc_valid_i      (memwb_exc_valid_q),
        .reg_write_i      (memwb_reg_write_q),
        .rd_addr_i        (memwb_rd_addr_q),
        .wb_data_i        (memwb_wb_data_q),
        .pc_i             (memwb_pc_q),
        .instr_i          (memwb_instr_q),
        .exc_cause_i      (memwb_exc_cause_q),
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
        .idex_valid_i           (idex_valid_q),
        .idex_exc_valid_i       (idex_exc_valid_q),
        .idex_load_i            (idex_load_q),
        .idex_rd_addr_i         (idex_rd_addr_q),
        .idex_rs1_addr_i        (idex_rs1_addr_q),
        .idex_rs2_addr_i        (idex_rs2_addr_q),
        .exmem_valid_i          (exmem_valid_q),
        .exmem_exc_valid_i      (exmem_exc_valid_q),
        .exmem_reg_write_i      (exmem_reg_write_q),
        .exmem_load_i           (exmem_load_q),
        .exmem_rd_addr_i        (exmem_rd_addr_q),
        .memwb_valid_i          (memwb_valid_q),
        .memwb_exc_valid_i      (memwb_exc_valid_q),
        .memwb_reg_write_i      (memwb_reg_write_q),
        .memwb_rd_addr_i        (memwb_rd_addr_q),
        .mem_fault_raw_i        (mem_fault_raw),
        .mem_stall_i            (mem_stall),
        .ex_fault_raw_i         (ex_fault_raw),
        .ex_control_taken_i     (ex_control_taken),
        .ex_target_misaligned_i (ex_target_misaligned),
        .ifid_valid_i           (ifid_valid_q),
        .ifid_exc_valid_i       (ifid_exc_valid_q),
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
        .ifid_consumed_o        (ifid_consumed)
    );

endmodule

`default_nettype wire
