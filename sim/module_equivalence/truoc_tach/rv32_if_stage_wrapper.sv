`timescale 1ns/1ps
`default_nettype none
// Tệp sinh tự động: hai bản nhận cùng đầu vào và cùng RESET_VECTOR.
module rv32_if_stage #(parameter [31:0] RESET_VECTOR = 32'h0000_0000) (
    input wire  clk_i,
    input wire  rst_i,
    input wire  halted_i,
    input wire  wb_trap_event_i,
    input wire  mem_fault_event_i,
    input wire  ex_fault_event_i,
    input wire  ex_redirect_event_i,
    input wire  id_exception_event_i,
    input wire [31:0] ex_control_target_i,
    input wire  ifid_consumed_i,
    input wire  imem_gnt_i,
    input wire  imem_rvalid_i,
    input wire [31:0] imem_rdata_i,
    input wire  imem_err_i,
    output wire  imem_req_o,
    output wire [31:0] imem_addr_o,
    output wire [31:0] debug_fetch_pc_o,
    output wire  ifid_valid_o,
    output wire [31:0] ifid_pc_o,
    output wire [31:0] ifid_instr_o,
    output wire  ifid_exc_valid_o,
    output wire [4:0] ifid_exc_cause_o
);
    wire  tham_chieu_imem_req_o;
    wire [31:0] tham_chieu_imem_addr_o;
    wire [31:0] tham_chieu_debug_fetch_pc_o;
    wire  tham_chieu_ifid_valid_o;
    wire [31:0] tham_chieu_ifid_pc_o;
    wire [31:0] tham_chieu_ifid_instr_o;
    wire  tham_chieu_ifid_exc_valid_o;
    wire [4:0] tham_chieu_ifid_exc_cause_o;
    eq_candidate_rv32_if_stage #(.RESET_VECTOR(RESET_VECTOR)) u_ban_moi (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .halted_i(halted_i),
        .wb_trap_event_i(wb_trap_event_i),
        .mem_fault_event_i(mem_fault_event_i),
        .ex_fault_event_i(ex_fault_event_i),
        .ex_redirect_event_i(ex_redirect_event_i),
        .id_exception_event_i(id_exception_event_i),
        .ex_control_target_i(ex_control_target_i),
        .ifid_consumed_i(ifid_consumed_i),
        .imem_gnt_i(imem_gnt_i),
        .imem_rvalid_i(imem_rvalid_i),
        .imem_rdata_i(imem_rdata_i),
        .imem_err_i(imem_err_i),
        .imem_req_o(imem_req_o),
        .imem_addr_o(imem_addr_o),
        .debug_fetch_pc_o(debug_fetch_pc_o),
        .ifid_valid_o(ifid_valid_o),
        .ifid_pc_o(ifid_pc_o),
        .ifid_instr_o(ifid_instr_o),
        .ifid_exc_valid_o(ifid_exc_valid_o),
        .ifid_exc_cause_o(ifid_exc_cause_o)
    );
    eq_reference_rv32_if_stage #(.RESET_VECTOR(RESET_VECTOR)) u_ban_goc (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .halted_i(halted_i),
        .wb_trap_event_i(wb_trap_event_i),
        .mem_fault_event_i(mem_fault_event_i),
        .ex_fault_event_i(ex_fault_event_i),
        .ex_redirect_event_i(ex_redirect_event_i),
        .id_exception_event_i(id_exception_event_i),
        .ex_control_target_i(ex_control_target_i),
        .ifid_consumed_i(ifid_consumed_i),
        .imem_gnt_i(imem_gnt_i),
        .imem_rvalid_i(imem_rvalid_i),
        .imem_rdata_i(imem_rdata_i),
        .imem_err_i(imem_err_i),
        .imem_req_o(tham_chieu_imem_req_o),
        .imem_addr_o(tham_chieu_imem_addr_o),
        .debug_fetch_pc_o(tham_chieu_debug_fetch_pc_o),
        .ifid_valid_o(tham_chieu_ifid_valid_o),
        .ifid_pc_o(tham_chieu_ifid_pc_o),
        .ifid_instr_o(tham_chieu_ifid_instr_o),
        .ifid_exc_valid_o(tham_chieu_ifid_exc_valid_o),
        .ifid_exc_cause_o(tham_chieu_ifid_exc_cause_o)
    );
    reg da_reset = 1'b0;
    integer so_lan_so_sanh = 0;
    // Chờ một ns để cập nhật nonblocking và logic tổ hợp ổn định.
    // So payload cả khi invalid để phát hiện thay đổi quy tắc giữ/xóa.
    always @(posedge clk_i or negedge clk_i) begin
        if (clk_i && rst_i) da_reset = 1'b1;
        #1;
        if (da_reset) begin
            if (imem_req_o !== tham_chieu_imem_req_o)
                $fatal(1, "Sai khác %m.imem_req_o lúc %0t: mới=%h gốc=%h",
                       $time, imem_req_o, tham_chieu_imem_req_o);
            if (imem_addr_o !== tham_chieu_imem_addr_o)
                $fatal(1, "Sai khác %m.imem_addr_o lúc %0t: mới=%h gốc=%h",
                       $time, imem_addr_o, tham_chieu_imem_addr_o);
            if (debug_fetch_pc_o !== tham_chieu_debug_fetch_pc_o)
                $fatal(1, "Sai khác %m.debug_fetch_pc_o lúc %0t: mới=%h gốc=%h",
                       $time, debug_fetch_pc_o, tham_chieu_debug_fetch_pc_o);
            if (ifid_valid_o !== tham_chieu_ifid_valid_o)
                $fatal(1, "Sai khác %m.ifid_valid_o lúc %0t: mới=%h gốc=%h",
                       $time, ifid_valid_o, tham_chieu_ifid_valid_o);
            if (ifid_pc_o !== tham_chieu_ifid_pc_o)
                $fatal(1, "Sai khác %m.ifid_pc_o lúc %0t: mới=%h gốc=%h",
                       $time, ifid_pc_o, tham_chieu_ifid_pc_o);
            if (ifid_instr_o !== tham_chieu_ifid_instr_o)
                $fatal(1, "Sai khác %m.ifid_instr_o lúc %0t: mới=%h gốc=%h",
                       $time, ifid_instr_o, tham_chieu_ifid_instr_o);
            if (ifid_exc_valid_o !== tham_chieu_ifid_exc_valid_o)
                $fatal(1, "Sai khác %m.ifid_exc_valid_o lúc %0t: mới=%h gốc=%h",
                       $time, ifid_exc_valid_o, tham_chieu_ifid_exc_valid_o);
            if (ifid_exc_cause_o !== tham_chieu_ifid_exc_cause_o)
                $fatal(1, "Sai khác %m.ifid_exc_cause_o lúc %0t: mới=%h gốc=%h",
                       $time, ifid_exc_cause_o, tham_chieu_ifid_exc_cause_o);
            so_lan_so_sanh = so_lan_so_sanh + 1;
        end
    end
    final begin
        if (so_lan_so_sanh == 0)
            $fatal(1, "Không có lần đối chiếu nào tại %m");
        $display("DOI_CHIEU %m: %0d lần", so_lan_so_sanh);
    end
endmodule
`default_nettype wire
