`default_nettype none
`include "rv32_defs.vh"

// Thanh ghi ID/EX: giữ lệnh và điều khiển để tầng EX sử dụng.
// Ưu tiên: reset -> trap WB -> giữ khi halt -> hủy do MEM/EX ->
// MEM chờ -> load-use -> nhận ID. Hủy chỉ xóa valid, giữ payload.
// Riêng khi MEM chờ, vẫn chốt hai toán hạng đã chuyển tiếp; WB có thể
// hoàn tất và mất valid trong lúc lệnh này còn đứng tại EX.
module rv32_id_ex_reg (
    // Nhịp, reset và điều kiện giữ/hủy từ bộ điều khiển pipeline.
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        wb_trap_event_i,
    input  wire        halted_i,
    input  wire        mem_stall_i,
    input  wire        mem_fault_event_i,
    input  wire        ex_fault_event_i,
    input  wire        ex_redirect_event_i,
    input  wire        load_use_stall_i,

    // Lệnh tại ID: dữ liệu đọc thanh ghi, giải mã và ngoại lệ đã chọn.
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire [4:0]  rs1_addr_i,
    input  wire [4:0]  rs2_addr_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [2:0]  funct3_i,
    input  wire [31:0] rs1_data_i,
    input  wire [31:0] rs2_data_i,
    input  wire [31:0] imm_i,
    input  wire [3:0]  alu_op_i,
    input  wire [1:0]  op_a_sel_i,
    input  wire        op_b_imm_i,
    input  wire        reg_write_i,
    input  wire [1:0]  wb_sel_i,
    input  wire        branch_i,
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        load_i,
    input  wire        store_i,
    input  wire        exc_valid_i,
    input  wire [4:0]  exc_cause_i,

    // Toán hạng từ EX quay lại khi MEM chờ; giữ dữ liệu trước khi WB rời tầng.
    input  wire [31:0] forwarded_rs1_i,
    input  wire [31:0] forwarded_rs2_i,

    // Trạng thái đã chốt; chỉ dùng payload khi valid_o=1.
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] instr_o,
    output reg  [31:0] pc4_o,
    output reg  [4:0]  rs1_addr_o,
    output reg  [4:0]  rs2_addr_o,
    output reg  [4:0]  rd_addr_o,
    output reg  [31:0] rs1_data_o,
    output reg  [31:0] rs2_data_o,
    output reg  [31:0] imm_o,
    output reg  [2:0]  funct3_o,
    output reg  [3:0]  alu_op_o,
    output reg  [1:0]  op_a_sel_o,
    output reg         op_b_imm_o,
    output reg         reg_write_o,
    output reg  [1:0]  wb_sel_o,
    output reg         branch_o,
    output reg         jal_o,
    output reg         jalr_o,
    output reg         load_o,
    output reg         store_o,
    output reg         exc_valid_o,
    output reg  [4:0]  exc_cause_o
);

    localparam [1:0] OP_A_RS1 = `RV32_OP_A_RS1;
    localparam [1:0] WB_ALU = `RV32_WB_ALU;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_o        <= 1'b0;
            pc_o           <= 32'b0;
            instr_o        <= 32'b0;
            pc4_o          <= 32'b0;
            rs1_addr_o     <= 5'b0;
            rs2_addr_o     <= 5'b0;
            rd_addr_o      <= 5'b0;
            rs1_data_o     <= 32'b0;
            rs2_data_o     <= 32'b0;
            imm_o          <= 32'b0;
            funct3_o       <= 3'b0;
            alu_op_o       <= 4'b0;
            op_a_sel_o     <= OP_A_RS1;
            op_b_imm_o     <= 1'b0;
            reg_write_o    <= 1'b0;
            wb_sel_o       <= WB_ALU;
            branch_o       <= 1'b0;
            jal_o          <= 1'b0;
            jalr_o         <= 1'b0;
            load_o         <= 1'b0;
            store_o        <= 1'b0;
            exc_valid_o    <= 1'b0;
            exc_cause_o    <= 5'b0;
        end
        else if (wb_trap_event_i) begin
            valid_o <= 1'b0;
        end
        else if (!halted_i) begin
            if (mem_fault_event_i || ex_fault_event_i || ex_redirect_event_i) begin
                valid_o <= 1'b0;
            end
            else if (mem_stall_i) begin
                // WB có thể hoàn tất trong lúc MEM đang chờ. Lưu toán hạng
                // đã chuyển tiếp để lệnh ở EX không mất dữ liệu khi valid
                // của MEM/WB bị xóa. Các trường ID/EX khác vẫn giữ nguyên.
                rs1_data_o <= forwarded_rs1_i;
                rs2_data_o <= forwarded_rs2_i;
            end
            else if (load_use_stall_i) begin
                valid_o <= 1'b0;
            end
            else begin
                valid_o      <= valid_i;
                pc_o         <= pc_i;
                instr_o      <= instr_i;
                pc4_o        <= pc_i + 32'd4;
                rs1_addr_o   <= rs1_addr_i;
                rs2_addr_o   <= rs2_addr_i;
                rd_addr_o    <= rd_addr_i;
                rs1_data_o   <= rs1_data_i;
                rs2_data_o   <= rs2_data_i;
                imm_o        <= imm_i;
                funct3_o     <= funct3_i;
                alu_op_o     <= alu_op_i;
                op_a_sel_o   <= op_a_sel_i;
                op_b_imm_o   <= op_b_imm_i;
                reg_write_o  <= reg_write_i && !exc_valid_i;
                wb_sel_o     <= wb_sel_i;
                branch_o     <= branch_i && !exc_valid_i;
                jal_o        <= jal_i && !exc_valid_i;
                jalr_o       <= jalr_i && !exc_valid_i;
                load_o       <= load_i && !exc_valid_i;
                store_o      <= store_i && !exc_valid_i;
                exc_valid_o  <= exc_valid_i;
                exc_cause_o  <= exc_cause_i;
            end
        end
    end

endmodule

`default_nettype wire
