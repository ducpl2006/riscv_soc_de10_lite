`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Testbench   : tb_rv32_regfile
// Mục tiêu    : Kiểm tra reset đồng bộ, x0, hai cổng đọc, cổng ghi và bypass
//               write-through WB -> ID của tập thanh ghi pipeline RV32I.
//
// Chiến lược
//   - Ghi rồi đọc toàn bộ x1..x31 bằng pattern xác định để phủ bộ giải mã địa chỉ.
//   - Kiểm tra riêng từng ưu tiên: x0, write-enable, bypass, reset hơn ghi.
//   - Kiểm tra bypass khi cả hai cổng trùng, chỉ một cổng trùng, bị hủy trước
//     cạnh clock và khi ghi liên tiếp không hạ rd_we_i.
//   - So sánh bằng !== để bắt X/Z; lỗi cuối test và timeout đều dùng $fatal.
//
// Quy ước thời gian
//   - Clock 50 MHz, chu kỳ 20 ns.
//   - Tín hiệu ghi/reset được đổi cách cạnh lên đủ xa để tránh race testbench.
//   - Bypass được kiểm tra trước cạnh ghi; dữ liệu lưu được kiểm tra sau cạnh ghi.
// =============================================================================
module tb_rv32_regfile;

    localparam integer EXPECTED_CHECK_COUNT = 113;

    reg         clk;
    reg         rst;
    reg  [4:0]  rs1_addr;
    reg  [4:0]  rs2_addr;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    reg         rd_we;
    reg  [4:0]  rd_addr;
    reg  [31:0] rd_data;

    reg [31:0] expected_registers [0:31];

    integer check_count;
    integer fail_count;
    integer index;

    rv32_regfile dut (
        .clk_i      (clk),
        .rst_i      (rst),
        .rs1_addr_i (rs1_addr),
        .rs2_addr_i (rs2_addr),
        .rs1_data_o (rs1_data),
        .rs2_data_o (rs2_data),
        .rd_we_i    (rd_we),
        .rd_addr_i  (rd_addr),
        .rd_data_i  (rd_data)
    );

    initial begin
        clk = 1'b0;
    end

    always #10 clk = ~clk;

    // Tạo pattern khác nhau cho từng địa chỉ, có cả bit 0 và bit 31 thay đổi.
    function [31:0] register_pattern;
        input [4:0] address;

        begin
            register_pattern = 32'hA5A55A5A
                             ^ ({27'b0, address} * 32'h01020409);
        end
    endfunction

    task expect_reads;
        input [4:0]   address_1;
        input [4:0]   address_2;
        input [31:0]  expected_1;
        input [31:0]  expected_2;
        input [511:0] test_name;

        begin
            rs1_addr = address_1;
            rs2_addr = address_2;

            #1;
            check_count = check_count + 1;

            if ((rs1_data !== expected_1) ||
                (rs2_data !== expected_2)) begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL [%0d] %0s: rs1=x%0d got=%h expected=%h",
                    check_count,
                    test_name,
                    address_1,
                    rs1_data,
                    expected_1
                );
                $display(
                    "                       rs2=x%0d got=%h expected=%h",
                    address_2,
                    rs2_data,
                    expected_2
                );
            end
        end
    endtask

    // Một giao dịch ghi chuẩn; dữ liệu được chốt tại đúng một cạnh lên.
    task commit_write;
        input [4:0]  address;
        input [31:0] data;

        begin
            @(negedge clk);
            rd_we   = 1'b1;
            rd_addr = address;
            rd_data = data;

            @(posedge clk);
            #1;
            rd_we   = 1'b0;
            rd_addr = 5'd0;
            rd_data = 32'b0;
        end
    endtask

    initial begin
        rst         = 1'b1;
        rs1_addr    = 5'd0;
        rs2_addr    = 5'd0;
        rd_we       = 1'b0;
        rd_addr     = 5'd0;
        rd_data     = 32'b0;
        check_count = 0;
        fail_count  = 0;

        for (index = 0; index < 32; index = index + 1) begin
            expected_registers[index] = 32'b0;
        end

        // Reset đồng bộ phải đi qua cạnh lên mới xóa x1..x31.
        repeat (2) @(posedge clk);
        #1;
        @(negedge clk);
        rst = 1'b0;

        // Mỗi địa chỉ xuất hiện một lần trên từng cổng đọc sau reset.
        for (index = 0; index < 32; index = index + 1) begin
            expect_reads(
                index[4:0],
                5'd31 - index[4:0],
                32'b0,
                32'b0,
                "all registers zero after reset"
            );
        end

        // Ghi pattern riêng vào toàn bộ thanh ghi có thể ghi.
        for (index = 1; index < 32; index = index + 1) begin
            expected_registers[index] = register_pattern(index[4:0]);
            commit_write(index[4:0], expected_registers[index]);
        end

        // Đọc chéo để phủ mọi địa chỉ trên cả rs1 và rs2.
        for (index = 0; index < 32; index = index + 1) begin
            expect_reads(
                index[4:0],
                5'd31 - index[4:0],
                expected_registers[index],
                expected_registers[31 - index],
                "stored address sweep"
            );
        end

        // Ghi x0 không được tạo bypass và không làm thay đổi x0.
        @(negedge clk);
        rd_we   = 1'b1;
        rd_addr = 5'd0;
        rd_data = 32'hDEADBEEF;
        expect_reads(
            5'd0,
            5'd1,
            32'b0,
            expected_registers[1],
            "x0 ignores write and bypass"
        );
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        expect_reads(
            5'd0,
            5'd1,
            32'b0,
            expected_registers[1],
            "x0 remains zero after write edge"
        );

        // rd_we = 0 phải bảo toàn dữ liệu dù địa chỉ/dữ liệu ghi thay đổi.
        @(negedge clk);
        rd_we   = 1'b0;
        rd_addr = 5'd5;
        rd_data = 32'hFFFFFFFF;
        expect_reads(
            5'd5,
            5'd6,
            expected_registers[5],
            expected_registers[6],
            "write disabled before edge"
        );
        @(posedge clk);
        #1;
        expect_reads(
            5'd5,
            5'd6,
            expected_registers[5],
            expected_registers[6],
            "write disabled after edge"
        );

        // Bypass là tổ hợp: hủy rd_we trước cạnh ghi phải khôi phục dữ liệu cũ.
        @(negedge clk);
        rd_we   = 1'b1;
        rd_addr = 5'd5;
        rd_data = 32'h11223344;
        expect_reads(
            5'd5,
            5'd6,
            32'h11223344,
            expected_registers[6],
            "bypass appears before write edge"
        );
        rd_we = 1'b0;
        expect_reads(
            5'd5,
            5'd6,
            expected_registers[5],
            expected_registers[6],
            "cancelled write reveals old stored data"
        );

        // Chỉ cổng có địa chỉ trùng rd mới nhận dữ liệu bypass.
        @(negedge clk);
        rd_we   = 1'b1;
        rd_addr = 5'd10;
        rd_data = 32'h01020304;
        expect_reads(
            5'd10,
            5'd11,
            32'h01020304,
            expected_registers[11],
            "bypass rs1 only"
        );
        expect_reads(
            5'd11,
            5'd10,
            expected_registers[11],
            32'h01020304,
            "bypass rs2 only"
        );
        @(posedge clk);
        #1;
        expected_registers[10] = 32'h01020304;
        @(negedge clk);
        rd_we = 1'b0;
        expect_reads(
            5'd10,
            5'd11,
            expected_registers[10],
            expected_registers[11],
            "bypassed value stored after edge"
        );

        // Hai cổng cùng trùng rd đều phải nhìn thấy giá trị WB mới.
        @(negedge clk);
        rd_we   = 1'b1;
        rd_addr = 5'd3;
        rd_data = 32'h89ABCDEF;
        expect_reads(
            5'd3,
            5'd3,
            32'h89ABCDEF,
            32'h89ABCDEF,
            "bypass both read ports"
        );
        @(posedge clk);
        #1;
        expected_registers[3] = 32'h89ABCDEF;
        @(negedge clk);
        rd_we = 1'b0;
        expect_reads(
            5'd3,
            5'd3,
            expected_registers[3],
            expected_registers[3],
            "both ports read stored overwrite"
        );

        // Hai giao dịch liên tiếp giữ rd_we = 1, đổi địa chỉ tại cạnh xuống.
        @(negedge clk);
        rd_we   = 1'b1;
        rd_addr = 5'd20;
        rd_data = 32'h13579BDF;
        expect_reads(
            5'd20,
            5'd21,
            32'h13579BDF,
            expected_registers[21],
            "first back-to-back bypass"
        );
        @(posedge clk);
        #1;
        expected_registers[20] = 32'h13579BDF;

        @(negedge clk);
        rd_addr = 5'd21;
        rd_data = 32'h2468ACE0;
        expect_reads(
            5'd20,
            5'd21,
            expected_registers[20],
            32'h2468ACE0,
            "second back-to-back bypass"
        );
        @(posedge clk);
        #1;
        expected_registers[21] = 32'h2468ACE0;

        @(negedge clk);
        rd_we = 1'b0;
        expect_reads(
            5'd20,
            5'd21,
            expected_registers[20],
            expected_registers[21],
            "back-to-back writes stored"
        );

        // Reset đồng bộ: trước cạnh vẫn thấy dữ liệu cũ và bypass bị khóa.
        @(negedge clk);
        rst     = 1'b1;
        rd_we   = 1'b1;
        rd_addr = 5'd1;
        rd_data = 32'hFFFFFFFF;
        expect_reads(
            5'd1,
            5'd31,
            expected_registers[1],
            expected_registers[31],
            "synchronous reset before active edge"
        );

        // Tại cạnh lên, reset thắng yêu cầu ghi và xóa toàn bộ x1..x31.
        @(posedge clk);
        #1;
        expect_reads(
            5'd1,
            5'd31,
            32'b0,
            32'b0,
            "reset priority over write"
        );
        @(negedge clk);
        rst     = 1'b0;
        rd_we   = 1'b0;
        rd_addr = 5'd0;
        rd_data = 32'b0;

        for (index = 0; index < 32; index = index + 1) begin
            expected_registers[index] = 32'b0;
            expect_reads(
                index[4:0],
                5'd31 - index[4:0],
                32'b0,
                32'b0,
                "all registers retain reset value"
            );
        end

        // Tập thanh ghi phải hoạt động lại ngay sau khi nhả reset.
        commit_write(5'd31, 32'h80000001);
        expected_registers[31] = 32'h80000001;
        expect_reads(
            5'd31,
            5'd0,
            expected_registers[31],
            32'b0,
            "write after reset release"
        );

        if (check_count != EXPECTED_CHECK_COUNT) begin
            $fatal(
                1,
                "FAIL: check manifest mismatch, ran %0d expected %0d",
                check_count,
                EXPECTED_CHECK_COUNT
            );
        end
        else if (fail_count != 0) begin
            $fatal(
                1,
                "FAIL: %0d / %0d register-file checks",
                fail_count,
                check_count
            );
        end
        else begin
            $display("PASS: %0d register-file checks", check_count);
            $finish;
        end
    end

    // Watchdog độc lập: regression không thể treo vô hạn nếu lỗi clock/control.
    initial begin
        #5000;
        $fatal(1, "FAIL: tb_rv32_regfile timeout");
    end

endmodule

`default_nettype wire
