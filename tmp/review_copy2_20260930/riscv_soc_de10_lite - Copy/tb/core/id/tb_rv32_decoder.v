`timescale 1ns/1ps
`default_nettype none

`include "rv32_defs.vh"

`default_nettype none

// =============================================================================
// Testbench : tb_rv32_decoder
// Mục tiêu  : Tự kiểm tra decoder RV32I v2.1 và hợp đồng hazard.
//
// Kế hoạch kiểm thử:
//   1. Kiểm tra từng lệnh hợp lệ trong 40 lệnh cơ sở RV32I mà
//      baseline này hỗ trợ (FENCE.I đã chuyển sang Zifencei).
//   2. Kiểm tra nghiêm ngặt funct3/funct7 của branch, load, store,
//      shift-immediate và OP; M extension phải bị từ chối.
//   3. Kiểm tra FENCE chấp nhận các trường dự trữ khác 0,
//      trong khi FENCE.I, Zicsr và SYSTEM không chính xác phải illegal.
//   4. Kiểm tra uses_rs1/uses_rs2 cho hazard unit; lệnh illegal phải
//      giữ mọi tác dụng phụ và phụ thuộc nguồn ở mức 0.
//
// Tiêu chí PASS: mọi bit điều khiển khớp giá trị mong đợi;
// sai khác, bit X/Z hoặc timeout đều kết thúc bằng $fatal.
// =============================================================================

