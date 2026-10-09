`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Testbench   : tb_rv32_alu
// Mục tiêu    : Kiểm tra xác định mọi phép toán, biên số học, biên dịch và
//               toàn bộ mã điều khiển dự phòng của rv32_alu.
//
// Chiến lược
//   - Mỗi vector đặt đầu vào, chờ 1 ns cho logic tổ hợp ổn định rồi so sánh
//     bằng !== để bắt cả sai giá trị lẫn trạng thái X/Z.
//   - Giá trị mong đợi là hằng độc lập, không tái sử dụng biểu thức của DUT.
//   - Mọi lỗi được gom lại để có báo cáo đầy đủ; cuối test dùng $fatal để
//     regression trả trạng thái lỗi. Một watchdog riêng phát hiện mô phỏng kẹt.
// =============================================================================
module tb_rv32_alu;

    localparam [3:0]
        ALU_ADD    = 4'h0,
        ALU_SUB    = 4'h1,
        ALU_AND    = 4'h2,
        ALU_OR     = 4'h3,
        ALU_XOR    = 4'h4,
        ALU_SLL    = 4'h5,
        ALU_SRL    = 4'h6,
        ALU_SRA    = 4'h7,
        ALU_SLT    = 4'h8,
        ALU_SLTU   = 4'h9,
        ALU_COPY_B = 4'hA;

    localparam integer EXPECTED_TEST_COUNT = 58;

    reg  [31:0] operand_a;
    reg  [31:0] operand_b;
    reg  [3:0]  alu_op;

    wire [31:0] result;

    integer test_count;
    integer fail_count;
    integer reserved_op;

    rv32_alu dut (
        .operand_a_i (operand_a),
        .operand_b_i (operand_b),
        .alu_op_i    (alu_op),
        .result_o    (result)
    );

    task check;
        input [3:0]   operation;
        input [31:0]  value_a;
        input [31:0]  value_b;
        input [31:0]  expected;
        input [383:0] test_name;

        begin
            alu_op    = operation;
            operand_a = value_a;
            operand_b = value_b;

            #1;
            test_count = test_count + 1;

            if (result !== expected) begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL [%0d] %0s: op=%h A=%h B=%h got=%h expected=%h",
                    test_count,
                    test_name,
                    operation,
                    value_a,
                    value_b,
                    result,
                    expected
                );
            end
        end
    endtask

    initial begin
        operand_a  = 32'b0;
        operand_b  = 32'b0;
        alu_op     = ALU_ADD;
        test_count = 0;
        fail_count = 0;

        // ADD: zero, giá trị thường, carry và các biên overflow modulo 2^32.
        check(ALU_ADD, 32'h00000000, 32'h00000000,
              32'h00000000, "ADD zero");
        check(ALU_ADD, 32'd12, 32'd7,
              32'd19, "ADD basic");
        check(ALU_ADD, 32'hFFFFFFFF, 32'h00000001,
              32'h00000000, "ADD carry wraparound");
        check(ALU_ADD, 32'h7FFFFFFF, 32'h00000001,
              32'h80000000, "ADD signed positive overflow");
        check(ALU_ADD, 32'h80000000, 32'h80000000,
              32'h00000000, "ADD signed negative overflow");
        check(ALU_ADD, 32'hAAAAAAAA, 32'h55555555,
              32'hFFFFFFFF, "ADD complementary patterns");

        // SUB: zero, borrow và các biên wraparound.
        check(ALU_SUB, 32'h00000000, 32'h00000000,
              32'h00000000, "SUB zero");
        check(ALU_SUB, 32'd12, 32'd7,
              32'd5, "SUB basic");
        check(ALU_SUB, 32'd7, 32'd12,
              32'hFFFFFFFB, "SUB negative result");
        check(ALU_SUB, 32'h00000000, 32'h00000001,
              32'hFFFFFFFF, "SUB borrow wraparound");
        check(ALU_SUB, 32'h80000000, 32'h00000001,
              32'h7FFFFFFF, "SUB signed negative overflow");
        check(ALU_SUB, 32'h7FFFFFFF, 32'hFFFFFFFF,
              32'h80000000, "SUB signed positive overflow");

        // Logic bit theo bit với pattern xen kẽ và toán hạng trung tính.
        check(ALU_AND, 32'hA5A5A5A5, 32'h0F0F0F0F,
              32'h05050505, "AND alternating pattern");
        check(ALU_AND, 32'h12345678, 32'hFFFFFFFF,
              32'h12345678, "AND identity");
        check(ALU_OR, 32'hA5A5A5A5, 32'h0F0F0F0F,
              32'hAFAFAFAF, "OR alternating pattern");
        check(ALU_OR, 32'h12345678, 32'h00000000,
              32'h12345678, "OR identity");
        check(ALU_XOR, 32'hA5A5A5A5, 32'h0F0F0F0F,
              32'hAAAAAAAA, "XOR alternating pattern");
        check(ALU_XOR, 32'h89ABCDEF, 32'h89ABCDEF,
              32'h00000000, "XOR self");

        // SLL: lượng dịch 0/1/31 và chỉ năm bit thấp của operand B có hiệu lực.
        check(ALU_SLL, 32'h00000001, 32'd0,
              32'h00000001, "SLL by 0");
        check(ALU_SLL, 32'h00000001, 32'd1,
              32'h00000002, "SLL by 1");
        check(ALU_SLL, 32'h00000001, 32'd31,
              32'h80000000, "SLL by 31");
        check(ALU_SLL, 32'h00000001, 32'd32,
              32'h00000001, "SLL by 32 uses low five bits");
        check(ALU_SLL, 32'h00000003, 32'd63,
              32'h80000000, "SLL by 63 equals by 31");
        check(ALU_SLL, 32'h80000001, 32'd1,
              32'h00000002, "SLL discards high bit");
        check(ALU_SLL, 32'h00000001, 32'hFFFFFFE1,
              32'h00000002, "SLL ignores upper shift bits");

        // SRL: điền zero và cùng quy tắc năm bit lượng dịch.
        check(ALU_SRL, 32'h80000000, 32'd0,
              32'h80000000, "SRL by 0");
        check(ALU_SRL, 32'h80000000, 32'd1,
              32'h40000000, "SRL zero fill");
        check(ALU_SRL, 32'h80000000, 32'd31,
              32'h00000001, "SRL by 31");
        check(ALU_SRL, 32'h80000000, 32'd32,
              32'h80000000, "SRL by 32 uses low five bits");
        check(ALU_SRL, 32'hFFFFFFFF, 32'hFFFFFFE4,
              32'h0FFFFFFF, "SRL ignores upper shift bits");

        // SRA: bảo toàn dấu cho số âm và dịch logic tương đương cho số dương.
        check(ALU_SRA, 32'h80000000, 32'd0,
              32'h80000000, "SRA by 0");
        check(ALU_SRA, 32'h80000000, 32'd1,
              32'hC0000000, "SRA negative by 1");
        check(ALU_SRA, 32'h80000000, 32'd31,
              32'hFFFFFFFF, "SRA negative by 31");
        check(ALU_SRA, 32'h7FFFFFFF, 32'd1,
              32'h3FFFFFFF, "SRA positive by 1");
        check(ALU_SRA, 32'h7FFFFFFF, 32'd31,
              32'h00000000, "SRA positive by 31");
        check(ALU_SRA, 32'hFFFFFFFF, 32'd4,
              32'hFFFFFFFF, "SRA minus one");
        check(ALU_SRA, 32'h80000000, 32'd32,
              32'h80000000, "SRA by 32 uses low five bits");

        // So sánh có dấu: khác dấu, hai số âm, hai biên và bằng nhau.
        check(ALU_SLT, 32'hFFFFFFFF, 32'h00000001,
              32'd1, "SLT negative less than positive");
        check(ALU_SLT, 32'h00000001, 32'hFFFFFFFF,
              32'd0, "SLT positive not less than negative");
        check(ALU_SLT, 32'h80000000, 32'h7FFFFFFF,
              32'd1, "SLT minimum less than maximum");
        check(ALU_SLT, 32'h7FFFFFFF, 32'h80000000,
              32'd0, "SLT maximum not less than minimum");
        check(ALU_SLT, 32'hFFFFFFFE, 32'hFFFFFFFF,
              32'd1, "SLT minus two less than minus one");
        check(ALU_SLT, 32'hFFFFFFFF, 32'hFFFFFFFE,
              32'd0, "SLT minus one not less than minus two");
        check(ALU_SLT, 32'h80000000, 32'h80000000,
              32'd0, "SLT equal");

        // So sánh không dấu tại zero, bit cao và bằng nhau.
        check(ALU_SLTU, 32'hFFFFFFFF, 32'h00000001,
              32'd0, "SLTU maximum not less than one");
        check(ALU_SLTU, 32'h00000001, 32'hFFFFFFFF,
              32'd1, "SLTU one less than maximum");
        check(ALU_SLTU, 32'h00000000, 32'hFFFFFFFF,
              32'd1, "SLTU zero less than maximum");
        check(ALU_SLTU, 32'hFFFFFFFF, 32'hFFFFFFFF,
              32'd0, "SLTU equal");
        check(ALU_SLTU, 32'h80000000, 32'h7FFFFFFF,
              32'd0, "SLTU high bit set is larger");
        check(ALU_SLTU, 32'h7FFFFFFF, 32'h80000000,
              32'd1, "SLTU high bit clear is smaller");

        // COPY_B không phụ thuộc operand A.
        check(ALU_COPY_B, 32'hFFFFFFFF, 32'h12345000,
              32'h12345000, "COPY B pattern");
        check(ALU_COPY_B, 32'hAAAAAAAA, 32'h00000000,
              32'h00000000, "COPY B zero");
        check(ALU_COPY_B, 32'h00000000, 32'hFFFFFFFF,
              32'hFFFFFFFF, "COPY B ones");

        // Toàn bộ mã 0xB..0xF được dành riêng và phải cho kết quả xác định bằng 0.
        for (reserved_op = 11; reserved_op < 16;
             reserved_op = reserved_op + 1) begin
            check(reserved_op[3:0], 32'hDEADBEEF, 32'hCAFEBABE,
                  32'h00000000, "reserved ALU control");
        end

        if (test_count != EXPECTED_TEST_COUNT) begin
            $fatal(
                1,
                "FAIL: test manifest mismatch, ran %0d expected %0d",
                test_count,
                EXPECTED_TEST_COUNT
            );
        end
        else if (fail_count != 0) begin
            $fatal(1, "FAIL: %0d / %0d ALU tests", fail_count, test_count);
        end
        else begin
            $display("PASS: %0d ALU tests", test_count);
            $finish;
        end
    end

    // Watchdog độc lập: mọi đường chạy hợp lệ kết thúc trước mốc này.
    initial begin
        #1000;
        $fatal(1, "FAIL: tb_rv32_alu timeout");
    end

endmodule

`default_nettype wire
