`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Testbench   : tb_rv32_hazard_unit
// Mục tiêu    : Kiểm chứng stall load-use và forwarding MEM/WB của pipeline.
// Phương pháp : Directed self-checking; mỗi vector kiểm đồng thời ba output.
// Bao phủ     : x0, cờ uses_rs, hai toán hạng, ưu tiên MEM trên WB, load ở MEM,
//               stage invalid và trường hợp không có phụ thuộc.
// Tiêu chí    : Mọi vector đúng và không chạm timeout.
// =============================================================================
module tb_rv32_hazard_unit;

    reg  [4:0] id_rs1_addr;
    reg  [4:0] id_rs2_addr;
    reg        id_uses_rs1;
    reg        id_uses_rs2;
    reg        ex_valid;
    reg        ex_load;
    reg  [4:0] ex_rd_addr;
    reg  [4:0] ex_rs1_addr;
    reg  [4:0] ex_rs2_addr;
    reg        mem_valid;
    reg        mem_reg_write;
    reg        mem_load;
    reg  [4:0] mem_rd_addr;
    reg        wb_valid;
    reg        wb_reg_write;
    reg  [4:0] wb_rd_addr;

    wire       stall_load_use;
    wire [1:0] forward_rs1;
    wire [1:0] forward_rs2;

    integer test_count;
    integer fail_count;

    rv32_hazard_unit dut (
        .id_rs1_addr_i     (id_rs1_addr),
        .id_rs2_addr_i     (id_rs2_addr),
        .id_uses_rs1_i     (id_uses_rs1),
        .id_uses_rs2_i     (id_uses_rs2),
        .ex_valid_i        (ex_valid),
        .ex_load_i         (ex_load),
        .ex_rd_addr_i      (ex_rd_addr),
        .ex_rs1_addr_i     (ex_rs1_addr),
        .ex_rs2_addr_i     (ex_rs2_addr),
        .mem_valid_i       (mem_valid),
        .mem_reg_write_i   (mem_reg_write),
        .mem_load_i        (mem_load),
        .mem_rd_addr_i     (mem_rd_addr),
        .wb_valid_i        (wb_valid),
        .wb_reg_write_i    (wb_reg_write),
        .wb_rd_addr_i      (wb_rd_addr),
        .stall_load_use_o  (stall_load_use),
        .forward_rs1_o     (forward_rs1),
        .forward_rs2_o     (forward_rs2)
    );

    task clear_inputs;
        begin
            id_rs1_addr  = 5'd0;
            id_rs2_addr  = 5'd0;
            id_uses_rs1  = 1'b0;
            id_uses_rs2  = 1'b0;
            ex_valid     = 1'b0;
            ex_load      = 1'b0;
            ex_rd_addr   = 5'd0;
            ex_rs1_addr  = 5'd0;
            ex_rs2_addr  = 5'd0;
            mem_valid    = 1'b0;
            mem_reg_write = 1'b0;
            mem_load     = 1'b0;
            mem_rd_addr  = 5'd0;
            wb_valid     = 1'b0;
            wb_reg_write = 1'b0;
            wb_rd_addr   = 5'd0;
        end
    endtask

    task check;
        input       expected_stall;
        input [1:0] expected_fwd1;
        input [1:0] expected_fwd2;
        input [255:0] name;
        begin
            #1;
            test_count = test_count + 1;
            if ((stall_load_use !== expected_stall) ||
                (forward_rs1 !== expected_fwd1) ||
                (forward_rs2 !== expected_fwd2)) begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: stall=%b/%b fwd1=%b/%b fwd2=%b/%b",
                         name,
                         stall_load_use, expected_stall,
                         forward_rs1, expected_fwd1,
                         forward_rs2, expected_fwd2);
            end
        end
    endtask

    initial begin
        test_count = 0;
        fail_count = 0;
        clear_inputs();
        check(1'b0, 2'b00, 2'b00, "idle");

        id_uses_rs1 = 1'b1;
        id_rs1_addr = 5'd5;
        ex_valid    = 1'b1;
        ex_load     = 1'b1;
        ex_rd_addr  = 5'd5;
        check(1'b1, 2'b00, 2'b00, "load-use rs1");

        id_uses_rs1 = 1'b0;
        id_uses_rs2 = 1'b1;
        id_rs2_addr = 5'd5;
        check(1'b1, 2'b00, 2'b00, "load-use rs2");

        id_uses_rs2 = 1'b0;
        check(1'b0, 2'b00, 2'b00, "field unused");

        id_uses_rs1 = 1'b1;
        id_rs1_addr = 5'd0;
        ex_rd_addr  = 5'd0;
        check(1'b0, 2'b00, 2'b00, "x0 never stalls");

        clear_inputs();
        ex_rs1_addr    = 5'd7;
        ex_rs2_addr    = 5'd8;
        mem_valid      = 1'b1;
        mem_reg_write  = 1'b1;
        mem_rd_addr    = 5'd7;
        wb_valid       = 1'b1;
        wb_reg_write   = 1'b1;
        wb_rd_addr     = 5'd8;
        check(1'b0, 2'b10, 2'b01, "MEM rs1 and WB rs2");

        wb_rd_addr = 5'd7;
        check(1'b0, 2'b10, 2'b00, "MEM priority over WB");

        mem_load = 1'b1;
        check(1'b0, 2'b01, 2'b00, "MEM load cannot forward");

        mem_load    = 1'b0;
        mem_valid   = 1'b0;
        wb_rd_addr  = 5'd8;
        check(1'b0, 2'b00, 2'b01, "invalid MEM ignored");

        wb_reg_write = 1'b0;
        check(1'b0, 2'b00, 2'b00, "write disable ignored");

        wb_reg_write  = 1'b1;
        wb_rd_addr    = 5'd0;
        ex_rs2_addr   = 5'd0;
        check(1'b0, 2'b00, 2'b00, "x0 never forwarded");

        if (fail_count != 0)
            $fatal(1, "FAIL: %0d/%0d hazard checks failed",
                   fail_count, test_count);

        $display("PASS: %0d hazard checks", test_count);
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: timeout tb_rv32_hazard_unit");
    end

endmodule

`default_nettype wire
