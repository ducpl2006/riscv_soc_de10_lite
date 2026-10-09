`default_nettype none

`include "rv32_defs.vh"

`default_nettype none

// =============================================================================
// Module    : rv32_decoder
// Chức năng : Giải mã nghiêm ngặt tập lệnh cơ sở RV32I v2.1.
//
// Đặc tả hoạt động:
//   - Logic tổ hợp, không có clock, độ trễ một tầng logic giải mã.
//   - Mọi lệnh không hợp lệ đều đặt illegal_o=1 và vô hiệu toàn bộ
//     tác dụng phụ như ghi thanh ghi, load, store hay thay đổi luồng điều khiển.
//   - branch_o chỉ xác nhận sáu lệnh nhánh chuẩn. Khối branch phía sau
//     dùng instr_i[14:12] để chọn điều kiện so sánh.
//   - load_o/store_o chỉ xác nhận các kích thước hợp lệ. Khối LSU dùng
//     instr_i[14:12] để chọn byte/half-word/word và signed/unsigned.
//   - FENCE (funct3=000) là lệnh hợp lệ; các trường dự trữ rs1/rd/fm
//     không được kiểm tra. FENCE.I và Zicsr không thuộc baseline này.
//   - ECALL và EBREAK phải khớp chính xác toàn bộ mã lệnh.
//   - uses_rs1_o/uses_rs2_o mô tả phụ thuộc dữ liệu thực sự cho
//     hazard/forwarding unit của pipeline; lệnh illegal không dùng nguồn nào.
//
// Quy ước datapath:
//   - op_b_imm_o=1: toán hạng B lấy từ immediate; =0: lấy từ rs2.
//   - Nhánh/JAL tính đích bằng PC + immediate; JALR tính rs1 + immediate.
//   - reg_write_o chỉ là yêu cầu ghi; register file vẫn phải chặn rd=x0.
// =============================================================================

module rv32_decoder (
    // Mã lệnh RV32I 32 bit của lệnh đang xét.
    input  wire [31:0] instr_i,

    // Mã phép toán nội bộ RV32_ALU_* trong rv32_defs.vh.
    output reg  [3:0]  alu_op_o,
    // Chọn dạng immediate theo RV32_IMM_* trong rv32_defs.vh.
    output reg  [2:0]  imm_type_o,
    // Chọn toán hạng A: RV32_OP_A_RS1 / PC / ZERO.
    output reg  [1:0]  op_a_sel_o,
    // 1: ALU lấy immediate làm B; 0: lấy giá trị rs2.
    output reg         op_b_imm_o,
    // Yêu cầu ghi rd; còn phải kiểm tra valid, ngoại lệ và rd khác x0.
    output reg         reg_write_o,
    // Chọn nguồn ghi về: RV32_WB_ALU / LOAD / PC4.
    output reg  [1:0]  wb_sel_o,
    // 1: lệnh nhánh có điều kiện; chưa có nghĩa là nhánh được lấy.
    output reg         branch_o,
    // 1: lệnh JAL, nhảy tới PC + immediate và ghi PC+4 vào rd.
    output reg         jal_o,
    // 1: lệnh JALR; đích rs1 + immediate phải xóa bit 0.
    output reg         jalr_o,
    // 1: lệnh đọc bộ nhớ; cỡ đọc và mở rộng dấu do funct3 quyết định.
    output reg         load_o,
    // 1: lệnh ghi bộ nhớ; cỡ ghi do funct3 quyết định.
    output reg         store_o,
    // 1: FENCE hợp lệ; thực hiện như NOP trong core in-order hiện tại.
    output reg         fence_o,
    // 1: lệnh ECALL; ID tạo ngoại lệ cause 11.
    output reg         ecall_o,
    // 1: lệnh EBREAK; ID tạo ngoại lệ breakpoint, cause 3.
    output reg         ebreak_o,
    // 1: mã lệnh không hỗ trợ/không hợp lệ; các tác dụng phụ bị vô hiệu.
    output reg         illegal_o,
    // 1: lệnh thực sự đọc rs1; dùng để tránh báo hazard giả.
    output reg         uses_rs1_o,
    // 1: lệnh thực sự đọc rs2; dùng để tránh báo hazard giả.
    output reg         uses_rs2_o
);

    // Trường instr[6:0], xác định nhóm lệnh chính.
    wire [6:0] opcode;
    // Trường instr[14:12], chọn điều kiện nhánh hoặc cỡ/kiểu load-store.
    wire [2:0] funct3;
    // Trường instr[31:25], phân biệt phép toán và kiểm tra encoding hợp lệ.
    wire [6:0] funct7;

    assign opcode = instr_i[6:0];
    assign funct3 = instr_i[14:12];
    assign funct7 = instr_i[31:25];

    always @(*) begin
        // Giá trị an toàn: lệnh chưa được công nhận là illegal và
        // không được phép gây bất kỳ thay đổi trạng thái kiến trúc nào.
        alu_op_o    = `RV32_ALU_ADD;
        imm_type_o  = `RV32_IMM_NONE;
        op_a_sel_o  = `RV32_OP_A_RS1;
        op_b_imm_o  = 1'b0;
        reg_write_o = 1'b0;
        wb_sel_o    = `RV32_WB_ALU;
        branch_o    = 1'b0;
        jal_o       = 1'b0;
        jalr_o      = 1'b0;
        load_o      = 1'b0;
        store_o     = 1'b0;
        fence_o     = 1'b0;
        ecall_o     = 1'b0;
        ebreak_o    = 1'b0;
        illegal_o   = 1'b1;
        uses_rs1_o  = 1'b0;
        uses_rs2_o  = 1'b0;

        case (opcode)
            `RV32_OPCODE_LUI: begin
                alu_op_o    = `RV32_ALU_COPY_B;
                imm_type_o  = `RV32_IMM_U;
                op_a_sel_o  = `RV32_OP_A_ZERO;
                op_b_imm_o  = 1'b1;
                reg_write_o = 1'b1;
                illegal_o   = 1'b0;
            end

            `RV32_OPCODE_AUIPC: begin
                alu_op_o    = `RV32_ALU_ADD;
                imm_type_o  = `RV32_IMM_U;
                op_a_sel_o  = `RV32_OP_A_PC;
                op_b_imm_o  = 1'b1;
                reg_write_o = 1'b1;
                illegal_o   = 1'b0;
            end

            `RV32_OPCODE_JAL: begin
                alu_op_o    = `RV32_ALU_ADD;
                imm_type_o  = `RV32_IMM_J;
                op_a_sel_o  = `RV32_OP_A_PC;
                op_b_imm_o  = 1'b1;
                reg_write_o = 1'b1;
                wb_sel_o    = `RV32_WB_PC4;
                jal_o       = 1'b1;
                illegal_o   = 1'b0;
            end

            `RV32_OPCODE_JALR: begin
                if (funct3 == 3'b000) begin
                    alu_op_o    = `RV32_ALU_ADD;
                    imm_type_o  = `RV32_IMM_I;
                    op_a_sel_o  = `RV32_OP_A_RS1;
                    op_b_imm_o  = 1'b1;
                    reg_write_o = 1'b1;
                    wb_sel_o    = `RV32_WB_PC4;
                    jalr_o      = 1'b1;
                    illegal_o   = 1'b0;
                    uses_rs1_o  = 1'b1;
                end
            end

            `RV32_OPCODE_BRANCH: begin
                case (funct3)
                    3'b000, // BEQ
                    3'b001, // BNE
                    3'b100, // BLT
                    3'b101, // BGE
                    3'b110, // BLTU
                    3'b111: // BGEU
                        illegal_o = 1'b0;
                    default:
                        illegal_o = 1'b1;
                endcase

                if (!illegal_o) begin
                    alu_op_o   = `RV32_ALU_ADD;
                    imm_type_o = `RV32_IMM_B;
                    op_a_sel_o = `RV32_OP_A_PC;
                    op_b_imm_o = 1'b1;
                    branch_o   = 1'b1;
                    uses_rs1_o = 1'b1;
                    uses_rs2_o = 1'b1;
                end
            end

            `RV32_OPCODE_LOAD: begin
                case (funct3)
                    3'b000, // LB
                    3'b001, // LH
                    3'b010, // LW
                    3'b100, // LBU
                    3'b101: // LHU
                        illegal_o = 1'b0;
                    default:
                        illegal_o = 1'b1;
                endcase

                if (!illegal_o) begin
                    alu_op_o    = `RV32_ALU_ADD;
                    imm_type_o  = `RV32_IMM_I;
                    op_a_sel_o  = `RV32_OP_A_RS1;
                    op_b_imm_o  = 1'b1;
                    reg_write_o = 1'b1;
                    wb_sel_o    = `RV32_WB_LOAD;
                    load_o      = 1'b1;
                    uses_rs1_o  = 1'b1;
                end
            end

            `RV32_OPCODE_STORE: begin
                case (funct3)
                    3'b000, // SB
                    3'b001, // SH
                    3'b010: // SW
                        illegal_o = 1'b0;
                    default:
                        illegal_o = 1'b1;
                endcase

                if (!illegal_o) begin
                    alu_op_o   = `RV32_ALU_ADD;
                    imm_type_o = `RV32_IMM_S;
                    op_a_sel_o = `RV32_OP_A_RS1;
                    op_b_imm_o = 1'b1;
                    store_o    = 1'b1;
                    uses_rs1_o = 1'b1;
                    uses_rs2_o = 1'b1;
                end
            end

            `RV32_OPCODE_OP_IMM: begin
                case (funct3)
                    3'b000: begin // ADDI
                        alu_op_o  = `RV32_ALU_ADD;
                        illegal_o = 1'b0;
                    end
                    3'b010: begin // SLTI
                        alu_op_o  = `RV32_ALU_SLT;
                        illegal_o = 1'b0;
                    end
                    3'b011: begin // SLTIU
                        alu_op_o  = `RV32_ALU_SLTU;
                        illegal_o = 1'b0;
                    end
                    3'b100: begin // XORI
                        alu_op_o  = `RV32_ALU_XOR;
                        illegal_o = 1'b0;
                    end
                    3'b110: begin // ORI
                        alu_op_o  = `RV32_ALU_OR;
                        illegal_o = 1'b0;
                    end
                    3'b111: begin // ANDI
                        alu_op_o  = `RV32_ALU_AND;
                        illegal_o = 1'b0;
                    end
                    3'b001: begin // SLLI: imm[11:5] phải bằng 0000000.
                        if (funct7 == 7'b0000000) begin
                            alu_op_o  = `RV32_ALU_SLL;
                            illegal_o = 1'b0;
                        end
                    end
                    3'b101: begin
                        case (funct7)
                            7'b0000000: begin // SRLI
                                alu_op_o  = `RV32_ALU_SRL;
                                illegal_o = 1'b0;
                            end
                            7'b0100000: begin // SRAI
                                alu_op_o  = `RV32_ALU_SRA;
                                illegal_o = 1'b0;
                            end
                            default:
                                illegal_o = 1'b1;
                        endcase
                    end
                    default:
                        illegal_o = 1'b1;
                endcase

                if (!illegal_o) begin
                    imm_type_o  = `RV32_IMM_I;
                    op_a_sel_o  = `RV32_OP_A_RS1;
                    op_b_imm_o  = 1'b1;
                    reg_write_o = 1'b1;
                    uses_rs1_o  = 1'b1;
                end
            end

            `RV32_OPCODE_OP: begin
                case ({funct7, funct3})
                    10'b0000000_000: begin // ADD
                        alu_op_o  = `RV32_ALU_ADD;
                        illegal_o = 1'b0;
                    end
                    10'b0100000_000: begin // SUB
                        alu_op_o  = `RV32_ALU_SUB;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_001: begin // SLL
                        alu_op_o  = `RV32_ALU_SLL;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_010: begin // SLT
                        alu_op_o  = `RV32_ALU_SLT;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_011: begin // SLTU
                        alu_op_o  = `RV32_ALU_SLTU;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_100: begin // XOR
                        alu_op_o  = `RV32_ALU_XOR;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_101: begin // SRL
                        alu_op_o  = `RV32_ALU_SRL;
                        illegal_o = 1'b0;
                    end
                    10'b0100000_101: begin // SRA
                        alu_op_o  = `RV32_ALU_SRA;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_110: begin // OR
                        alu_op_o  = `RV32_ALU_OR;
                        illegal_o = 1'b0;
                    end
                    10'b0000000_111: begin // AND
                        alu_op_o  = `RV32_ALU_AND;
                        illegal_o = 1'b0;
                    end
                    default:
                        illegal_o = 1'b1;
                endcase

                if (!illegal_o) begin
                    op_a_sel_o  = `RV32_OP_A_RS1;
                    reg_write_o = 1'b1;
                    uses_rs1_o  = 1'b1;
                    uses_rs2_o  = 1'b1;
                end
            end

            `RV32_OPCODE_MISC_MEM: begin
                // Chỉ FENCE thuộc baseline RV32I. Theo hợp đồng module,
                // các trường dự trữ của FENCE được bỏ qua.
                if (funct3 == 3'b000) begin
                    fence_o   = 1'b1;
                    illegal_o = 1'b0;
                end
            end

            `RV32_OPCODE_SYSTEM: begin
                if (instr_i == 32'h0000_0073) begin
                    ecall_o   = 1'b1;
                    illegal_o = 1'b0;
                end
                else if (instr_i == 32'h0010_0073) begin
                    ebreak_o  = 1'b1;
                    illegal_o = 1'b0;
                end
                // CSR*, MRET/WFI và SYSTEM dự trữ giữ default illegal.
            end

            default: begin
                illegal_o = 1'b1;
            end
        endcase
    end

endmodule

`default_nettype wire
