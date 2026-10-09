`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench tự kiểm tra cho rv32_branch_unit
 *
 * Chiến lược:
 * - Kiểm tra cả kết quả đúng/sai của sáu funct3 branch hợp lệ.
 * - Dùng cùng mẫu bit âm/dương để phân biệt rõ so sánh có dấu và không dấu.
 * - Kiểm tra bằng nhau, các biên 0x80000000/0x7fffffff, branch bị disable
 *   và hai mã funct3 dành riêng.
 * - So sánh bằng !== để bắt X/Z và có watchdog chống treo.
 */
module tb_rv32_branch_unit;

    reg         branch_en;
    reg  [2:0]  funct3;
    reg  [31:0] rs1_data;
    reg  [31:0] rs2_data;
    wire        branch_taken;

    integer check_count;
    integer fail_count;

    rv32_branch_unit dut (
        .branch_en_i    (branch_en),
        .funct3_i       (funct3),
        .rs1_data_i     (rs1_data),
        .rs2_data_i     (rs2_data),
        .branch_taken_o (branch_taken)
    );

    task check_branch;
        input         test_enable;
        input [2:0]   test_funct3;
        input [31:0]  test_rs1;
        input [31:0]  test_rs2;
        input         expected;
        input [8*48-1:0] test_name;
        begin
            branch_en = test_enable;
            funct3    = test_funct3;
            rs1_data  = test_rs1;
            rs2_data  = test_rs2;
            #1;

            check_count = check_count + 1;
            if (branch_taken !== expected) begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL %0s: en=%b f3=%b rs1=%h rs2=%h got=%b exp=%b",
                    test_name, test_enable, test_funct3,
                    test_rs1, test_rs2, branch_taken, expected
                );
            end
        end
    endtask

    initial begin
        branch_en  = 1'b0;
        funct3     = 3'b000;
        rs1_data   = 32'b0;
        rs2_data   = 32'b0;
        check_count = 0;
        fail_count  = 0;

        check_branch(1'b0, 3'b000, 32'h12345678, 32'h12345678,
                     1'b0, "disabled BEQ cannot redirect PC");
        check_branch(1'b0, 3'b001, 32'h00000000, 32'hFFFFFFFF,
                     1'b0, "disabled BNE cannot redirect PC");

        check_branch(1'b1, 3'b000, 32'hDEADBEEF, 32'hDEADBEEF,
                     1'b1, "BEQ equal");
        check_branch(1'b1, 3'b000, 32'hDEADBEEF, 32'hDEADBEEE,
                     1'b0, "BEQ not equal");
        check_branch(1'b1, 3'b001, 32'h00000001, 32'h00000002,
                     1'b1, "BNE not equal");
        check_branch(1'b1, 3'b001, 32'h80000000, 32'h80000000,
                     1'b0, "BNE equal");

        check_branch(1'b1, 3'b100, 32'hFFFFFFFF, 32'h00000001,
                     1'b1, "BLT signed minus one less than one");
        check_branch(1'b1, 3'b100, 32'h80000000, 32'h7FFFFFFF,
                     1'b1, "BLT signed minimum less than maximum");
        check_branch(1'b1, 3'b100, 32'h00000007, 32'h00000007,
                     1'b0, "BLT equal is false");
        check_branch(1'b1, 3'b100, 32'h00000001, 32'hFFFFFFFF,
                     1'b0, "BLT positive not less than negative");

        check_branch(1'b1, 3'b101, 32'h00000007, 32'h00000007,
                     1'b1, "BGE signed equality");
        check_branch(1'b1, 3'b101, 32'h7FFFFFFF, 32'h80000000,
                     1'b1, "BGE signed maximum over minimum");
        check_branch(1'b1, 3'b101, 32'hFFFFFFFF, 32'h00000000,
                     1'b0, "BGE signed minus one below zero");

        check_branch(1'b1, 3'b110, 32'h00000000, 32'hFFFFFFFF,
                     1'b1, "BLTU zero below unsigned maximum");
        check_branch(1'b1, 3'b110, 32'hFFFFFFFF, 32'h00000001,
                     1'b0, "BLTU unsigned maximum not below one");
        check_branch(1'b1, 3'b110, 32'h80000000, 32'h80000000,
                     1'b0, "BLTU equal is false");

        check_branch(1'b1, 3'b111, 32'h80000000, 32'h80000000,
                     1'b1, "BGEU equality");
        check_branch(1'b1, 3'b111, 32'hFFFFFFFF, 32'h00000001,
                     1'b1, "BGEU unsigned maximum over one");
        check_branch(1'b1, 3'b111, 32'h00000000, 32'hFFFFFFFF,
                     1'b0, "BGEU zero below unsigned maximum");

        check_branch(1'b1, 3'b010, 32'h00000000, 32'h00000000,
                     1'b0, "reserved funct3 010");
        check_branch(1'b1, 3'b011, 32'hFFFFFFFF, 32'h00000000,
                     1'b0, "reserved funct3 011");

        if (fail_count == 0)
            $display("PASS tb_rv32_branch_unit: %0d checks", check_count);
        else
            $display(
                "FAIL tb_rv32_branch_unit: %0d/%0d checks failed",
                fail_count, check_count
            );

        $finish;
    end

    initial begin
        #1000;
        $display("FAIL tb_rv32_branch_unit: timeout");
        $finish;
    end

endmodule

`default_nettype wire
