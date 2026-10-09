`default_nettype none
`include "rv32_defs.vh"

// EX: forwarding toán hạng, ALU/nhánh và kiểm tra địa chỉ lệch hàng.
// Logic tổ hợp, không giữ trạng thái. fault_raw được khóa bởi valid/exc_valid;
// bộ điều khiển core phân xử lỗi và redirect theo tuổi lệnh trước khi áp dụng.
// Chi tiết ranh giới pipeline: docs/giao_tiep_rtl_vi.md, mục 5.
module rv32_ex_stage (
    // Trạng thái lệnh ID/EX: chỉ lệnh hợp lệ, chưa mang ngoại lệ mới tạo lỗi EX.
    input  wire         valid_i,
    input  wire         exc_valid_i,

    // Hai toán hạng đã chốt tại ID/EX, trước khi chọn forwarding.
    input  wire [31:0]  rs1_data_i,
    input  wire [31:0]  rs2_data_i,

    // Điều khiển ALU: A chọn rs1/PC/0; B chọn immediate hoặc rs2.
    // PC là địa chỉ byte; immediate đã mở rộng thành 32 bit tại ID.
    input  wire [1:0]   op_a_sel_i,
    input  wire         op_b_imm_i,
    input  wire [31:0]  pc_i,
    input  wire [31:0]  imm_i,
    input  wire [3:0]   alu_op_i,

    // Loại nhánh/nhảy và truy cập dữ liệu; funct3 chọn điều kiện nhánh
    // hoặc cỡ load/store. Đích JALR phải xóa bit 0 trước kiểm tra căn chỉnh.
    input  wire         branch_i,
    input  wire [2:0]   funct3_i,
    input  wire         jal_i,
    input  wire         jalr_i,
    input  wire         load_i,
    input  wire         store_i,

    // Dữ liệu forwarding: EX/MEM cung cấp ALU hoặc PC+4; MEM/WB có cả load.
    // Bộ hazard không chọn EX/MEM khi lệnh ở MEM là load.
    input  wire [1:0]   exmem_wb_sel_i,
    input  wire [31:0]  exmem_pc4_i,
    input  wire [31:0]  exmem_alu_result_i,
    input  wire [31:0]  memwb_wb_data_i,

    // Mã chọn: 00=ID/EX, 01=MEM/WB, 10=EX/MEM; EX/MEM ưu tiên MEM/WB.
    input  wire [1:0]   forward_rs1_sel_i,
    input  wire [1:0]   forward_rs2_sel_i,

    // Toán hạng sau forwarding; rs2 còn được chốt làm dữ liệu store.
    output reg  [31:0]  rs1_value_o,
    output reg  [31:0]  rs2_value_o,

    // Kết quả ALU; với load/store đây là địa chỉ byte hiệu dụng.
    output wire [31:0]  alu_result_o,

    // Đích và yêu cầu chuyển luồng; JALR đã xóa bit 0. Bộ điều khiển
    // còn xét valid/ngoại lệ và sự kiện của lệnh già hơn trước khi redirect.
    output wire [31:0]  control_target_o,
    output wire         control_taken_o,
    output wire         target_misaligned_o,

    // Lỗi căn chỉnh khi valid && !exc_valid; cause 0/4/6 lần lượt cho
    // đích nhảy/load/store. Cause chỉ có nghĩa khi fault_raw=1.
    output wire         fault_raw_o,
    output reg  [4:0]   fault_cause_o
);

    localparam [1:0] OP_A_PC   = `RV32_OP_A_PC;
    localparam [1:0] OP_A_ZERO = `RV32_OP_A_ZERO;
    localparam [1:0] WB_PC4    = `RV32_WB_PC4;
    localparam [1:0] FWD_WB    = `RV32_FWD_WB;
    localparam [1:0] FWD_MEM   = `RV32_FWD_MEM;

    localparam [4:0] CAUSE_INSTR_ADDR_MISALIGNED = `RV32_CAUSE_INSTR_ADDR_MISALIGNED;
    localparam [4:0] CAUSE_LOAD_ADDR_MISALIGNED  = `RV32_CAUSE_LOAD_ADDR_MISALIGNED;
    localparam [4:0] CAUSE_STORE_ADDR_MISALIGNED = `RV32_CAUSE_STORE_ADDR_MISALIGNED;

    // 1. Chọn dữ liệu forwarding trước ALU, so sánh nhánh và dữ liệu store.
    // EX/MEM chỉ có PC+4 hoặc kết quả ALU; hazard loại load khỏi nguồn này.
    wire [31:0] mem_forward_data;

    assign mem_forward_data = (exmem_wb_sel_i == WB_PC4)
                              ? exmem_pc4_i
                              : exmem_alu_result_i;

    always @(*) begin
        case (forward_rs1_sel_i)
            FWD_MEM: rs1_value_o = mem_forward_data;
            FWD_WB : rs1_value_o = memwb_wb_data_i;
            default: rs1_value_o = rs1_data_i;
        endcase

        case (forward_rs2_sel_i)
            FWD_MEM: rs2_value_o = mem_forward_data;
            FWD_WB : rs2_value_o = memwb_wb_data_i;
            default: rs2_value_o = rs2_data_i;
        endcase
    end

    // 2. Chọn toán hạng ALU: A=rs1/PC/0; B=immediate/rs2.
    reg  [31:0] ex_operand_a;
    wire [31:0] ex_operand_b;

    always @(*) begin
        case (op_a_sel_i)
            OP_A_PC  : ex_operand_a = pc_i;
            OP_A_ZERO: ex_operand_a = 32'b0;
            default  : ex_operand_a = rs1_value_o;
        endcase
    end

    assign ex_operand_b = op_b_imm_i ? imm_i : rs2_value_o;

    rv32_alu u_alu (
        .operand_a_i (ex_operand_a),
        .operand_b_i (ex_operand_b),
        .alu_op_i    (alu_op_i),
        .result_o    (alu_result_o)
    );

    // 3. So sánh nhánh chỉ hoạt động với lệnh hợp lệ, chưa có ngoại lệ.
    wire ex_branch_taken;

    rv32_branch_unit u_branch_unit (
        .branch_en_i    (branch_i && valid_i && !exc_valid_i),
        .funct3_i       (funct3_i),
        .rs1_data_i     (rs1_value_o),
        .rs2_data_i     (rs2_value_o),
        .branch_taken_o (ex_branch_taken)
    );

    // Decoder chọn PC/rs1 cộng immediate cho branch, JAL và JALR.
    // Tái sử dụng bộ cộng ALU làm đích; JALR xóa bit 0 trước kiểm tra căn chỉnh.
    assign control_target_o = jalr_i
                              ? {alu_result_o[31:1], 1'b0}
                              : alu_result_o;
    assign control_taken_o = jal_i || jalr_i ||
                             (branch_i && ex_branch_taken);
    assign target_misaligned_o = control_taken_o &&
                                 (control_target_o[1:0] != 2'b00);

    // 4. LSU tại EX chỉ kiểm tra căn chỉnh; bốn đầu ra dữ liệu không sử dụng.
    // LSU tại MEM mới tạo địa chỉ, dữ liệu và byte-enable đưa lên bus.
    wire [31:0] ex_lsu_addr_unused;
    wire [31:0] ex_lsu_wdata_unused;
    wire [3:0]  ex_lsu_wstrb_unused;
    wire [31:0] ex_lsu_load_unused;
    // LSU kiểm tra địa chỉ load/store tại EX trước khi phát data bus.
    wire        ex_lsu_misaligned;

    rv32_lsu u_lsu_ex_check (
        .addr_i         (alu_result_o),
        .funct3_i       (funct3_i),
        .load_en_i      (load_i && valid_i && !exc_valid_i),
        .store_en_i     (store_i && valid_i && !exc_valid_i),
        .store_data_i   (rs2_value_o),
        .load_data_i    (32'b0),
        .mem_addr_o     (ex_lsu_addr_unused),
        .mem_wdata_o    (ex_lsu_wdata_unused),
        .mem_wstrb_o    (ex_lsu_wstrb_unused),
        .load_data_o    (ex_lsu_load_unused),
        .misaligned_o   (ex_lsu_misaligned)
    );

    // Lỗi thô còn phải qua phân xử với MEM; ưu tiên cause: đích nhảy, load, store.
    assign fault_raw_o = valid_i && !exc_valid_i &&
                         (target_misaligned_o || ex_lsu_misaligned);

    always @(*) begin
        if (target_misaligned_o)
            fault_cause_o = CAUSE_INSTR_ADDR_MISALIGNED;
        else if (load_i)
            fault_cause_o = CAUSE_LOAD_ADDR_MISALIGNED;
        else
            fault_cause_o = CAUSE_STORE_ADDR_MISALIGNED;
    end

endmodule

`default_nettype wire
