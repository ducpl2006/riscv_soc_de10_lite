`default_nettype none

/*
 * Khối quyết định nhánh có điều kiện RV32I
 *
 * Đặc tả giao tiếp:
 * - branch_en_i = 1 khi lệnh hiện tại là một lệnh branch hợp lệ.
 * - funct3_i dùng mã chuẩn RV32I: 000 BEQ, 001 BNE, 100 BLT,
 *   101 BGE, 110 BLTU, 111 BGEU. Hai mã 010/011 là dành riêng.
 * - rs1_data_i và rs2_data_i là hai toán hạng cần so sánh.
 * - branch_taken_o = 1 duy nhất khi branch được cho phép và điều kiện đúng.
 *
 * Thời gian:
 * - Khối hoàn toàn tổ hợp; không tính địa chỉ đích và không giữ trạng thái.
 * - Trong pipeline 5 tầng, khối thường đặt ở EX; PC/target được tính ở
 *   datapath khác từ PC + immediate B.
 *
 * Quy tắc an toàn và góc biên:
 * - BLT/BGE diễn giải toán hạng là số bù hai có dấu.
 * - BLTU/BGEU diễn giải cùng mẫu bit là số không dấu.
 * - Khi branch_en_i = 0 hoặc funct3 dành riêng/không xác định, đầu ra = 0.
 */
module eq_reference_rv32_branch_unit (
    // Cho phép so sánh cho lệnh branch hợp lệ; bằng 0 thì không lấy nhánh.
    input  wire        branch_en_i,
    // 000 BEQ, 001 BNE, 100 BLT, 101 BGE, 110 BLTU, 111 BGEU.
    input  wire [2:0]  funct3_i,
    // Toán hạng so sánh rs1 đã forwarding tại EX.
    input  wire [31:0] rs1_data_i,
    // Toán hạng so sánh rs2 đã forwarding tại EX.
    input  wire [31:0] rs2_data_i,

    // 1 khi branch_en=1 và điều kiện đúng; không tính địa chỉ đích.
    output reg         branch_taken_o
);

    localparam [2:0]
        BR_BEQ  = 3'b000,
        BR_BNE  = 3'b001,
        BR_BLT  = 3'b100,
        BR_BGE  = 3'b101,
        BR_BLTU = 3'b110,
        BR_BGEU = 3'b111;

    always @(*) begin
        branch_taken_o = 1'b0;

        if (branch_en_i) begin
            case (funct3_i)
                BR_BEQ: begin
                    branch_taken_o = (rs1_data_i == rs2_data_i);
                end

                BR_BNE: begin
                    branch_taken_o = (rs1_data_i != rs2_data_i);
                end

                BR_BLT: begin
                    branch_taken_o =
                        ($signed(rs1_data_i) < $signed(rs2_data_i));
                end

                BR_BGE: begin
                    branch_taken_o =
                        ($signed(rs1_data_i) >= $signed(rs2_data_i));
                end

                BR_BLTU: begin
                    branch_taken_o = (rs1_data_i < rs2_data_i);
                end

                BR_BGEU: begin
                    branch_taken_o = (rs1_data_i >= rs2_data_i);
                end

                default: branch_taken_o = 1'b0;
            endcase
        end
    end

endmodule

`default_nettype wire
