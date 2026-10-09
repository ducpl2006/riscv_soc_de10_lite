`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench tự kiểm tra cho rv32_imm_gen
 *
 * Chiến lược:
 * - Dựng lệnh từ chính vị trí bit do RV32I quy định, độc lập với DUT.
 * - Kiểm tra đủ I/S/B/U/J, mở rộng dấu, biên lớn nhất/nhỏ nhất và bit 0
 *   cưỡng bức bằng 0 của B/J.
 * - Kiểm tra IMM_NONE, mã dành riêng và chuyển từ mã hợp lệ sang mã lỗi
 *   để phát hiện latch hoặc giá trị cũ còn sót.
 * - Mỗi phép so sánh dùng !== nhằm bắt cả X/Z; watchdog kết thúc mô phỏng
 *   nếu testbench bị kẹt.
 */
module tb_rv32_imm_gen;

    reg  [31:0] instr;
    reg  [2:0]  imm_type;
    wire [31:0] imm;

    integer check_count;
    integer fail_count;

    localparam [2:0]
        IMM_NONE = 3'b000,
        IMM_I    = 3'b001,
        IMM_S    = 3'b010,
        IMM_B    = 3'b011,
        IMM_U    = 3'b100,
        IMM_J    = 3'b101;

    rv32_imm_gen dut (
        .instr_i    (instr),
        .imm_type_i (imm_type),
        .imm_o      (imm)
    );

    function [31:0] make_i_instr;
        input [11:0] immediate;
        begin
            make_i_instr = 32'h00000013;
            make_i_instr[31:20] = immediate;
        end
    endfunction

    function [31:0] make_s_instr;
        input [11:0] immediate;
        begin
            make_s_instr = 32'h00000023;
            make_s_instr[31:25] = immediate[11:5];
            make_s_instr[11:7]  = immediate[4:0];
        end
    endfunction

    function [31:0] make_b_instr;
        input [12:0] immediate;
        begin
            make_b_instr = 32'h00000063;
            make_b_instr[31]    = immediate[12];
            make_b_instr[7]     = immediate[11];
            make_b_instr[30:25] = immediate[10:5];
            make_b_instr[11:8]  = immediate[4:1];
        end
    endfunction

    function [31:0] make_u_instr;
        input [19:0] immediate_upper;
        begin
            make_u_instr = {immediate_upper, 12'h037};
        end
    endfunction

    function [31:0] make_j_instr;
        input [20:0] immediate;
        begin
            make_j_instr = 32'h0000006f;
            make_j_instr[31]    = immediate[20];
            make_j_instr[19:12] = immediate[19:12];
            make_j_instr[20]    = immediate[11];
            make_j_instr[30:21] = immediate[10:1];
        end
    endfunction

    task check_imm;
        input [2:0]   test_type;
        input [31:0]  test_instr;
        input [31:0]  expected;
        input [8*48-1:0] test_name;
        begin
            imm_type = test_type;
            instr    = test_instr;
            #1;

            check_count = check_count + 1;
            if (imm !== expected) begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL %0s: type=%b instr=%h got=%h expected=%h",
                    test_name, test_type, test_instr, imm, expected
                );
            end
        end
    endtask

    initial begin
        instr       = 32'b0;
        imm_type    = IMM_NONE;
        check_count = 0;
        fail_count  = 0;

        check_imm(IMM_NONE, 32'hFFFFFFFF, 32'h00000000,
                  "IMM_NONE returns zero");

        check_imm(IMM_I, make_i_instr(12'h000), 32'h00000000,
                  "I zero");
        check_imm(IMM_I, make_i_instr(12'h7FF), 32'h000007FF,
                  "I largest positive");
        check_imm(IMM_I, make_i_instr(12'h800), 32'hFFFFF800,
                  "I most negative");
        check_imm(IMM_I, make_i_instr(12'hFFF), 32'hFFFFFFFF,
                  "I minus one");

        check_imm(IMM_S, make_s_instr(12'h123), 32'h00000123,
                  "S split positive");
        check_imm(IMM_S, make_s_instr(12'h800), 32'hFFFFF800,
                  "S most negative");
        check_imm(IMM_S, make_s_instr(12'hFFF), 32'hFFFFFFFF,
                  "S minus one");

        check_imm(IMM_B, make_b_instr(13'h0000), 32'h00000000,
                  "B zero");
        check_imm(IMM_B, make_b_instr(13'h0FFE), 32'h00000FFE,
                  "B largest positive even offset");
        check_imm(IMM_B, make_b_instr(13'h1000), 32'hFFFFF000,
                  "B most negative offset");
        check_imm(IMM_B, make_b_instr(13'h1FFE), 32'hFFFFFFFE,
                  "B minus two");

        check_imm(IMM_U, make_u_instr(20'h00000), 32'h00000000,
                  "U zero");
        check_imm(IMM_U, make_u_instr(20'h12345), 32'h12345000,
                  "U places upper twenty bits");
        check_imm(IMM_U, make_u_instr(20'hABCDE), 32'hABCDE000,
                  "U preserves top sign bit as data");

        check_imm(IMM_J, make_j_instr(21'h000000), 32'h00000000,
                  "J zero");
        check_imm(IMM_J, make_j_instr(21'h0FFFFE), 32'h000FFFFE,
                  "J largest positive even offset");
        check_imm(IMM_J, make_j_instr(21'h100000), 32'hFFF00000,
                  "J most negative offset");
        check_imm(IMM_J, make_j_instr(21'h1FFFFE), 32'hFFFFFFFE,
                  "J minus two");

        check_imm(3'b110, 32'hFFFFFFFF, 32'h00000000,
                  "reserved type 110 returns zero");
        check_imm(3'b111, 32'hA5A5A5A5, 32'h00000000,
                  "reserved type 111 returns zero");
        check_imm(3'bxxx, 32'hFFFFFFFF, 32'h00000000,
                  "unknown type returns zero");

        if (fail_count == 0)
            $display("PASS tb_rv32_imm_gen: %0d checks", check_count);
        else
            $display(
                "FAIL tb_rv32_imm_gen: %0d/%0d checks failed",
                fail_count, check_count
            );

        $finish;
    end

    initial begin
        #1000;
        $display("FAIL tb_rv32_imm_gen: timeout");
        $finish;
    end

endmodule

`default_nettype wire
