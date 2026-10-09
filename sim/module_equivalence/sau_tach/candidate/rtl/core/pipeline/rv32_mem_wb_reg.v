`default_nettype none
`include "rv32_defs.vh"

// Thanh ghi MEM/WB: giữ kết quả hoặc ngoại lệ để WB hoàn tất lệnh.
// Ưu tiên: reset -> trap WB -> giữ khi halt -> MEM chờ -> nhận MEM.
// MEM chờ thì xóa valid vì lệnh WB cũ đã hoàn tất tại cạnh này.
// Ngoại lệ đã có ở EX/MEM ưu tiên hơn lỗi truy cập dữ liệu mới.
module rv32_mem_wb_reg (
    // Nhịp, reset và điều kiện giữ/hủy từ bộ điều khiển pipeline.
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        wb_trap_event_i,
    input  wire        halted_i,
    input  wire        mem_stall_i,
    input  wire        mem_fault_event_i,

    // Lệnh EX/MEM và dữ liệu đã chọn tại MEM; load_i chọn cause 5 hay 7.
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire [4:0]  rd_addr_i,
    input  wire        reg_write_i,
    input  wire        load_i,
    input  wire        exc_valid_i,
    input  wire [4:0]  exc_cause_i,
    input  wire [31:0] wb_data_i,

    // Trạng thái đã chốt; chỉ dùng payload khi valid_o=1.
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] instr_o,
    output reg  [4:0]  rd_addr_o,
    output reg         reg_write_o,
    output reg  [31:0] wb_data_o,
    output reg         exc_valid_o,
    output reg  [4:0]  exc_cause_o
);

    localparam [4:0] CAUSE_LOAD_ACCESS_FAULT = `RV32_CAUSE_LOAD_ACCESS_FAULT;
    localparam [4:0] CAUSE_STORE_ACCESS_FAULT = `RV32_CAUSE_STORE_ACCESS_FAULT;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_o       <= 1'b0;
            pc_o          <= 32'b0;
            instr_o       <= 32'b0;
            rd_addr_o     <= 5'b0;
            reg_write_o   <= 1'b0;
            wb_data_o     <= 32'b0;
            exc_valid_o   <= 1'b0;
            exc_cause_o   <= 5'b0;
        end
        else if (wb_trap_event_i) begin
            valid_o <= 1'b0;
        end
        else if (!halted_i) begin
            if (mem_stall_i) begin
                // Lệnh WB cũ đã commit ở cạnh này; không được commit lặp.
                valid_o <= 1'b0;
            end
            else begin
                valid_o      <= valid_i;
                pc_o         <= pc_i;
                instr_o      <= instr_i;
                rd_addr_o    <= rd_addr_i;
                reg_write_o  <= reg_write_i &&
                                !exc_valid_i &&
                                !mem_fault_event_i;
                wb_data_o    <= wb_data_i;
                exc_valid_o  <= exc_valid_i ||
                                mem_fault_event_i;
                if (exc_valid_i) begin
                    exc_cause_o <= exc_cause_i;
                end
                else if (load_i) begin
                    exc_cause_o <= CAUSE_LOAD_ACCESS_FAULT;
                end
                else begin
                    exc_cause_o <= CAUSE_STORE_ACCESS_FAULT;
                end
            end
        end
    end

endmodule

`default_nettype wire
