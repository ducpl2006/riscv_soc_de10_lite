`timescale 1ns/1ps
`default_nettype none
// Tệp sinh tự động: hai bản nhận cùng đầu vào và cùng RESET_VECTOR.
module rv32_core #(parameter [31:0] RESET_VECTOR = 32'h0000_0000) (
    input wire  clk_i,
    input wire  rst_i,
    output wire  imem_req_o,
    output wire [31:0] imem_addr_o,
    input wire  imem_gnt_i,
    input wire  imem_rvalid_i,
    input wire [31:0] imem_rdata_i,
    input wire  imem_err_i,
    output wire  dmem_req_o,
    output wire  dmem_we_o,
    output wire [31:0] dmem_addr_o,
    output wire [31:0] dmem_wdata_o,
    output wire [3:0] dmem_wstrb_o,
    input wire [31:0] dmem_rdata_i,
    input wire  dmem_ready_i,
    input wire  dmem_err_i,
    output wire  halted_o,
    output wire  trap_valid_o,
    output wire [4:0] trap_cause_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_instr_o,
    output wire  retire_valid_o,
    output wire [31:0] retire_pc_o,
    output wire [31:0] retire_instr_o,
    output wire  retire_rd_we_o,
    output wire [4:0] retire_rd_addr_o,
    output wire [31:0] retire_rd_data_o,
    output wire [31:0] debug_fetch_pc_o
);
    wire  tham_chieu_imem_req_o;
    wire [31:0] tham_chieu_imem_addr_o;
    wire  tham_chieu_dmem_req_o;
    wire  tham_chieu_dmem_we_o;
    wire [31:0] tham_chieu_dmem_addr_o;
    wire [31:0] tham_chieu_dmem_wdata_o;
    wire [3:0] tham_chieu_dmem_wstrb_o;
    wire  tham_chieu_halted_o;
    wire  tham_chieu_trap_valid_o;
    wire [4:0] tham_chieu_trap_cause_o;
    wire [31:0] tham_chieu_trap_pc_o;
    wire [31:0] tham_chieu_trap_instr_o;
    wire  tham_chieu_retire_valid_o;
    wire [31:0] tham_chieu_retire_pc_o;
    wire [31:0] tham_chieu_retire_instr_o;
    wire  tham_chieu_retire_rd_we_o;
    wire [4:0] tham_chieu_retire_rd_addr_o;
    wire [31:0] tham_chieu_retire_rd_data_o;
    wire [31:0] tham_chieu_debug_fetch_pc_o;
    eq_candidate_rv32_core #(.RESET_VECTOR(RESET_VECTOR)) u_ban_moi (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .imem_req_o(imem_req_o),
        .imem_addr_o(imem_addr_o),
        .imem_gnt_i(imem_gnt_i),
        .imem_rvalid_i(imem_rvalid_i),
        .imem_rdata_i(imem_rdata_i),
        .imem_err_i(imem_err_i),
        .dmem_req_o(dmem_req_o),
        .dmem_we_o(dmem_we_o),
        .dmem_addr_o(dmem_addr_o),
        .dmem_wdata_o(dmem_wdata_o),
        .dmem_wstrb_o(dmem_wstrb_o),
        .dmem_rdata_i(dmem_rdata_i),
        .dmem_ready_i(dmem_ready_i),
        .dmem_err_i(dmem_err_i),
        .halted_o(halted_o),
        .trap_valid_o(trap_valid_o),
        .trap_cause_o(trap_cause_o),
        .trap_pc_o(trap_pc_o),
        .trap_instr_o(trap_instr_o),
        .retire_valid_o(retire_valid_o),
        .retire_pc_o(retire_pc_o),
        .retire_instr_o(retire_instr_o),
        .retire_rd_we_o(retire_rd_we_o),
        .retire_rd_addr_o(retire_rd_addr_o),
        .retire_rd_data_o(retire_rd_data_o),
        .debug_fetch_pc_o(debug_fetch_pc_o)
    );
    eq_reference_rv32_core #(.RESET_VECTOR(RESET_VECTOR)) u_ban_goc (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .imem_req_o(tham_chieu_imem_req_o),
        .imem_addr_o(tham_chieu_imem_addr_o),
        .imem_gnt_i(imem_gnt_i),
        .imem_rvalid_i(imem_rvalid_i),
        .imem_rdata_i(imem_rdata_i),
        .imem_err_i(imem_err_i),
        .dmem_req_o(tham_chieu_dmem_req_o),
        .dmem_we_o(tham_chieu_dmem_we_o),
        .dmem_addr_o(tham_chieu_dmem_addr_o),
        .dmem_wdata_o(tham_chieu_dmem_wdata_o),
        .dmem_wstrb_o(tham_chieu_dmem_wstrb_o),
        .dmem_rdata_i(dmem_rdata_i),
        .dmem_ready_i(dmem_ready_i),
        .dmem_err_i(dmem_err_i),
        .halted_o(tham_chieu_halted_o),
        .trap_valid_o(tham_chieu_trap_valid_o),
        .trap_cause_o(tham_chieu_trap_cause_o),
        .trap_pc_o(tham_chieu_trap_pc_o),
        .trap_instr_o(tham_chieu_trap_instr_o),
        .retire_valid_o(tham_chieu_retire_valid_o),
        .retire_pc_o(tham_chieu_retire_pc_o),
        .retire_instr_o(tham_chieu_retire_instr_o),
        .retire_rd_we_o(tham_chieu_retire_rd_we_o),
        .retire_rd_addr_o(tham_chieu_retire_rd_addr_o),
        .retire_rd_data_o(tham_chieu_retire_rd_data_o),
        .debug_fetch_pc_o(tham_chieu_debug_fetch_pc_o)
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
            if (dmem_req_o !== tham_chieu_dmem_req_o)
                $fatal(1, "Sai khác %m.dmem_req_o lúc %0t: mới=%h gốc=%h",
                       $time, dmem_req_o, tham_chieu_dmem_req_o);
            if (dmem_we_o !== tham_chieu_dmem_we_o)
                $fatal(1, "Sai khác %m.dmem_we_o lúc %0t: mới=%h gốc=%h",
                       $time, dmem_we_o, tham_chieu_dmem_we_o);
            if (dmem_addr_o !== tham_chieu_dmem_addr_o)
                $fatal(1, "Sai khác %m.dmem_addr_o lúc %0t: mới=%h gốc=%h",
                       $time, dmem_addr_o, tham_chieu_dmem_addr_o);
            if (dmem_wdata_o !== tham_chieu_dmem_wdata_o)
                $fatal(1, "Sai khác %m.dmem_wdata_o lúc %0t: mới=%h gốc=%h",
                       $time, dmem_wdata_o, tham_chieu_dmem_wdata_o);
            if (dmem_wstrb_o !== tham_chieu_dmem_wstrb_o)
                $fatal(1, "Sai khác %m.dmem_wstrb_o lúc %0t: mới=%h gốc=%h",
                       $time, dmem_wstrb_o, tham_chieu_dmem_wstrb_o);
            if (halted_o !== tham_chieu_halted_o)
                $fatal(1, "Sai khác %m.halted_o lúc %0t: mới=%h gốc=%h",
                       $time, halted_o, tham_chieu_halted_o);
            if (trap_valid_o !== tham_chieu_trap_valid_o)
                $fatal(1, "Sai khác %m.trap_valid_o lúc %0t: mới=%h gốc=%h",
                       $time, trap_valid_o, tham_chieu_trap_valid_o);
            if (trap_cause_o !== tham_chieu_trap_cause_o)
                $fatal(1, "Sai khác %m.trap_cause_o lúc %0t: mới=%h gốc=%h",
                       $time, trap_cause_o, tham_chieu_trap_cause_o);
            if (trap_pc_o !== tham_chieu_trap_pc_o)
                $fatal(1, "Sai khác %m.trap_pc_o lúc %0t: mới=%h gốc=%h",
                       $time, trap_pc_o, tham_chieu_trap_pc_o);
            if (trap_instr_o !== tham_chieu_trap_instr_o)
                $fatal(1, "Sai khác %m.trap_instr_o lúc %0t: mới=%h gốc=%h",
                       $time, trap_instr_o, tham_chieu_trap_instr_o);
            if (retire_valid_o !== tham_chieu_retire_valid_o)
                $fatal(1, "Sai khác %m.retire_valid_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_valid_o, tham_chieu_retire_valid_o);
            if (retire_pc_o !== tham_chieu_retire_pc_o)
                $fatal(1, "Sai khác %m.retire_pc_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_pc_o, tham_chieu_retire_pc_o);
            if (retire_instr_o !== tham_chieu_retire_instr_o)
                $fatal(1, "Sai khác %m.retire_instr_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_instr_o, tham_chieu_retire_instr_o);
            if (retire_rd_we_o !== tham_chieu_retire_rd_we_o)
                $fatal(1, "Sai khác %m.retire_rd_we_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_rd_we_o, tham_chieu_retire_rd_we_o);
            if (retire_rd_addr_o !== tham_chieu_retire_rd_addr_o)
                $fatal(1, "Sai khác %m.retire_rd_addr_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_rd_addr_o, tham_chieu_retire_rd_addr_o);
            if (retire_rd_data_o !== tham_chieu_retire_rd_data_o)
                $fatal(1, "Sai khác %m.retire_rd_data_o lúc %0t: mới=%h gốc=%h",
                       $time, retire_rd_data_o, tham_chieu_retire_rd_data_o);
            if (debug_fetch_pc_o !== tham_chieu_debug_fetch_pc_o)
                $fatal(1, "Sai khác %m.debug_fetch_pc_o lúc %0t: mới=%h gốc=%h",
                       $time, debug_fetch_pc_o, tham_chieu_debug_fetch_pc_o);
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
