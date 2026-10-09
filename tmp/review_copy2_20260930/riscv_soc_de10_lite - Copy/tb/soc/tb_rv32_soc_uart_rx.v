`timescale 1ns/1ps
`default_nettype none
// RX pad -> synchronizer -> FIFO -> registered bus -> RV32 load -> GPIO.
module tb_rv32_soc_uart_rx;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,rx=1;
    wire [7:0] leds;
    wire trap;
    wire [4:0] cause;
    wire [31:0] pc;
    integer b,watchdog,pops=0;
    localparam [7:0] BYTE=8'hA6;
    rv32_soc #(.CLOCK_HZ(1000000),.ROM_WORDS(16),.RAM_WORDS(16)) dut (
        .clk_i(clk),.rst_i(rst),.switches_i(10'd0),.leds_o(leds),.uart_rx_i(rx),.uart_tx_o(),
        .i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.i2c_scl_drive_low_o(),.i2c_sda_drive_low_o(),
        .halted_o(),.trap_valid_o(trap),.trap_cause_o(cause),.trap_pc_o(pc),
        .qnn_busy_o(),.qnn_done_o(),.qnn_result_o());
    always @(posedge clk) if(!rst && dut.u_uart.pop) pops<=pops+1;
    initial begin
        #1;
        dut.u_rom.u_storage.mem[0]=32'h200010B7;
        dut.u_rom.u_storage.mem[1]=32'h0040A103; // lw x2,STATUS
        dut.u_rom.u_storage.mem[2]=32'h00417113; // andi x2,x2,RX_VALID
        dut.u_rom.u_storage.mem[3]=32'hFE010CE3; // beq x2,x0,-8
        dut.u_rom.u_storage.mem[4]=32'h0080A183; // lw x3,RX_DATA; pop exactly once
        dut.u_rom.u_storage.mem[5]=32'h20000237;
        dut.u_rom.u_storage.mem[6]=32'h00322023;
        dut.u_rom.u_storage.mem[7]=32'h00100073;
        repeat(3) @(negedge clk); rst=0;
        repeat(30) @(negedge clk);
        rx=0; repeat(9) @(negedge clk);
        for(b=0;b<8;b=b+1) begin rx=BYTE[b]; repeat(9) @(negedge clk); end
        rx=1; repeat(9) @(negedge clk);
        watchdog=0;
        while(!trap && watchdog<200) begin @(negedge clk); watchdog=watchdog+1; end
        if(!trap || cause!==3 || pc!==28 || leds!==BYTE || pops!=1 || !dut.u_uart.empty)
            $fatal(1,"UART RX SoC integration: cause=%0d pc=%h leds=%h pops=%0d",cause,pc,leds,pops);
        $display("PASS tb_rv32_soc_uart_rx: pad-to-CPU/GPIO, polling, registered response, exactly one pop");
        $finish;
    end
    initial begin #20000; $fatal(1,"SoC UART RX timeout"); end
endmodule
`default_nettype wire
