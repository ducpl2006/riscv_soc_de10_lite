`timescale 1ns/1ps
`default_nettype none

// Core -> fabric -> MMIO tests; no firmware image or accelerator model is used.
module tb_rv32_soc_mmio;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg scl_input = 1;
    wire [7:0] leds;
    wire halted, trap;
    wire [4:0] cause;
    wire [31:0] trap_pc;
    integer watchdog, checks = 0;
    rv32_soc #(.ROM_WORDS(16), .RAM_WORDS(16)) dut (
        .clk_i(clk), .rst_i(rst), .switches_i(10'h2A5), .leds_o(leds),
        .uart_rx_i(1'b1), .uart_tx_o(), .i2c_scl_i(scl_input), .i2c_sda_i(1'b1),
        .i2c_scl_drive_low_o(), .i2c_sda_drive_low_o(),
        .halted_o(halted), .trap_valid_o(trap), .trap_cause_o(cause),
        .trap_pc_o(trap_pc), .qnn_busy_o(), .qnn_done_o(), .qnn_result_o());
    // Tăng tốc watchdog trong mô phỏng; giữ nguyên bus/core và chương trình thật.
    defparam dut.u_i2c.TIMEOUT_CYCLES = 48;

    task run_case;
        input [19:0] upper_address;
        input [11:0] offset;
        input write_access;
        input byte_access;
        input [4:0] expected_cause;
        input [31:0] expected_pc;
        input [7:0] expected_leds;
        begin
            @(negedge clk); rst = 1;
            dut.u_rom.u_storage.mem[0] = {upper_address, 5'd1, 7'b0110111};
            dut.u_rom.u_storage.mem[1] = 32'h00300113; // addi x2,x0,3
            if (write_access)
                dut.u_rom.u_storage.mem[2] = {offset[11:5], 5'd2, 5'd1,
                    byte_access ? 3'b000 : 3'b010, offset[4:0], 7'b0100011};
            else
                dut.u_rom.u_storage.mem[2] = {offset, 5'd1, 3'b010, 5'd2, 7'b0000011};
            dut.u_rom.u_storage.mem[3] = 32'h00100073;
            repeat (3) @(negedge clk); rst = 0;
            watchdog = 0;
            while (!trap && watchdog < 200) begin @(negedge clk); watchdog = watchdog + 1; end
            if (!trap || !halted || cause !== expected_cause || trap_pc !== expected_pc || leds !== expected_leds)
                $fatal(1, "MMIO %h+%h write=%b cause=%0d pc=%h leds=%h",
                       upper_address, offset, write_access, cause, trap_pc, leds);
            checks = checks + 1;
        end
    endtask

    initial begin
        run_case(20'h20000, 12'h001, 1, 1, 3, 12, 8'h00); // GPIO SB outside 8-bit LED width is a no-op
        run_case(20'h20000, 12'h004, 0, 0, 3, 12, 0);       // switches read
        run_case(20'h20000, 12'h008, 0, 0, 5, 8, 0);        // reserved GPIO register
        run_case(20'h20000, 12'h010, 1, 0, 7, 8, 0);        // no 16-byte alias
        run_case(20'h20001, 12'h010, 0, 0, 5, 8, 0);        // UART bad offset terminates
        run_case(20'h20001, 12'h004, 1, 0, 7, 8, 0);        // UART status read-only
        run_case(20'h20002, 12'h008, 1, 0, 7, 8, 0);        // I2C status read-only
        run_case(20'h20004, 12'h000, 1, 0, 7, 8, 0);        // TIME read-only
        run_case(20'h00000, 12'h000, 1, 0, 7, 8, 0);        // ROM write
        run_case(20'h10000, 12'h040, 0, 0, 5, 8, 0);        // SRAM just out of range
        run_case(20'h30000, 12'h000, 0, 0, 5, 8, 0);        // unmapped region
        run_case(20'h20000, 12'hFFC, 0, 0, 5, 8, 0);        // GPIO full page, reserved offset
        run_case(20'h20001, 12'hFFC, 1, 0, 7, 8, 0);        // UART reserved write
        run_case(20'h20001, 12'h008, 0, 0, 5, 8, 0);        // UART empty RX read
        run_case(20'h20001, 12'h008, 1, 0, 7, 8, 0);        // UART RX read-only
        run_case(20'h20002, 12'h100, 1, 0, 7, 8, 0);        // I2C must not mirror DATA
        run_case(20'h20003, 12'hFFC, 0, 0, 5, 8, 0);        // QNN reserved offset
        run_case(20'h20003, 12'h004, 1, 0, 7, 8, 0);        // QNN STATUS read-only
        run_case(20'h20004, 12'h100, 0, 0, 5, 8, 0);        // timer must not mirror TIME_LO
        // Timeout phải đi qua peripheral -> fabric -> MEM -> trap tại đúng store.
        @(negedge clk); rst=1; scl_input=0;
        dut.u_rom.u_storage.mem[0] = 32'h200020B7; // lui x1,0x20002
        dut.u_rom.u_storage.mem[1] = 32'h08300113; // addi x2,x0,EXECUTE|START|STOP
        dut.u_rom.u_storage.mem[2] = 32'h0020A223; // sw x2,4(x1): bắt đầu lệnh
        dut.u_rom.u_storage.mem[3] = 32'h0020A023; // sw x2,0(x1): chờ rồi fault
        dut.u_rom.u_storage.mem[4] = 32'h200001B7; // lui x3,GPIO
        dut.u_rom.u_storage.mem[5] = 32'h0021A023; // store trẻ hơn không được thực hiện
        dut.u_rom.u_storage.mem[6] = 32'h00100073;
        repeat (3) @(negedge clk); rst=0;
        watchdog=0;
        while (!trap && watchdog<200) begin @(negedge clk); watchdog=watchdog+1; end
        if (!trap || !halted || cause !== 7 || trap_pc !== 12 || leds !== 0 || dut.u_i2c.busy_o)
            $fatal(1, "I2C timeout must produce precise store access fault, cause=%0d pc=%h", cause, trap_pc);
        checks=checks+1;
        $display("PASS tb_rv32_soc_mmio: %0d CPU/bus/MMIO cases", checks);
        $finish;
    end
    initial begin #100000; $fatal(1, "SoC MMIO timeout"); end
endmodule

`default_nettype wire
