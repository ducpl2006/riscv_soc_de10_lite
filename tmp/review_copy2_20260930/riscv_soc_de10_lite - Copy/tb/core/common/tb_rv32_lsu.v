`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench tự kiểm tra cho rv32_lsu
 *
 * Chiến lược:
 * - Dùng word 0x80ff7f01 để byte lane little-endian lần lượt là
 *   01, 7f, ff, 80; nhờ đó bắt được cả chọn lane và mở rộng dấu/zero.
 * - Kiểm tra SB ở bốn lane, SH ở hai lane hợp lệ, SW, dữ liệu ghi đã shift
 *   và từng mẫu byte-strobe.
 * - Kiểm tra mọi dạng LB/LH/LW/LBU/LHU, địa chỉ lệch hàng, funct3 dành
 *   riêng, trạng thái idle và căn địa chỉ word.
 * - Store lệch hàng phải có strobe 0000; mọi phép so sánh dùng !== và có
 *   watchdog chống treo.
 */
module tb_rv32_lsu;

    reg  [31:0] addr;
    reg  [2:0]  funct3;
    reg         load_en;
    reg         store_en;
    reg  [31:0] store_data;
    reg  [31:0] load_data;

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] load_result;
    wire        misaligned;

    integer check_count;
    integer fail_count;

    rv32_lsu dut (
        .addr_i        (addr),
        .funct3_i      (funct3),
        .load_en_i     (load_en),
        .store_en_i    (store_en),
        .store_data_i  (store_data),
        .load_data_i   (load_data),
        .mem_addr_o    (mem_addr),
        .mem_wdata_o   (mem_wdata),
        .mem_wstrb_o   (mem_wstrb),
        .load_data_o   (load_result),
        .misaligned_o  (misaligned)
    );

    task check_lsu;
        input [31:0] test_addr;
        input [2:0]  test_funct3;
        input        test_load_en;
        input        test_store_en;
        input [31:0] test_store_data;
        input [31:0] test_load_data;
        input [31:0] expected_mem_addr;
        input [31:0] expected_mem_wdata;
        input [3:0]  expected_mem_wstrb;
        input [31:0] expected_load_result;
        input        expected_misaligned;
        input [8*48-1:0] test_name;
        begin
            addr       = test_addr;
            funct3     = test_funct3;
            load_en    = test_load_en;
            store_en   = test_store_en;
            store_data = test_store_data;
            load_data  = test_load_data;
            #1;

            check_count = check_count + 1;
            if ((mem_addr    !== expected_mem_addr)       ||
                (mem_wdata   !== expected_mem_wdata)      ||
                (mem_wstrb   !== expected_mem_wstrb)      ||
                (load_result !== expected_load_result)    ||
                (misaligned  !== expected_misaligned)) begin
                fail_count = fail_count + 1;
                $display("FAIL %0s", test_name);
                $display(
                    "  got: addr=%h wdata=%h strb=%b load=%h mis=%b",
                    mem_addr, mem_wdata, mem_wstrb,
                    load_result, misaligned
                );
                $display(
                    "  exp: addr=%h wdata=%h strb=%b load=%h mis=%b",
                    expected_mem_addr, expected_mem_wdata,
                    expected_mem_wstrb, expected_load_result,
                    expected_misaligned
                );
            end
        end
    endtask

    initial begin
        addr        = 32'b0;
        funct3      = 3'b0;
        load_en     = 1'b0;
        store_en    = 1'b0;
        store_data  = 32'b0;
        load_data   = 32'b0;
        check_count = 0;
        fail_count  = 0;

        check_lsu(32'h00001003, 3'b000, 1'b0, 1'b0,
                  32'hA1B2C3D4, 32'h80FF7F01,
                  32'h00001000, 32'h00000000, 4'b0000,
                  32'h00000000, 1'b0, "idle outputs are benign");

        // Store byte: chỉ byte thấp D4 được đặt vào lane được chọn.
        check_lsu(32'h00001000, 3'b000, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00001000, 32'h000000D4, 4'b0001,
                  32'b0, 1'b0, "SB lane 0");
        check_lsu(32'h00001001, 3'b000, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00001000, 32'h0000D400, 4'b0010,
                  32'b0, 1'b0, "SB lane 1");
        check_lsu(32'h00001002, 3'b000, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00001000, 32'h00D40000, 4'b0100,
                  32'b0, 1'b0, "SB lane 2");
        check_lsu(32'h00001003, 3'b000, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00001000, 32'hD4000000, 4'b1000,
                  32'b0, 1'b0, "SB lane 3");
        check_lsu(32'hFFFFFFFF, 3'b000, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'hFFFFFFFC, 32'hD4000000, 4'b1000,
                  32'b0, 1'b0, "SB top address aligns without wrap logic");

        // Store halfword: chỉ 16 bit thấp C3D4 được dùng.
        check_lsu(32'h00002000, 3'b001, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00002000, 32'h0000C3D4, 4'b0011,
                  32'b0, 1'b0, "SH lower half");
        check_lsu(32'h00002002, 3'b001, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00002000, 32'hC3D40000, 4'b1100,
                  32'b0, 1'b0, "SH upper half");
        check_lsu(32'h00002001, 3'b001, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00002000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "SH offset 1 is blocked");
        check_lsu(32'h00002003, 3'b001, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00002000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "SH offset 3 is blocked");

        check_lsu(32'h00003000, 3'b010, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00003000, 32'hA1B2C3D4, 4'b1111,
                  32'b0, 1'b0, "SW aligned");
        check_lsu(32'h00003001, 3'b010, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00003000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "SW offset 1 is blocked");
        check_lsu(32'h00003002, 3'b010, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00003000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "SW offset 2 is blocked");
        check_lsu(32'h00003003, 3'b010, 1'b0, 1'b1,
                  32'hA1B2C3D4, 32'b0,
                  32'h00003000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "SW offset 3 is blocked");

        // Load byte signed/unsigned trên cả bốn lane của 80 FF 7F 01.
        check_lsu(32'h00004000, 3'b000, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h00000001, 1'b0, "LB lane 0 positive");
        check_lsu(32'h00004001, 3'b000, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h0000007F, 1'b0, "LB lane 1 positive boundary");
        check_lsu(32'h00004002, 3'b000, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'hFFFFFFFF, 1'b0, "LB lane 2 minus one");
        check_lsu(32'h00004003, 3'b000, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'hFFFFFF80, 1'b0, "LB lane 3 negative boundary");

        check_lsu(32'h00004000, 3'b100, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h00000001, 1'b0, "LBU lane 0");
        check_lsu(32'h00004001, 3'b100, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h0000007F, 1'b0, "LBU lane 1");
        check_lsu(32'h00004002, 3'b100, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h000000FF, 1'b0, "LBU lane 2 zero extends");
        check_lsu(32'h00004003, 3'b100, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h00000080, 1'b0, "LBU lane 3 zero extends");

        check_lsu(32'h00004000, 3'b001, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h00007F01, 1'b0, "LH lower positive");
        check_lsu(32'h00004002, 3'b001, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'hFFFF80FF, 1'b0, "LH upper negative");
        check_lsu(32'h00004000, 3'b101, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h00007F01, 1'b0, "LHU lower");
        check_lsu(32'h00004002, 3'b101, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h000080FF, 1'b0, "LHU upper zero extends");
        check_lsu(32'h00004001, 3'b001, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "LH offset 1 is misaligned");
        check_lsu(32'h00004003, 3'b101, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "LHU offset 3 is misaligned");

        check_lsu(32'h00004000, 3'b010, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'h80FF7F01, 1'b0, "LW aligned");
        check_lsu(32'h00004001, 3'b010, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "LW offset 1 is misaligned");
        check_lsu(32'h00004002, 3'b010, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "LW offset 2 is misaligned");
        check_lsu(32'h00004003, 3'b010, 1'b1, 1'b0,
                  32'b0, 32'h80FF7F01,
                  32'h00004000, 32'b0, 4'b0000,
                  32'b0, 1'b1, "LW offset 3 is misaligned");

        // Các mã load/store dành riêng phải không có tác dụng phụ.
        check_lsu(32'h00005003, 3'b011, 1'b1, 1'b0,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved load funct3 011");
        check_lsu(32'h00005003, 3'b110, 1'b1, 1'b0,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved load funct3 110");
        check_lsu(32'h00005003, 3'b111, 1'b1, 1'b0,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved load funct3 111");
        check_lsu(32'h00005003, 3'b011, 1'b0, 1'b1,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved store funct3 011");
        check_lsu(32'h00005003, 3'b101, 1'b0, 1'b1,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved store funct3 101");
        check_lsu(32'h00005003, 3'b111, 1'b0, 1'b1,
                  32'hFFFFFFFF, 32'hFFFFFFFF,
                  32'h00005000, 32'b0, 4'b0000,
                  32'b0, 1'b0, "reserved store funct3 111");

        if (fail_count == 0)
            $display("PASS tb_rv32_lsu: %0d checks", check_count);
        else
            $display(
                "FAIL tb_rv32_lsu: %0d/%0d checks failed",
                fail_count, check_count
            );

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL tb_rv32_lsu: timeout");
        $finish;
    end

endmodule

`default_nettype wire
