`default_nettype none
`include "eq_reference_rv32_defs.vh"

// WB: commit thanh ghi, trace lệnh hoàn tất và chốt ngoại lệ chính xác.
// Cạnh lên thực hiện commit khi MEM/WB hợp lệ, không lỗi và core chưa halt.
// Trace có nghĩa trong chu kỳ ngay sau cạnh commit; trap/halt giữ tới reset.
// Lệnh lỗi không retire và không ghi rd. Reset đồng bộ, tích cực cao.
// Chi tiết trace/trap: docs/giao_tiep_rtl_vi.md, mục 6.
module eq_reference_rv32_wb_stage (
    // Cập nhật tại cạnh lên; reset đồng bộ, tích cực cao.
    input  wire         clk_i,
    input  wire         rst_i,

    // Lệnh MEM/WB và yêu cầu ghi rd; x0 không nhận ghi.
    input  wire         valid_i,
    input  wire         exc_valid_i,
    input  wire         reg_write_i,
    input  wire [4:0]   rd_addr_i,
    input  wire [31:0]  wb_data_i,

    // Thông tin lệnh để ghi trace hoặc trap; cause chỉ dùng khi exc_valid=1.
    input  wire [31:0]  pc_i,
    input  wire [31:0]  instr_i,
    input  wire [4:0]   exc_cause_i,

    // Cho phép ghi rd ở cạnh lên sau khi loại reset, bubble, lỗi, halt và x0.
    output wire         wb_regfile_we_o,

    // Lỗi hợp lệ tại WB: chặn lệnh trẻ hơn ngay trong chu kỳ trước khi chốt trap.
    output wire         wb_trap_event_o,

    // Trạng thái trap và metadata giữ tới reset. Trap do fetch không có mã lệnh
    // hợp lệ được core đưa vào với instr=0.
    output reg          halted_o,
    output reg          trap_valid_o,
    output reg  [4:0]   trap_cause_o,
    output reg  [31:0]  trap_pc_o,
    output reg  [31:0]  trap_instr_o,

    // Trace sau cạnh hoàn tất thành công; valid có thể cao nhiều chu kỳ liên tiếp.
    // PC/instr chỉ có nghĩa khi retire_valid=1.
    output reg          retire_valid_o,
    output reg  [31:0]  retire_pc_o,
    output reg  [31:0]  retire_instr_o,

    // Ghi thanh ghi của lệnh retire; rd_addr/data chỉ có nghĩa khi
    // retire_valid && retire_rd_we. Lệnh không ghi rd vẫn có thể retire.
    output reg          retire_rd_we_o,
    output reg  [4:0]   retire_rd_addr_o,
    output reg  [31:0]  retire_rd_data_o
);

    // Hai cửa ra kiến trúc loại trừ nhau: ghi rd cho lệnh tốt, trap cho lệnh lỗi.
    // wb_trap_event_o cũng chặn truy cập MEM trẻ hơn ngay trong chu kỳ báo lỗi.
    assign wb_regfile_we_o = !rst_i && valid_i && !exc_valid_i &&
                             reg_write_i && (rd_addr_i != 5'd0) && !halted_o;
    assign wb_trap_event_o = valid_i && exc_valid_i && !halted_o && !rst_i;

    // Reset xóa cả trap đã giữ và trace; ngoài reset, trap/halt chỉ có thể được đặt.
    always @(posedge clk_i) begin
        if (rst_i) begin
            halted_o         <= 1'b0;
            trap_valid_o     <= 1'b0;
            trap_cause_o     <= 5'b0;
            trap_pc_o        <= 32'b0;
            trap_instr_o     <= 32'b0;
            retire_valid_o   <= 1'b0;
            retire_pc_o      <= 32'b0;
            retire_instr_o   <= 32'b0;
            retire_rd_we_o   <= 1'b0;
            retire_rd_addr_o <= 5'b0;
            retire_rd_data_o <= 32'b0;
        end
        else begin
            // Mặc định không có lệnh retire; metadata cũ chỉ dùng khi valid=1.
            retire_valid_o <= 1'b0;
            retire_rd_we_o <= 1'b0;

            // Lệnh hợp lệ, không lỗi, chưa halt mới được retire. Lệnh không ghi rd
            // (kể cả store đã hoàn tất tại MEM) vẫn xuất trace hoàn tất.
            if (!halted_o && valid_i && !exc_valid_i) begin
                retire_valid_o   <= 1'b1;
                retire_pc_o      <= pc_i;
                retire_instr_o   <= instr_i;
                retire_rd_we_o   <= reg_write_i && (rd_addr_i != 5'd0);
                retire_rd_addr_o <= rd_addr_i;
                retire_rd_data_o <= wb_data_i;
            end

            // Lệnh lỗi không retire/ghi rd; chốt nguyên nhân và dừng đến reset.
            if (wb_trap_event_o) begin
                halted_o     <= 1'b1;
                trap_valid_o <= 1'b1;
                trap_cause_o <= exc_cause_i;
                trap_pc_o    <= pc_i;
                trap_instr_o <= instr_i;
            end
        end
    end

endmodule

`default_nettype wire
