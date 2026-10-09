`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Testbench : tb_rv32_soc
// Mục tiêu  : Kiểm tra tích hợp end-to-end CPU pipeline -> ROM/MMIO -> QNN ->
//             GPIO/UART và precise breakpoint trap.
//
// Firmware kiểm thử:
//   1) Ghi LED, nạp feature[0]=3, start QNN và poll done.
//   2) Model vàng trả 84; CPU đưa kết quả ra LED.
//   3) CPU phát chuỗi "OK" qua UART rồi EBREAK.
// =============================================================================
module tb_rv32_soc;

    reg clk;
    reg rst;
    reg [9:0] switches;
    wire [7:0] leds;
    wire uart_tx;
    wire halted;
    wire trap_valid;
    wire [4:0] trap_cause;
    wire [31:0] trap_pc;
    wire qnn_busy;
    wire qnn_done;
    wire [31:0] qnn_result;
    reg [7:0] uart_byte_0;
    reg [7:0] uart_byte_1;
    integer checks;
    integer timeout;

    rv32_soc #(
        .CLOCK_HZ(1000000),
        .ROM_WORDS(256),
        .RAM_WORDS(64),
        .USE_ROM_INIT_FILE(0),
        .USE_QNN_INIT_FILES(0)
    ) dut (
        .clk_i(clk), .rst_i(rst), .switches_i(switches), .leds_o(leds),
        .uart_rx_i(1'b1), .uart_tx_o(uart_tx),
        .i2c_scl_i(1'b1), .i2c_sda_i(1'b1),
        .i2c_scl_drive_low_o(), .i2c_sda_drive_low_o(),
        .halted_o(halted), .trap_valid_o(trap_valid), .trap_cause_o(trap_cause),
        .trap_pc_o(trap_pc), .qnn_busy_o(qnn_busy), .qnn_done_o(qnn_done),
        .qnn_result_o(qnn_result)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL tb_rv32_soc: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task receive_uart_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge uart_tx);
            // BAUD_DIV=9. Lấy mẫu giữa data bit 0, sau start 1,5 bit.
            repeat (13) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                repeat (9) @(posedge clk);
            end
            check(uart_tx === 1'b1, "UART stop bit phai o muc 1");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        switches = 10'h155;
        checks = 0;
        uart_byte_0 = 8'd0;
        uart_byte_1 = 8'd0;

        // Boot image hand-encoded, cùng nội dung firmware/build/boot.hex.
        #1;
        dut.u_rom.u_storage.mem[0]  = 32'h200000b7;
        dut.u_rom.u_storage.mem[1]  = 32'h15500113;
        dut.u_rom.u_storage.mem[2]  = 32'h0020a023;
        dut.u_rom.u_storage.mem[3]  = 32'h200031b7;
        dut.u_rom.u_storage.mem[4]  = 32'h00300213;
        dut.u_rom.u_storage.mem[5]  = 32'h1041a023;
        dut.u_rom.u_storage.mem[6]  = 32'h00100293;
        dut.u_rom.u_storage.mem[7]  = 32'h0051a023;
        dut.u_rom.u_storage.mem[8]  = 32'h0041a303;
        dut.u_rom.u_storage.mem[9]  = 32'h00237313;
        dut.u_rom.u_storage.mem[10] = 32'hfe030ce3;
        dut.u_rom.u_storage.mem[11] = 32'h0081a383;
        dut.u_rom.u_storage.mem[12] = 32'h0070a023;
        dut.u_rom.u_storage.mem[13] = 32'h20001437;
        dut.u_rom.u_storage.mem[14] = 32'h04f00493;
        dut.u_rom.u_storage.mem[15] = 32'h00940023;
        dut.u_rom.u_storage.mem[16] = 32'h04b00493;
        dut.u_rom.u_storage.mem[17] = 32'h00940023;
        dut.u_rom.u_storage.mem[18] = 32'h00100073;

        // Model vàng: (3*2+1)*3*4 = 84.
        dut.u_qnn.u_l1_weight_rom.mem[0]  = 8'sd2;
        dut.u_qnn.l1_biases[0]   = 32'sd1;
        dut.u_qnn.u_l2_weight_rom.mem[0]  = 8'sd3;
        dut.u_qnn.out_weights[0] = 8'sd4;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        fork
            begin
                receive_uart_byte(uart_byte_0);
                receive_uart_byte(uart_byte_1);
            end
            begin
                timeout = 0;
                while (!trap_valid && timeout < 10000) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
            end
        join

        check(timeout < 10000, "SoC phai ket thuc firmware truoc timeout");
        check(halted && trap_valid, "EBREAK phai halt core va tao trap");
        check(trap_cause == 5'd3, "trap cause phai la breakpoint");
        check(trap_pc == 32'h0000_0048, "trap PC phai tro vao EBREAK");
        check(qnn_done && !qnn_busy, "QNN phai hoan tat");
        check(qnn_result == 32'd84, "ket qua QNN end-to-end phai bang 84");
        check(leds == 10'd84, "CPU phai ghi ket qua QNN ra GPIO LED");
        check(uart_byte_0 == 8'h4F && uart_byte_1 == 8'h4B,
              "UART phai phat dung chuoi OK");

        $display("PASS tb_rv32_soc: %0d checks, cycles=%0d", checks, timeout);
        $finish;
    end

endmodule

`default_nettype wire
