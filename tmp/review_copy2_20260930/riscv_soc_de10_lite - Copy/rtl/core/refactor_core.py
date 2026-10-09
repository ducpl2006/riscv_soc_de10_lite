import re

def refactor_core(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Rename signals
    content = re.sub(r'\bifid_([a-zA-Z0-9_]+)_q\b', r'\1_id', content)
    content = re.sub(r'\bidex_([a-zA-Z0-9_]+)_q\b', r'\1_ex', content)
    content = re.sub(r'\bexmem_([a-zA-Z0-9_]+)_q\b', r'\1_mem', content)
    content = re.sub(r'\bmemwb_([a-zA-Z0-9_]+)_q\b', r'\1_wb', content)

    # 2. Change 'reg' to 'wire' for the pipeline registers
    # Find the block from "// 1. Trạng thái pipeline do core giữ" to "// 2. Đường dữ liệu tổ hợp"
    start_str = "// =========================================================================\n    // 1. Trạng thái pipeline do core giữ\n    // ========================================================================="
    end_str = "// =========================================================================\n    // 2. Đường dữ liệu tổ hợp và trạng thái từ các module tầng\n    // ========================================================================="
    
    start_idx = content.find(start_str)
    end_idx = content.find(end_str)
    
    if start_idx != -1 and end_idx != -1:
        block = content[start_idx:end_idx]
        block = re.sub(r'\breg\b', 'wire', block)
        content = content[:start_idx] + block + content[end_idx:]
    
    # 3. Replace the always block with instantiations
    always_start_str = "// =========================================================================\n    // 5. Cập nhật pipeline tại cạnh lên\n    // ========================================================================="
    always_end_str = "endmodule"
    
    always_start_idx = content.find(always_start_str)
    always_end_idx = content.rfind(always_end_str)
    
    instantiations = """// =========================================================================
    // 5. Cập nhật pipeline tại cạnh lên (Instantiations)
    // =========================================================================
    rv32_idex_reg u_idex_reg (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .trap_flush_i     (wb_trap_event),
        .stage_flush_i    (mem_fault_event || ex_fault_event || ex_redirect_event),
        .mem_stall_i      (mem_stall),
        .load_use_stall_i (load_use_stall),
        .valid_id_i       (valid_id),
        .pc_id_i          (pc_id),
        .instr_id_i       (instr_id),
        .rs1_addr_id_i    (id_rs1_addr),
        .rs2_addr_id_i    (id_rs2_addr),
        .rd_addr_id_i     (id_rd_addr),
        .rs1_data_id_i    (id_rs1_data),
        .rs2_data_id_i    (id_rs2_data),
        .imm_id_i         (id_imm),
        .funct3_id_i      (id_funct3),
        .alu_op_id_i      (id_alu_op),
        .op_a_sel_id_i    (id_op_a_sel),
        .op_b_imm_id_i    (id_op_b_imm),
        .reg_write_id_i   (id_reg_write),
        .wb_sel_id_i      (id_wb_sel),
        .branch_id_i      (id_branch),
        .jal_id_i         (id_jal),
        .jalr_id_i        (id_jalr),
        .load_id_i        (id_load),
        .store_id_i       (id_store),
        .exc_valid_id_i   (exc_valid_id),
        .exc_cause_id_i   (exc_cause_id),
        .rs1_fwd_i        (ex_rs1_value),
        .rs2_fwd_i        (ex_rs2_value),
        .valid_ex_o       (valid_ex),
        .pc_ex_o          (pc_ex),
        .instr_ex_o       (instr_ex),
        .pc4_ex_o         (pc4_ex),
        .rs1_addr_ex_o    (rs1_addr_ex),
        .rs2_addr_ex_o    (rs2_addr_ex),
        .rd_addr_ex_o     (rd_addr_ex),
        .rs1_data_ex_o    (rs1_data_ex),
        .rs2_data_ex_o    (rs2_data_ex),
        .imm_ex_o         (imm_ex),
        .funct3_ex_o      (funct3_ex),
        .alu_op_ex_o      (alu_op_ex),
        .op_a_sel_ex_o    (op_a_sel_ex),
        .op_b_imm_ex_o    (op_b_imm_ex),
        .reg_write_ex_o   (reg_write_ex),
        .wb_sel_ex_o      (wb_sel_ex),
        .branch_ex_o      (branch_ex),
        .jal_ex_o         (jal_ex),
        .jalr_ex_o        (jalr_ex),
        .load_ex_o        (load_ex),
        .store_ex_o       (store_ex),
        .exc_valid_ex_o   (exc_valid_ex),
        .exc_cause_ex_o   (exc_cause_ex)
    );

    rv32_exmem_reg u_exmem_reg (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .trap_flush_i     (wb_trap_event),
        .stage_flush_i    (mem_fault_event),
        .mem_stall_i      (mem_stall),
        .valid_ex_i       (valid_ex),
        .pc_ex_i          (pc_ex),
        .instr_ex_i       (instr_ex),
        .pc4_ex_i         (pc4_ex),
        .rd_addr_ex_i     (rd_addr_ex),
        .reg_write_ex_i   (reg_write_ex),
        .wb_sel_ex_i      (wb_sel_ex),
        .alu_result_ex_i  (ex_alu_result),
        .store_data_ex_i  (ex_rs2_value),
        .funct3_ex_i      (funct3_ex),
        .load_ex_i        (load_ex),
        .store_ex_i       (store_ex),
        .exc_valid_ex_i   (exc_valid_ex),
        .exc_cause_ex_i   (exc_cause_ex),
        .ex_fault_raw_i   (ex_fault_raw),
        .ex_fault_cause_i (ex_fault_cause),
        .valid_mem_o      (valid_mem),
        .pc_mem_o         (pc_mem),
        .instr_mem_o      (instr_mem),
        .pc4_mem_o        (pc4_mem),
        .rd_addr_mem_o    (rd_addr_mem),
        .reg_write_mem_o  (reg_write_mem),
        .wb_sel_mem_o     (wb_sel_mem),
        .alu_result_mem_o (alu_result_mem),
        .store_data_mem_o (store_data_mem),
        .funct3_mem_o     (funct3_mem),
        .load_mem_o       (load_mem),
        .store_mem_o      (store_mem),
        .exc_valid_mem_o  (exc_valid_mem),
        .exc_cause_mem_o  (exc_cause_mem)
    );

    rv32_memwb_reg u_memwb_reg (
        .clk_i             (clk_i),
        .rst_i             (rst_i),
        .trap_flush_i      (wb_trap_event),
        .mem_stall_i       (mem_stall),
        .valid_mem_i       (valid_mem),
        .pc_mem_i          (pc_mem),
        .instr_mem_i       (instr_mem),
        .rd_addr_mem_i     (rd_addr_mem),
        .reg_write_mem_i   (reg_write_mem),
        .mem_wb_data_i     (mem_wb_data),
        .exc_valid_mem_i   (exc_valid_mem),
        .exc_cause_mem_i   (exc_cause_mem),
        .load_mem_i        (load_mem),
        .mem_fault_event_i (mem_fault_event),
        .valid_wb_o        (valid_wb),
        .pc_wb_o           (pc_wb),
        .instr_wb_o        (instr_wb),
        .rd_addr_wb_o      (rd_addr_wb),
        .reg_write_wb_o    (reg_write_wb),
        .wb_data_wb_o      (wb_data_wb),
        .exc_valid_wb_o    (exc_valid_wb),
        .exc_cause_wb_o    (exc_cause_wb)
    );

"""
    
    if always_start_idx != -1 and always_end_idx != -1:
        content = content[:always_start_idx] + instantiations + content[always_end_idx:]

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

refactor_core(r'c:\FPGA\riscv_soc_de10_lite - Copy\rtl\core\rv32_core.v')
