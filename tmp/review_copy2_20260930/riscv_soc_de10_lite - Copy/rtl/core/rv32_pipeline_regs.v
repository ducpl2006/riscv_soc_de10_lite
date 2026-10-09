`default_nettype none
`include "rv32_defs.vh"

// =============================================================================
// File        : rv32_pipeline_regs.v
// Chức năng   : Chứa các Thanh ghi đường ống (Pipeline Registers) cho core RV32I.
// Mô tả       : 
//   - Tách biệt logic lưu trữ trạng thái của luồng lệnh giữa các tầng:
//     ID/EX, EX/MEM, và MEM/WB.
//   - Quản lý luồng điều khiển bao gồm: Stall (dừng do hazard hoặc bộ nhớ) và 
//     Flush (hủy bỏ lệnh do phân nhánh sai hoặc có ngoại lệ/trap).
//   - Ưu tiên đồng bộ: Reset > Trap (từ WB) > Flush/Stall thông thường.
// =============================================================================


// =============================================================================
// Module      : rv32_idex_reg
// Chức năng   : Thanh ghi ngăn cách tầng Giải mã (ID) và tầng Thực thi (EX).
// =============================================================================
module rv32_idex_reg (
    input  wire        clk_i,
    input  wire        rst_i,
    
    // Tín hiệu điều khiển luồng (Control Flow)
    input  wire        trap_flush_i,      // Xóa khẩn cấp do ngoại lệ/trap từ tầng WB
    input  wire        stage_flush_i,     // Xóa lệnh do phân nhánh sai hoặc ngoại lệ từ MEM/EX
    input  wire        mem_stall_i,       // Dừng do giao tiếp dữ liệu ở MEM chưa xong
    input  wire        load_use_stall_i,  // Dừng do Hazard Load-Use từ ID

    // Trạng thái lệnh từ tầng ID (Inputs)
    input  wire        valid_id_i,        // Lệnh có hợp lệ không
    input  wire [31:0] pc_id_i,           // Program Counter của lệnh
    input  wire [31:0] instr_id_i,        // Mã lệnh 32-bit
    input  wire [4:0]  rs1_addr_id_i,     // Địa chỉ thanh ghi nguồn 1
    input  wire [4:0]  rs2_addr_id_i,     // Địa chỉ thanh ghi nguồn 2
    input  wire [4:0]  rd_addr_id_i,      // Địa chỉ thanh ghi đích
    input  wire [31:0] rs1_data_id_i,     // Dữ liệu thanh ghi nguồn 1
    input  wire [31:0] rs2_data_id_i,     // Dữ liệu thanh ghi nguồn 2
    input  wire [31:0] imm_id_i,          // Giá trị Immediate đã mở rộng
    input  wire [2:0]  funct3_id_i,       // Mã funct3 (dùng cho phân nhánh/load/store)
    input  wire [3:0]  alu_op_id_i,       // Mã phép toán ALU
    input  wire [1:0]  op_a_sel_id_i,     // Mux chọn toán hạng A cho ALU
    input  wire        op_b_imm_id_i,     // Mux chọn toán hạng B cho ALU (1: imm, 0: rs2)
    input  wire        reg_write_id_i,    // Cờ báo lệnh này sẽ ghi vào Register File
    input  wire [1:0]  wb_sel_id_i,       // Mux chọn kết quả ghi về (ALU / Load / PC+4)
    input  wire        branch_id_i,       // Cờ báo lệnh phân nhánh có điều kiện
    input  wire        jal_id_i,          // Cờ báo lệnh JAL
    input  wire        jalr_id_i,         // Cờ báo lệnh JALR
    input  wire        load_id_i,         // Cờ báo lệnh đọc bộ nhớ (Load)
    input  wire        store_id_i,        // Cờ báo lệnh ghi bộ nhớ (Store)
    input  wire        exc_valid_id_i,    // Cờ báo có ngoại lệ phát sinh tại ID (ví dụ: Illegal Instruction)
    input  wire [4:0]  exc_cause_id_i,    // Mã nguyên nhân ngoại lệ tại ID

    // Dữ liệu chuyển tiếp (Forwarding) cập nhật liên tục khi MEM stall
    input  wire [31:0] rs1_fwd_i,         // Dữ liệu rs1 đã được chuyển tiếp mới nhất
    input  wire [31:0] rs2_fwd_i,         // Dữ liệu rs2 đã được chuyển tiếp mới nhất

    // Trạng thái lệnh xuất ra tầng EX (Outputs)
    output reg         valid_ex_o,
    output reg  [31:0] pc_ex_o,
    output reg  [31:0] instr_ex_o,
    output reg  [31:0] pc4_ex_o,          // Mặc định lưu sẵn PC+4 cho lệnh JAL/JALR
    output reg  [4:0]  rs1_addr_ex_o,
    output reg  [4:0]  rs2_addr_ex_o,
    output reg  [4:0]  rd_addr_ex_o,
    output reg  [31:0] rs1_data_ex_o,
    output reg  [31:0] rs2_data_ex_o,
    output reg  [31:0] imm_ex_o,
    output reg  [2:0]  funct3_ex_o,
    output reg  [3:0]  alu_op_ex_o,
    output reg  [1:0]  op_a_sel_ex_o,
    output reg         op_b_imm_ex_o,
    output reg         reg_write_ex_o,
    output reg  [1:0]  wb_sel_ex_o,
    output reg         branch_ex_o,
    output reg         jal_ex_o,
    output reg         jalr_ex_o,
    output reg         load_ex_o,
    output reg         store_ex_o,
    output reg         exc_valid_ex_o,
    output reg  [4:0]  exc_cause_ex_o
);
    localparam [1:0] OP_A_RS1 = `RV32_OP_A_RS1;
    localparam [1:0] WB_ALU   = `RV32_WB_ALU;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_ex_o      <= 1'b0;
            pc_ex_o         <= 32'b0;
            instr_ex_o      <= 32'b0;
            pc4_ex_o        <= 32'b0;
            rs1_addr_ex_o   <= 5'b0;
            rs2_addr_ex_o   <= 5'b0;
            rd_addr_ex_o    <= 5'b0;
            rs1_data_ex_o   <= 32'b0;
            rs2_data_ex_o   <= 32'b0;
            imm_ex_o        <= 32'b0;
            funct3_ex_o     <= 3'b0;
            alu_op_ex_o     <= 4'b0;
            op_a_sel_ex_o   <= OP_A_RS1;
            op_b_imm_ex_o   <= 1'b0;
            reg_write_ex_o  <= 1'b0;
            wb_sel_ex_o     <= WB_ALU;
            branch_ex_o     <= 1'b0;
            jal_ex_o        <= 1'b0;
            jalr_ex_o       <= 1'b0;
            load_ex_o       <= 1'b0;
            store_ex_o      <= 1'b0;
            exc_valid_ex_o  <= 1'b0;
            exc_cause_ex_o  <= 5'b0;
            
        end else if (trap_flush_i) begin
            // Xóa rỗng slot hiện tại nếu có Trap tổng toàn hệ thống
            valid_ex_o <= 1'b0;
            
        end else if (stage_flush_i) begin
            // Xóa rỗng do lệnh già hơn đổi nhánh hoặc gặp lỗi (không chạy lệnh đi sau nữa)
            valid_ex_o <= 1'b0;
            
        end else if (mem_stall_i) begin
            // ĐẶC BIỆT: Khi MEM bị treo (stall), kết quả ở tầng WB có thể vẫn đang được ghi về.
            // Để đảm bảo tầng EX không bị lỡ mất dữ liệu mới từ mạng Forwarding, ta phải 
            // cập nhật dữ liệu rs1/rs2 thay vì chỉ giữ nguyên (hold) toàn bộ trạng thái.
            rs1_data_ex_o <= rs1_fwd_i;
            rs2_data_ex_o <= rs2_fwd_i;
            
        end else if (load_use_stall_i) begin
            // Chèn một "bong bóng" (bubble / NOP) khi gặp Hazard Load-Use
            valid_ex_o <= 1'b0;
            
        end else begin
            // Di chuyển bình thường (Normal Pipeline Advance)
            valid_ex_o      <= valid_id_i;
            pc_ex_o         <= pc_id_i;
            instr_ex_o      <= instr_id_i;
            pc4_ex_o        <= pc_id_i + 32'd4;
            rs1_addr_ex_o   <= rs1_addr_id_i;
            rs2_addr_ex_o   <= rs2_addr_id_i;
            rd_addr_ex_o    <= rd_addr_id_i;
            rs1_data_ex_o   <= rs1_data_id_i;
            rs2_data_ex_o   <= rs2_data_id_i;
            imm_ex_o        <= imm_id_i;
            funct3_ex_o     <= funct3_id_i;
            alu_op_ex_o     <= alu_op_id_i;
            op_a_sel_ex_o   <= op_a_sel_id_i;
            op_b_imm_ex_o   <= op_b_imm_id_i;
            
            // Nếu có ngoại lệ từ ID, khóa các tác dụng phụ của lệnh (không ghi reg/mem/nhánh)
            reg_write_ex_o  <= reg_write_id_i && !exc_valid_id_i;
            wb_sel_ex_o     <= wb_sel_id_i;
            branch_ex_o     <= branch_id_i && !exc_valid_id_i;
            jal_ex_o        <= jal_id_i && !exc_valid_id_i;
            jalr_ex_o       <= jalr_id_i && !exc_valid_id_i;
            load_ex_o       <= load_id_i && !exc_valid_id_i;
            store_ex_o      <= store_id_i && !exc_valid_id_i;
            
            exc_valid_ex_o  <= exc_valid_id_i;
            exc_cause_ex_o  <= exc_cause_id_i;
        end
    end
