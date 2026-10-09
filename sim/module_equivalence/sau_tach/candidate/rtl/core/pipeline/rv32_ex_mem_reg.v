`default_nettype none
`include "rv32_defs.vh"

// Thanh ghi EX/MEM: giữ kết quả EX trong suốt giao dịch dữ liệu.
// Ưu tiên: reset -> trap WB -> giữ khi halt -> lỗi MEM -> MEM chờ -> nhận EX.
// Lỗi MEM hủy lệnh trẻ bằng valid=0; khi MEM chờ thì giữ toàn bộ payload.
// Khi nhận EX, dùng fault_raw để chặn ghi rd/load/store của lệnh lỗi.
module rv32_ex_mem_reg (
    // Nhịp, reset và điều kiện giữ/hủy từ bộ điều khiển pipeline.
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        wb_trap_event_i,
    input  wire        halted_i,
    input  wire        mem_stall_i,
    input  wire        mem_fault_event_i,

    // Lệnh ID/EX và kết quả EX; store_data đã qua chuyển tiếp toán hạng.
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire [31:0] pc4_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [2:0]  funct3_i,
    input  wire        reg_write_i,
    input  wire [1:0]  wb_sel_i,
    input  wire        load_i,
    input  wire        store_i,
    input  wire        exc_valid_i,
    input  wire [4:0]  exc_cause_i,
    input  wire [31:0] store_data_i,
    input  wire [31:0] alu_result_i,
    input  wire        fault_raw_i,
    input  wire [4:0]  fault_cause_i,

    // Trạng thái đã chốt; chỉ dùng payload khi valid_o=1.
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] instr_o,
    output reg  [31:0] pc4_o,
    output reg  [4:0]  rd_addr_o,
    output reg         reg_write_o,
    output reg  [1:0]  wb_sel_o,
    output reg  [31:0] alu_result_o,
    output reg  [31:0] store_data_o,
    output reg  [2:0]  funct3_o,
    output reg         load_o,
    output reg         store_o,
    output reg         exc_valid_o,
    output reg  [4:0]  exc_cause_o
);

    localparam [1:0] WB_ALU = `RV32_WB_ALU;
    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_o       <= 1'b0;
            pc_o          <= 32'b0;
            instr_o       <= 32'b0;
            pc4_o         <= 32'b0;
            rd_addr_o     <= 5'b0;
            reg_write_o   <= 1'b0;
            wb_sel_o      <= WB_ALU;
            alu_result_o  <= 32'b0;
            store_data_o  <= 32'b0;
            funct3_o      <= 3'b0;
            load_o        <= 1'b0;
            store_o       <= 1'b0;
            exc_valid_o   <= 1'b0;
            exc_cause_o   <= 5'b0;
        end
        else if (wb_trap_event_i) begin
            valid_o <= 1'b0;
        end
        else if (!halted_i) begin
            if (mem_fault_event_i) begin
                // MEM fault thuộc lệnh già hơn; hủy mọi kết quả từ EX.
                valid_o <= 1'b0;
            end
            else if (!mem_stall_i) begin
                valid_o      <= valid_i;
                pc_o         <= pc_i;
                instr_o      <= instr_i;
                pc4_o        <= pc4_i;
                rd_addr_o    <= rd_addr_i;
                reg_write_o  <= reg_write_i &&
                                !exc_valid_i &&
                                !fault_raw_i;
                wb_sel_o     <= wb_sel_i;
                alu_result_o <= alu_result_i;
                store_data_o <= store_data_i;
                funct3_o     <= funct3_i;
                load_o       <= load_i &&
                                !exc_valid_i &&
                                !fault_raw_i;
                store_o      <= store_i &&
                                !exc_valid_i &&
                                !fault_raw_i;
                exc_valid_o  <= exc_valid_i || fault_raw_i;
                exc_cause_o  <= exc_valid_i
                                ? exc_cause_i
                                : fault_cause_i;
            end
        end
    end

endmodule

`default_nettype wire
