`default_nettype none

`include "eq_reference_rv32_defs.vh"

// =============================================================================
// Module      : rv32_alu
// Chức năng   : Khối số học và logic tổ hợp cho datapath RV32I.
//
// Đặc tả giao tiếp
//   - operand_a_i, operand_b_i: hai toán hạng 32 bit.
//   - alu_op_i               : mã phép toán nội bộ, được liệt kê bên dưới.
//   - result_o               : kết quả 32 bit, hợp lệ sau trễ lan truyền tổ hợp.
//
// Nguyên tắc thời gian
//   - Module không có clock và không lưu trạng thái.
//   - Mỗi thay đổi ở đầu vào được phản ánh trực tiếp lên result_o.
//
// Trường hợp biên
//   - ADD/SUB tuân theo số học modulo 2^32; cờ carry/overflow không được xuất.
//   - Các phép dịch chỉ dùng operand_b_i[4:0], đúng quy tắc RV32I.
//   - SRA và SLT diễn giải toán hạng là số bù hai có dấu.
//   - Mã alu_op_i dự phòng luôn trả về 0 để đầu ra xác định và không tạo latch.
// =============================================================================
module eq_reference_rv32_alu (
    // Toán hạng A 32 bit; SLT/SRA diễn giải dấu theo phép toán.
    input  wire [31:0] operand_a_i,
    // Toán hạng B 32 bit; phép dịch chỉ dùng 5 bit thấp.
    input  wire [31:0] operand_b_i,
    // Mã phép toán nội bộ RV32_ALU_* trong rv32_defs.vh.
    input  wire [3:0]  alu_op_i,

    // Kết quả tổ hợp 32 bit; ADD/SUB modulo 2^32, mã dự phòng trả 0.
    output reg  [31:0] result_o
);

    // Số bit dịch 0..31, lấy từ operand_b_i[4:0].
    wire [4:0] shift_amount;

    assign shift_amount = operand_b_i[4:0];

    always @(*) begin
        // Giá trị mặc định bảo đảm logic tổ hợp đầy đủ cho mọi mã điều khiển.
        result_o = 32'b0;

        case (alu_op_i)
            `EQ_REFERENCE_RV32_ALU_ADD: begin
                result_o = operand_a_i + operand_b_i;
            end

            `EQ_REFERENCE_RV32_ALU_SUB: begin
                result_o = operand_a_i - operand_b_i;
            end

            `EQ_REFERENCE_RV32_ALU_AND: begin
                result_o = operand_a_i & operand_b_i;
            end

            `EQ_REFERENCE_RV32_ALU_OR: begin
                result_o = operand_a_i | operand_b_i;
            end

            `EQ_REFERENCE_RV32_ALU_XOR: begin
                result_o = operand_a_i ^ operand_b_i;
            end

            `EQ_REFERENCE_RV32_ALU_SLL: begin
                result_o = operand_a_i << shift_amount;
            end

            `EQ_REFERENCE_RV32_ALU_SRL: begin
                result_o = operand_a_i >> shift_amount;
            end

            `EQ_REFERENCE_RV32_ALU_SRA: begin
                result_o = $signed(operand_a_i) >>> shift_amount;
            end

            `EQ_REFERENCE_RV32_ALU_SLT: begin
                result_o = ($signed(operand_a_i) < $signed(operand_b_i))
                         ? 32'd1
                         : 32'd0;
            end

            `EQ_REFERENCE_RV32_ALU_SLTU: begin
                result_o = (operand_a_i < operand_b_i) ? 32'd1 : 32'd0;
            end

            `EQ_REFERENCE_RV32_ALU_COPY_B: begin
                result_o = operand_b_i;
            end

            default: begin
                result_o = 32'b0;
            end
        endcase
    end

endmodule

`default_nettype wire
