`default_nettype none
`include "rv32_defs.vh"

// ID: giải mã RV32I, tạo immediate và đọc thanh ghi có bypass từ WB.
// Giải mã tổ hợp; register file ghi/reset tại cạnh lên. Payload đầu vào chỉ
// được core sử dụng khi IF/ID hợp lệ; decode_exc không tự tạo tác dụng phụ.
// Chi tiết ranh giới pipeline: docs/giao_tiep_rtl_vi.md, mục 5.
module rv32_id_stage (
    // Tập thanh ghi ghi/reset tại cạnh lên; reset đồng bộ, tích cực cao.
    input  wire         clk_i,
    input  wire         rst_i,

    // Lệnh IF/ID và ngoại lệ fetch đi kèm; ngoại lệ này ưu tiên lỗi giải mã mới.
    input  wire [31:0]  instr_i,
    input  wire         exc_valid_i,
    input  wire [4:0]   exc_cause_i,

    // Cổng ghi từ WB đã xét valid, ngoại lệ, halt, reset và x0. Dữ liệu này
    // cũng bypass trực tiếp tới nguồn đọc cùng địa chỉ trong chu kỳ WB/ID.
    input  wire         wb_regfile_we_i,
    input  wire [4:0]   memwb_rd_addr_i,
    input  wire [31:0]  memwb_wb_data_i,

    // Các trường thanh ghi và funct3 trích trực tiếp từ mã lệnh; uses_rs*
    // bên dưới xác định nguồn nào thật sự được dùng.
    output wire [4:0]   rs1_addr_o,
    output wire [4:0]   rs2_addr_o,
    output wire [4:0]   rd_addr_o,
    output wire [2:0]   funct3_o,

    // Dữ liệu đọc sau bypass WB→ID; x0 luôn bằng 0.
    output wire [31:0]  rs1_data_o,
    output wire [31:0]  rs2_data_o,

    // Immediate mở rộng 32 bit; điều khiển ALU dùng các mã RV32_* trong defs.
    // A chọn rs1/PC/0; B chọn immediate nếu op_b_imm=1, ngược lại chọn rs2.
    output wire [31:0]  imm_o,
    output wire [3:0]   alu_op_o,
    output wire [1:0]   op_a_sel_o,
    output wire         op_b_imm_o,

    // Điều khiển ghi về và loại lệnh; core khóa tác dụng phụ khi có ngoại lệ.
    // wb_sel chọn ALU/load/PC+4; branch chỉ đánh dấu nhánh, chưa quyết định lấy.
    output wire         reg_write_o,
    output wire [1:0]   wb_sel_o,
    output wire         branch_o,
    output wire         jal_o,
    output wire         jalr_o,
    output wire         load_o,
    output wire         store_o,

    // Cờ nguồn thực sự được đọc; dùng để tránh hazard do trường bit không sử dụng.
    output wire         uses_rs1_o,
    output wire         uses_rs2_o,

    // Lỗi giải mã mới chưa xét valid IF/ID; any_exc gộp thêm lỗi fetch,
    // với cause của fetch được giữ nguyên nếu đã có ngoại lệ đi kèm.
    output reg          decode_exc_o,
    output wire         any_exc_o,
    output wire [4:0]   any_exc_cause_o
);

    localparam [4:0] CAUSE_ILLEGAL_INSTRUCTION = `RV32_CAUSE_ILLEGAL_INSTRUCTION;
    localparam [4:0] CAUSE_BREAKPOINT          = `RV32_CAUSE_BREAKPOINT;
    localparam [4:0] CAUSE_ECALL_MMODE         = `RV32_CAUSE_ECALL_MMODE;

    // Giải mã loại immediate và các lệnh hệ thống; FENCE hợp lệ là NOP
    // trong core thực thi theo thứ tự hiện tại, không tạo ngoại lệ ID.
    wire [2:0] id_imm_type;
    wire       id_fence;
    wire       id_ecall;
    wire       id_ebreak;
    wire       id_illegal;

    assign rs1_addr_o = instr_i[19:15];
    assign rs2_addr_o = instr_i[24:20];
    assign rd_addr_o  = instr_i[11:7];
    assign funct3_o   = instr_i[14:12];

    rv32_decoder u_decoder (
        .instr_i       (instr_i),
        .alu_op_o      (alu_op_o),
        .imm_type_o    (id_imm_type),
        .op_a_sel_o    (op_a_sel_o),
        .op_b_imm_o    (op_b_imm_o),
        .reg_write_o   (reg_write_o),
        .wb_sel_o      (wb_sel_o),
        .branch_o      (branch_o),
        .jal_o         (jal_o),
        .jalr_o        (jalr_o),
        .load_o        (load_o),
        .store_o       (store_o),
        .fence_o       (id_fence),
        .ecall_o       (id_ecall),
        .ebreak_o      (id_ebreak),
        .illegal_o     (id_illegal),
        .uses_rs1_o    (uses_rs1_o),
        .uses_rs2_o    (uses_rs2_o)
    );

    rv32_imm_gen u_imm_gen (
        .instr_i    (instr_i),
        .imm_type_i (id_imm_type),
        .imm_o      (imm_o)
    );

    // Regfile ưu tiên x0, rồi bypass WB→ID, rồi giá trị đã lưu. Bypass trả
    // ngay dữ liệu WB khi trùng nguồn, không cần chờ cạnh ghi thanh ghi.
    rv32_regfile u_regfile (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .rs1_addr_i (rs1_addr_o),
        .rs2_addr_i (rs2_addr_o),
        .rs1_data_o (rs1_data_o),
        .rs2_data_o (rs2_data_o),
        .rd_we_i    (wb_regfile_we_i),
        .rd_addr_i  (memwb_rd_addr_i),
        .rd_data_i  (memwb_wb_data_i)
    );

    // Lỗi giải mã theo thứ tự: mã lệnh không hợp lệ, EBREAK, ECALL.
    // Cause chỉ dùng khi decode_exc=1 và chưa có ngoại lệ fetch đi kèm.
    reg [4:0]  id_decode_exc_cause;
    always @(*) begin
        decode_exc_o       = 1'b0;
        id_decode_exc_cause = CAUSE_ILLEGAL_INSTRUCTION;
        if (id_illegal) begin
            decode_exc_o       = 1'b1;
            id_decode_exc_cause = CAUSE_ILLEGAL_INSTRUCTION;
        end
        else if (id_ebreak) begin
            decode_exc_o       = 1'b1;
            id_decode_exc_cause = CAUSE_BREAKPOINT;
        end
        else if (id_ecall) begin
            decode_exc_o       = 1'b1;
            id_decode_exc_cause = CAUSE_ECALL_MMODE;
        end
    end

    // Giữ cause fetch nếu đã có; core đưa ngoại lệ theo lệnh qua các tầng
    // và khóa tác dụng phụ, thay vì chốt trap ngay tại ID.
    assign any_exc_o = exc_valid_i || decode_exc_o;
    assign any_exc_cause_o = exc_valid_i
                            ? exc_cause_i
                            : id_decode_exc_cause;

endmodule

`default_nettype wire
