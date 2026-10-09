`ifndef RV32_DEFS_VH
`define RV32_DEFS_VH

// =============================================================================
// Tệp      : rv32_defs.vh
// Chức năng : Tập trung các mã điều khiển dùng chung trong core RV32I.
//
// Đặc tả:
//   - Các giá trị ALU và immediate là hợp đồng giữa decoder và
//     datapath; không được tự định nghĩa lại trong từng module.
//   - Opcode tuân theo RISC-V RV32I, unprivileged ISA v2.1.
//   - Tệp dùng macro Verilog-2001 để tương thích Quartus 20.1.
// =============================================================================

// Phép toán ALU, rộng 4 bit.
`define RV32_ALU_ADD       4'h0
`define RV32_ALU_SUB       4'h1
`define RV32_ALU_AND       4'h2
`define RV32_ALU_OR        4'h3
`define RV32_ALU_XOR       4'h4
`define RV32_ALU_SLL       4'h5
`define RV32_ALU_SRL       4'h6
`define RV32_ALU_SRA       4'h7
`define RV32_ALU_SLT       4'h8
`define RV32_ALU_SLTU      4'h9
`define RV32_ALU_COPY_B    4'hA

// Kiểu immediate, rộng 3 bit.
`define RV32_IMM_NONE      3'b000
`define RV32_IMM_I         3'b001
`define RV32_IMM_S         3'b010
`define RV32_IMM_B         3'b011
`define RV32_IMM_U         3'b100
`define RV32_IMM_J         3'b101

// Nguồn toán hạng A của ALU, rộng 2 bit.
`define RV32_OP_A_RS1      2'b00
`define RV32_OP_A_PC       2'b01
`define RV32_OP_A_ZERO     2'b10

// Nguồn write-back, rộng 2 bit.
`define RV32_WB_ALU        2'b00
`define RV32_WB_LOAD       2'b01
`define RV32_WB_PC4        2'b10

// Lựa chọn forwarding, dùng chung giữa control và EX.
`define RV32_FWD_NONE 2'b00
`define RV32_FWD_WB   2'b01
`define RV32_FWD_MEM  2'b10

// Opcode chuẩn của RV32I, rộng 7 bit.
`define RV32_OPCODE_LOAD      7'b0000011
`define RV32_OPCODE_MISC_MEM  7'b0001111
`define RV32_OPCODE_OP_IMM    7'b0010011
`define RV32_OPCODE_AUIPC     7'b0010111
`define RV32_OPCODE_STORE     7'b0100011
`define RV32_OPCODE_OP        7'b0110011
`define RV32_OPCODE_LUI       7'b0110111
`define RV32_OPCODE_BRANCH    7'b1100011
`define RV32_OPCODE_JALR      7'b1100111
`define RV32_OPCODE_JAL       7'b1101111
`define RV32_OPCODE_SYSTEM    7'b1110011

// Mã cause 5 bit của giao tiếp trap trong baseline hiện tại.
`define RV32_CAUSE_INSTR_ADDR_MISALIGNED  5'd0
`define RV32_CAUSE_INSTR_ACCESS_FAULT     5'd1
`define RV32_CAUSE_ILLEGAL_INSTRUCTION    5'd2
`define RV32_CAUSE_BREAKPOINT             5'd3
`define RV32_CAUSE_LOAD_ADDR_MISALIGNED   5'd4
`define RV32_CAUSE_LOAD_ACCESS_FAULT      5'd5
`define RV32_CAUSE_STORE_ADDR_MISALIGNED  5'd6
`define RV32_CAUSE_STORE_ACCESS_FAULT     5'd7
`define RV32_CAUSE_ECALL_MMODE            5'd11

`endif
