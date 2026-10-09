`default_nettype none

`include "eq_reference_rv32_defs.vh"

/*
 * Bộ sinh immediate RV32I
 *
 * Đặc tả giao tiếp:
 * - instr_i là từ lệnh 32 bit chưa giải mã.
 * - imm_type_i do khối giải mã phát, dùng đúng bảng mã:
 *     000: không có immediate, 001: I, 010: S,
 *     011: B, 100: U, 101: J.
 * - imm_o là immediate 32 bit đã mở rộng dấu (I/S/B/J) hoặc đã đặt
 *   12 bit thấp bằng 0 (U).
 *
 * Thời gian:
 * - Đây là logic tổ hợp, không có clock và không giữ trạng thái.
 * - imm_o thay đổi sau trễ lan truyền tổ hợp của instr_i/imm_type_i.
 *
 * Quy tắc an toàn và góc biên:
 * - Bit 0 của immediate B/J luôn bằng 0 theo đặc tả ISA.
 * - IMM_NONE và mọi mã dành riêng/không xác định trả về 0, tránh latch
 *   và ngăn một immediate cũ bị tái sử dụng ngoài ý muốn.
 */
module eq_reference_rv32_imm_gen (
    // Mã lệnh RV32I 32 bit của lệnh đang xét.
    input  wire [31:0] instr_i,
    // Chọn dạng immediate theo RV32_IMM_* trong rv32_defs.vh.
    input  wire [2:0]  imm_type_i,

    // Immediate 32 bit: mở rộng dấu I/S/B/J; dạng U có 12 bit thấp bằng 0.
    output reg  [31:0] imm_o
);

    always @(*) begin
        case (imm_type_i)
            `EQ_REFERENCE_RV32_IMM_NONE: imm_o = 32'b0;

            // I[11:0] = instr[31:20], mở rộng dấu từ bit 31.
            `EQ_REFERENCE_RV32_IMM_I: begin
                imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            end

            // S[11:5] = instr[31:25], S[4:0] = instr[11:7].
            `EQ_REFERENCE_RV32_IMM_S: begin
                imm_o = {
                    {20{instr_i[31]}},
                    instr_i[31:25],
                    instr_i[11:7]
                };
            end

            // B[12|11|10:5|4:1|0] = instr[31|7|30:25|11:8|0].
            `EQ_REFERENCE_RV32_IMM_B: begin
                imm_o = {
                    {19{instr_i[31]}},
                    instr_i[31],
                    instr_i[7],
                    instr_i[30:25],
                    instr_i[11:8],
                    1'b0
                };
            end

            // U[31:12] lấy trực tiếp từ lệnh; U[11:0] bằng 0.
            `EQ_REFERENCE_RV32_IMM_U: begin
                imm_o = {instr_i[31:12], 12'b0};
            end

            // J[20|19:12|11|10:1|0] = instr[31|19:12|20|30:21|0].
            `EQ_REFERENCE_RV32_IMM_J: begin
                imm_o = {
                    {11{instr_i[31]}},
                    instr_i[31],
                    instr_i[19:12],
                    instr_i[20],
                    instr_i[30:21],
                    1'b0
                };
            end

            default: imm_o = 32'b0;
        endcase
    end

endmodule

`default_nettype wire
