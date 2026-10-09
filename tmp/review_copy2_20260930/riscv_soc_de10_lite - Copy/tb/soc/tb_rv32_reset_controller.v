`timescale 1ns/1ps
`default_nettype none
module tb_rv32_reset_controller;
    reg clk=0, key_n=1;
    always #5 clk=~clk;
    wire rst, rst_short;
    integer n;
    wire halted;
    reset_controller #(.POR_CYCLES(5)) dut (.clk_i(clk),.key_reset_n_i(key_n),.rst_o(rst));
    reset_controller #(.POR_CYCLES(1)) short_por (.clk_i(clk),.key_reset_n_i(key_n),.rst_o(rst_short));
    rv32_soc #(.ROM_WORDS(8),.RAM_WORDS(8)) soc (
        .clk_i(clk),.rst_i(rst),.switches_i(10'd0),.leds_o(),.uart_rx_i(1'b1), .uart_tx_o(),
        .i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.i2c_scl_drive_low_o(),.i2c_sda_drive_low_o(),
        .halted_o(halted),.trap_valid_o(),.trap_cause_o(),.trap_pc_o(),
        .qnn_busy_o(),.qnn_done_o(),.qnn_result_o());
    initial begin
        #1;
        if (rst !== 1 || rst_short !== 1) $fatal(1,"POR must assert without KEY event");
        soc.u_rom.u_storage.mem[0]=32'h00100073;
        for (n=1;n<=8;n=n+1) begin
            @(posedge clk); #1;
            if (rst !== (n<8) || rst_short !== (n<4)) $fatal(1,"POR duration n=%0d",n);
            if (soc.u_timer.compare_q !== 64'hFFFFFFFFFFFFFFFF || soc.u_qnn.busy_q !== 0 ||
                soc.u_uart.busy_o !== 0 || halted !== 0)
                $fatal(1,"POR did not initialize SoC state");
        end
        repeat (20) @(negedge clk);
        if (!halted) $fatal(1,"SoC failed to boot after POR");
        #2; key_n=0; #1;
        if (!rst || !rst_short) $fatal(1,"KEY assert not asynchronous");
        repeat (3) @(negedge clk);
        #2; key_n=1; #1;
        if (!rst) $fatal(1,"KEY released reset asynchronously");
        for (n=1;n<=3;n=n+1) begin
            @(posedge clk); #1;
            if (rst !== (n<3)) $fatal(1,"KEY synchronous release");
        end
        repeat (20) @(negedge clk);
        if (!halted) $fatal(1,"SoC failed to reboot after KEY");
        $display("PASS tb_rv32_reset_controller: POR without KEY, boundary parameter, initialized SoC, synchronous release/reboot");
        $finish;
    end
    initial begin #10000; $fatal(1,"POR timeout"); end
endmodule
`default_nettype wire