endmodule


// =============================================================================
// Module      : rv32_exmem_reg
// Chức năng   : Thanh ghi ngăn cách tầng Thực thi (EX) và tầng Bộ nhớ (MEM).
// =============================================================================
module rv32_exmem_reg (
    input  wire        clk_i,
    input  wire        rst_i,
    
    // Tín hiệu điều khiển
    input  wire        trap_flush_i,      // Xóa khẩn cấp do Trap tổng
    input  wire        stage_flush_i,     // Xóa do lệnh tại MEM bị lỗi dữ liệu
    input  wire        mem_stall_i,       // Treo do MEM chưa giao tiếp xong

    // Trạng thái lệnh từ tầng EX (Inputs)
    input  wire        valid_ex_i,
    input  wire [31:0] pc_ex_i,
    input  wire [31:0] instr_ex_i,
    input  wire [31:0] pc4_ex_i,
    input  wire [4:0]  rd_addr_ex_i,
    input  wire        reg_write_ex_i,
    input  wire [1:0]  wb_sel_ex_i,
    input  wire [31:0] alu_result_ex_i,   // Kết quả ALU (cũng là Địa chỉ MEM)
    input  wire [31:0] store_data_ex_i,   // Dữ liệu cần ghi xuống MEM
    input  wire [2:0]  funct3_ex_i,
    input  wire        load_ex_i,
    input  wire        store_ex_i,
    input  wire        exc_valid_ex_i,
    input  wire [4:0]  exc_cause_ex_i,
    
    // Ngoại lệ mới phát sinh tại tầng EX (ví dụ: Nhảy tới địa chỉ lệch hàng)
    input  wire        ex_fault_raw_i,
    input  wire [4:0]  ex_fault_cause_i,

    // Trạng thái lệnh xuất ra tầng MEM (Outputs)
    output reg         valid_mem_o,
    output reg  [31:0] pc_mem_o,
    output reg  [31:0] instr_mem_o,
    output reg  [31:0] pc4_mem_o,
    output reg  [4:0]  rd_addr_mem_o,
    output reg         reg_write_mem_o,
    output reg  [1:0]  wb_sel_mem_o,
    output reg  [31:0] alu_result_mem_o,
    output reg  [31:0] store_data_mem_o,
    output reg  [2:0]  funct3_mem_o,
    output reg         load_mem_o,
    output reg         store_mem_o,
    output reg         exc_valid_mem_o,
    output reg  [4:0]  exc_cause_mem_o
);
    localparam [1:0] WB_ALU = `RV32_WB_ALU;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_mem_o       <= 1'b0;
            pc_mem_o          <= 32'b0;
            instr_mem_o       <= 32'b0;
            pc4_mem_o         <= 32'b0;
            rd_addr_mem_o     <= 5'b0;
            reg_write_mem_o   <= 1'b0;
            wb_sel_mem_o      <= WB_ALU;
            alu_result_mem_o  <= 32'b0;
            store_data_mem_o  <= 32'b0;
            funct3_mem_o      <= 3'b0;
            load_mem_o        <= 1'b0;
            store_mem_o       <= 1'b0;
            exc_valid_mem_o   <= 1'b0;
            exc_cause_mem_o   <= 5'b0;
            
        end else if (trap_flush_i) begin
            // Xóa khẩn cấp do Trap tổng
            valid_mem_o <= 1'b0;
            
        end else if (stage_flush_i) begin
            // Xóa khi lệnh già hơn ở MEM gây ra lỗi (MEM Fault)
            valid_mem_o <= 1'b0;
            
        end else if (!mem_stall_i) begin
            // Di chuyển bình thường nếu MEM không bị treo
            valid_mem_o      <= valid_ex_i;
            pc_mem_o         <= pc_ex_i;
            instr_mem_o      <= instr_ex_i;
            pc4_mem_o        <= pc4_ex_i;
            rd_addr_mem_o    <= rd_addr_ex_i;
            wb_sel_mem_o     <= wb_sel_ex_i;
            alu_result_mem_o <= alu_result_ex_i;
            store_data_mem_o <= store_data_ex_i;
            funct3_mem_o     <= funct3_ex_i;
            
            // Khóa tác dụng phụ nếu bản thân lệnh đang mang lỗi hoặc vừa phát sinh lỗi tại EX
            reg_write_mem_o  <= reg_write_ex_i && !exc_valid_ex_i && !ex_fault_raw_i;
            load_mem_o       <= load_ex_i && !exc_valid_ex_i && !ex_fault_raw_i;
            store_mem_o      <= store_ex_i && !exc_valid_ex_i && !ex_fault_raw_i;
            
            // Gộp cờ lỗi: Nếu lệnh trước đó đã có lỗi thì giữ nguyên, không thì ghi nhận lỗi mới tại EX
            exc_valid_mem_o  <= exc_valid_ex_i || ex_fault_raw_i;
            exc_cause_mem_o  <= exc_valid_ex_i ? exc_cause_ex_i : ex_fault_cause_i;
        end
    end
endmodule


// =============================================================================
// Module      : rv32_memwb_reg
// Chức năng   : Thanh ghi ngăn cách tầng Bộ nhớ (MEM) và tầng Ghi lại (WB).
// =============================================================================
module rv32_memwb_reg (
    input  wire        clk_i,
    input  wire        rst_i,
    
    // Tín hiệu điều khiển
    input  wire        trap_flush_i,      // Xóa khẩn cấp do Trap tổng
    input  wire        mem_stall_i,       // Treo do MEM chưa giao tiếp xong

    // Trạng thái lệnh từ tầng MEM (Inputs)
    input  wire        valid_mem_i,
    input  wire [31:0] pc_mem_i,
    input  wire [31:0] instr_mem_i,
    input  wire [4:0]  rd_addr_mem_i,
    input  wire        reg_write_mem_i,
    input  wire [31:0] mem_wb_data_i,     // Dữ liệu sẽ được ghi về Register File
    input  wire        exc_valid_mem_i,
    input  wire [4:0]  exc_cause_mem_i,
    input  wire        load_mem_i,        // Cờ báo lệnh là Load (dùng để gán mã ngoại lệ)
    
    // Sự kiện lỗi tại giao tiếp dữ liệu MEM (ví dụ Bus Error)
    input  wire        mem_fault_event_i, 

    // Trạng thái lệnh xuất ra tầng WB (Outputs)
    output reg         valid_wb_o,
    output reg  [31:0] pc_wb_o,
    output reg  [31:0] instr_wb_o,
    output reg  [4:0]  rd_addr_wb_o,
    output reg         reg_write_wb_o,
    output reg  [31:0] wb_data_wb_o,
    output reg         exc_valid_wb_o,
    output reg  [4:0]  exc_cause_wb_o
);
    localparam [4:0] CAUSE_LOAD_ACCESS_FAULT = `RV32_CAUSE_LOAD_ACCESS_FAULT;
    localparam [4:0] CAUSE_STORE_ACCESS_FAULT = `RV32_CAUSE_STORE_ACCESS_FAULT;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_wb_o      <= 1'b0;
            pc_wb_o         <= 32'b0;
            instr_wb_o      <= 32'b0;
            rd_addr_wb_o    <= 5'b0;
            reg_write_wb_o  <= 1'b0;
            wb_data_wb_o    <= 32'b0;
            exc_valid_wb_o  <= 1'b0;
            exc_cause_wb_o  <= 5'b0;
            
        end else if (trap_flush_i) begin
            // Xóa khẩn cấp do Trap tổng
            valid_wb_o <= 1'b0;
            
        end else if (mem_stall_i) begin
            // Lệnh tại WB đã hoàn tất ghi (commit) trong chu kỳ này.
            // Nếu MEM vẫn bị treo, không được lặp lại việc ghi (tránh ghi 2 lần hoặc lỗi trace).
            valid_wb_o <= 1'b0;
            
        end else begin
            // Di chuyển lệnh từ MEM sang WB để commit
            valid_wb_o      <= valid_mem_i;
            pc_wb_o         <= pc_mem_i;
            instr_wb_o      <= instr_mem_i;
            rd_addr_wb_o    <= rd_addr_mem_i;
            wb_data_wb_o    <= mem_wb_data_i;
            
            // Chỉ cho phép ghi Register File nếu lệnh không mang bất kỳ ngoại lệ/lỗi nào
            reg_write_wb_o  <= reg_write_mem_i && !exc_valid_mem_i && !mem_fault_event_i;
            
            // Gộp cờ lỗi từ MEM Bus
            exc_valid_wb_o  <= exc_valid_mem_i || mem_fault_event_i;
            
            if (exc_valid_mem_i) begin
                exc_cause_wb_o <= exc_cause_mem_i;
            end else if (load_mem_i) begin
                exc_cause_wb_o <= CAUSE_LOAD_ACCESS_FAULT;
            end else begin
                exc_cause_wb_o <= CAUSE_STORE_ACCESS_FAULT;
            end
        end
    end
endmodule

`default_nettype wire