module tb_rv32_decoder;

    reg  [31:0] instr;
    wire [3:0]  alu_op;
    wire [2:0]  imm_type;
    wire [1:0]  op_a_sel;
    wire        op_b_imm;
    wire        reg_write;
    wire [1:0]  wb_sel;
    wire        branch;
    wire        jal;
    wire        jalr;
    wire        load;
    wire        store;
    wire        fence;
    wire        ecall;
    wire        ebreak;
    wire        illegal;
    wire        uses_rs1;
    wire        uses_rs2;

    wire [23:0] observed_ctrl;
    integer     check_count;

    // Thứ tự bit của vector này là hợp đồng nội bộ của testbench.
    assign observed_ctrl = {
        alu_op, imm_type, op_a_sel, op_b_imm, reg_write, wb_sel,
        branch, jal, jalr, load, store, fence, ecall, ebreak,
        illegal, uses_rs1, uses_rs2
    };

    rv32_decoder dut (
        .instr_i      (instr),
        .alu_op_o     (alu_op),
        .imm_type_o   (imm_type),
        .op_a_sel_o   (op_a_sel),
        .op_b_imm_o   (op_b_imm),
        .reg_write_o  (reg_write),
        .wb_sel_o     (wb_sel),
        .branch_o     (branch),
        .jal_o        (jal),
        .jalr_o       (jalr),
        .load_o       (load),
        .store_o      (store),
        .fence_o      (fence),
        .ecall_o      (ecall),
        .ebreak_o     (ebreak),
        .illegal_o    (illegal),
        .uses_rs1_o   (uses_rs1),
        .uses_rs2_o   (uses_rs2)
    );

    // Vector điều khiển chuẩn cho từng lớp lệnh. Bốn bit ALU cao
    // nhất sẽ được thay bằng hàm ctrl_with_alu khi cần.
    localparam [23:0] CTRL_ILLEGAL = {
        `RV32_ALU_ADD, `RV32_IMM_NONE, `RV32_OP_A_RS1, 1'b0,
        1'b0, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b1, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_LUI = {
        `RV32_ALU_COPY_B, `RV32_IMM_U, `RV32_OP_A_ZERO, 1'b1,
        1'b1, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_AUIPC = {
        `RV32_ALU_ADD, `RV32_IMM_U, `RV32_OP_A_PC, 1'b1,
        1'b1, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_JAL = {
        `RV32_ALU_ADD, `RV32_IMM_J, `RV32_OP_A_PC, 1'b1,
        1'b1, `RV32_WB_PC4,
        1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_JALR = {
        `RV32_ALU_ADD, `RV32_IMM_I, `RV32_OP_A_RS1, 1'b1,
        1'b1, `RV32_WB_PC4,
        1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b0
    };

    localparam [23:0] CTRL_BRANCH = {
        `RV32_ALU_ADD, `RV32_IMM_B, `RV32_OP_A_PC, 1'b1,
        1'b0, `RV32_WB_ALU,
        1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b1
    };

    localparam [23:0] CTRL_LOAD = {
        `RV32_ALU_ADD, `RV32_IMM_I, `RV32_OP_A_RS1, 1'b1,
        1'b1, `RV32_WB_LOAD,
        1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b0
    };

    localparam [23:0] CTRL_STORE = {
        `RV32_ALU_ADD, `RV32_IMM_S, `RV32_OP_A_RS1, 1'b1,
        1'b0, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b1
    };

    localparam [23:0] CTRL_OP_IMM = {
        `RV32_ALU_ADD, `RV32_IMM_I, `RV32_OP_A_RS1, 1'b1,
        1'b1, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b0
    };

    localparam [23:0] CTRL_OP = {
        `RV32_ALU_ADD, `RV32_IMM_NONE, `RV32_OP_A_RS1, 1'b0,
        1'b1, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        1'b0, 1'b1, 1'b1
    };

    localparam [23:0] CTRL_FENCE = {
        `RV32_ALU_ADD, `RV32_IMM_NONE, `RV32_OP_A_RS1, 1'b0,
        1'b0, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
        1'b0, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_ECALL = {
        `RV32_ALU_ADD, `RV32_IMM_NONE, `RV32_OP_A_RS1, 1'b0,
        1'b0, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
        1'b0, 1'b0, 1'b0
    };

    localparam [23:0] CTRL_EBREAK = {
        `RV32_ALU_ADD, `RV32_IMM_NONE, `RV32_OP_A_RS1, 1'b0,
        1'b0, `RV32_WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
        1'b0, 1'b0, 1'b0
    };

    function [23:0] ctrl_with_alu;
        input [23:0] base_ctrl;
        input [3:0]  selected_alu;
        begin
            ctrl_with_alu = {selected_alu, base_ctrl[19:0]};
        end
    endfunction

    function [31:0] encode_r;
        input [6:0] funct7_value;
        input [2:0] funct3_value;
        begin
            // rd=x3, rs1=x1, rs2=x2: cả hai nguồn đều khác x0.
            encode_r = {
                funct7_value, 5'd2, 5'd1, funct3_value,
                5'd3, `RV32_OPCODE_OP
            };
        end
    endfunction

    function [31:0] encode_i;
        input [11:0] immediate;
        input [2:0]  funct3_value;
        input [6:0]  opcode_value;
        begin
            encode_i = {
                immediate, 5'd1, funct3_value, 5'd3, opcode_value
            };
        end
    endfunction

    function [31:0] encode_s;
        input [2:0] funct3_value;
        reg   [11:0] immediate;
        begin
            immediate = 12'hA5C;
            encode_s = {
                immediate[11:5], 5'd2, 5'd1, funct3_value,
                immediate[4:0], `RV32_OPCODE_STORE
            };
        end
    endfunction

    function [31:0] encode_b;
        input [2:0] funct3_value;
        begin
            // Immediate âm và các thanh ghi nguồn khác x0.
            encode_b = {
                1'b1, 6'b010101, 5'd2, 5'd1, funct3_value,
                4'b1010, 1'b0, `RV32_OPCODE_BRANCH
            };
        end
    endfunction

    task check_decode;
        input [31:0]  instruction;
        input [23:0]  expected_ctrl;
        input [8*40-1:0] test_name;
        begin
            instr = instruction;
            #1;
            check_count = check_count + 1;

            if (observed_ctrl !== expected_ctrl) begin
                $display("FAIL %0s", test_name);
                $display("  instr    = %08h", instruction);
                $display("  observed = %06h", observed_ctrl);
                $display("  expected = %06h", expected_ctrl);
                $fatal(1, "Decoder output mismatch");
            end
        end
    endtask

    initial begin
        instr       = 32'b0;
        check_count = 0;

        // U/J: các bit trông giống rs1/rs2 cố ý khác 0 để kiểm tra
        // hazard metadata không được suy ra chỉ bằng vị trí bit.
        check_decode({20'hABCDE, 5'd3, `RV32_OPCODE_LUI},
                     CTRL_LUI, "LUI");
        check_decode({20'h5A5A5, 5'd3, `RV32_OPCODE_AUIPC},
                     CTRL_AUIPC, "AUIPC");
        check_decode({20'hD5A5A, 5'd3, `RV32_OPCODE_JAL},
                     CTRL_JAL, "JAL");
        check_decode(encode_i(12'hFFC, 3'b000, `RV32_OPCODE_JALR),
                     CTRL_JALR, "JALR");

        // Sáu lệnh branch hợp lệ.
        check_decode(encode_b(3'b000), CTRL_BRANCH, "BEQ");
        check_decode(encode_b(3'b001), CTRL_BRANCH, "BNE");
        check_decode(encode_b(3'b100), CTRL_BRANCH, "BLT");
        check_decode(encode_b(3'b101), CTRL_BRANCH, "BGE");
        check_decode(encode_b(3'b110), CTRL_BRANCH, "BLTU");
        check_decode(encode_b(3'b111), CTRL_BRANCH, "BGEU");

        // Năm lệnh load và ba lệnh store hợp lệ.
        check_decode(encode_i(12'hFF8, 3'b000, `RV32_OPCODE_LOAD),
                     CTRL_LOAD, "LB");
        check_decode(encode_i(12'h004, 3'b001, `RV32_OPCODE_LOAD),
                     CTRL_LOAD, "LH");
        check_decode(encode_i(12'h008, 3'b010, `RV32_OPCODE_LOAD),
                     CTRL_LOAD, "LW");
        check_decode(encode_i(12'h00C, 3'b100, `RV32_OPCODE_LOAD),
                     CTRL_LOAD, "LBU");
        check_decode(encode_i(12'h010, 3'b101, `RV32_OPCODE_LOAD),
                     CTRL_LOAD, "LHU");
        check_decode(encode_s(3'b000), CTRL_STORE, "SB");
        check_decode(encode_s(3'b001), CTRL_STORE, "SH");
        check_decode(encode_s(3'b010), CTRL_STORE, "SW");

        // Chín lệnh OP-IMM. Immediate của lệnh không dịch có thể
        // mang bất kỳ bit cao nào và vẫn phải hợp lệ.
        check_decode(encode_i(12'hFFF, 3'b000, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_ADD), "ADDI");
        check_decode(encode_i(12'hA55, 3'b010, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_SLT), "SLTI");
        check_decode(encode_i(12'h800, 3'b011, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_SLTU), "SLTIU");
        check_decode(encode_i(12'hACE, 3'b100, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_XOR), "XORI");
        check_decode(encode_i(12'h987, 3'b110, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_OR), "ORI");
        check_decode(encode_i(12'hFED, 3'b111, `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_AND), "ANDI");
        check_decode(encode_i({7'b0000000, 5'd31}, 3'b001,
                              `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_SLL), "SLLI");
        check_decode(encode_i({7'b0000000, 5'd31}, 3'b101,
                              `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_SRL), "SRLI");
        check_decode(encode_i({7'b0100000, 5'd31}, 3'b101,
                              `RV32_OPCODE_OP_IMM),
                     ctrl_with_alu(CTRL_OP_IMM, `RV32_ALU_SRA), "SRAI");

        // Mười lệnh OP.
        check_decode(encode_r(7'b0000000, 3'b000),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_ADD), "ADD");
        check_decode(encode_r(7'b0100000, 3'b000),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SUB), "SUB");
        check_decode(encode_r(7'b0000000, 3'b001),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SLL), "SLL");
        check_decode(encode_r(7'b0000000, 3'b010),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SLT), "SLT");
        check_decode(encode_r(7'b0000000, 3'b011),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SLTU), "SLTU");
        check_decode(encode_r(7'b0000000, 3'b100),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_XOR), "XOR");
        check_decode(encode_r(7'b0000000, 3'b101),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SRL), "SRL");
        check_decode(encode_r(7'b0100000, 3'b101),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_SRA), "SRA");
        check_decode(encode_r(7'b0000000, 3'b110),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_OR), "OR");
        check_decode(encode_r(7'b0000000, 3'b111),
                     ctrl_with_alu(CTRL_OP, `RV32_ALU_AND), "AND");

        // FENCE chứa cố ý imm/rs1/rd khác 0: decoder chỉ xét funct3.
        check_decode({12'hFFF, 5'd17, 3'b000, 5'd9,
                      `RV32_OPCODE_MISC_MEM},
                     CTRL_FENCE, "FENCE reserved fields ignored");
        check_decode(32'h0000_0073, CTRL_ECALL, "ECALL exact");
        check_decode(32'h0010_0073, CTRL_EBREAK, "EBREAK exact");

        // Các funct3 dự trữ.
        check_decode(encode_i(12'h123, 3'b001, `RV32_OPCODE_JALR),
                     CTRL_ILLEGAL, "JALR reserved funct3");
        check_decode(encode_b(3'b010), CTRL_ILLEGAL,
                     "BRANCH reserved funct3 010");
        check_decode(encode_b(3'b011), CTRL_ILLEGAL,
                     "BRANCH reserved funct3 011");
        check_decode(encode_i(12'h123, 3'b011, `RV32_OPCODE_LOAD),
                     CTRL_ILLEGAL, "LOAD reserved funct3 011");
        check_decode(encode_i(12'h123, 3'b110, `RV32_OPCODE_LOAD),
                     CTRL_ILLEGAL, "LOAD reserved funct3 110");
        check_decode(encode_i(12'h123, 3'b111, `RV32_OPCODE_LOAD),
                     CTRL_ILLEGAL, "LOAD reserved funct3 111");
        check_decode(encode_s(3'b011), CTRL_ILLEGAL,
                     "STORE reserved funct3 011");
        check_decode(encode_s(3'b100), CTRL_ILLEGAL,
                     "STORE reserved funct3 100");
        check_decode(encode_s(3'b101), CTRL_ILLEGAL,
                     "STORE reserved funct3 101");
        check_decode(encode_s(3'b110), CTRL_ILLEGAL,
                     "STORE reserved funct3 110");
        check_decode(encode_s(3'b111), CTRL_ILLEGAL,
                     "STORE reserved funct3 111");

        // Các funct7 dự trữ và M extension.
        check_decode(encode_i({7'b0100000, 5'd1}, 3'b001,
                              `RV32_OPCODE_OP_IMM),
                     CTRL_ILLEGAL, "SLLI reserved funct7");
        check_decode(encode_i({7'b0000001, 5'd1}, 3'b101,
                              `RV32_OPCODE_OP_IMM),
                     CTRL_ILLEGAL, "SRLI SRAI reserved funct7");
        check_decode(encode_r(7'b0000001, 3'b000), CTRL_ILLEGAL,
                     "M extension MUL illegal");
        check_decode(encode_r(7'b0100000, 3'b111), CTRL_ILLEGAL,
                     "OP reserved funct7 funct3");

        // FENCE.I, funct3 MISC-MEM dự trữ, Zicsr và SYSTEM gần đúng.
        check_decode(encode_i(12'h000, 3'b001, `RV32_OPCODE_MISC_MEM),
                     CTRL_ILLEGAL, "FENCE.I illegal");
        check_decode(encode_i(12'h000, 3'b010, `RV32_OPCODE_MISC_MEM),
                     CTRL_ILLEGAL, "MISC-MEM reserved funct3");
        check_decode(encode_i(12'hC00, 3'b010, `RV32_OPCODE_SYSTEM),
                     CTRL_ILLEGAL, "Zicsr CSRRS illegal");
        check_decode(32'h0000_00F3, CTRL_ILLEGAL,
                     "ECALL with nonzero rd illegal");
        check_decode(32'h0010_80F3, CTRL_ILLEGAL,
                     "EBREAK malformed illegal");
        check_decode(32'h3020_0073, CTRL_ILLEGAL, "MRET illegal");
        check_decode(32'h1050_0073, CTRL_ILLEGAL, "WFI illegal");

        // Opcode dự trữ/không được hỗ trợ; các trường rs cố ý khác 0.
        check_decode(32'hFFFF_FF80, CTRL_ILLEGAL, "Reserved opcode");

        $display("PASS: %0d decoder checks", check_count);
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Timeout while testing rv32_decoder");
    end

endmodule

`default_nettype wire
