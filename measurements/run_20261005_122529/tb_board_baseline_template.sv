`timescale 1ns/1ps
module tb_board_baseline;
reg clk=0;
reg [1:0] key=2'b11;
wire [9:0] leds;
tri1 [1:0] gpio;
wire tx;
integer runs=0;
reg [7:0] a,b;
de10_lite_top dut(.MAX10_CLK1_50(clk),.KEY(key),.SW(10'h155),.LEDR(leds),.GPIO(gpio),.UART_RX(1'b1),.UART_TX(tx));
always #10 clk=~clk;
task uart_byte(output reg [7:0] value);
 integer n;
 begin
  @(negedge tx);
  repeat(651) @(negedge clk);
  for(n=0;n<8;n=n+1) begin
   value[n]=tx;
   repeat(434) @(negedge clk);
  end
  if(tx!==1'b1) $fatal(1,"UART stop bit");
 end
endtask
task boot_check;
 begin
  uart_byte(a);uart_byte(b);
  repeat(10) @(negedge clk);
  if({a,b}!==16'h4f4b) $fatal(1,"UART bytes: %h %h",a,b);
  if(leds[9]!==1'b1 || leds[8]!==1'b0 || leds[7:0]!==8'dEXPECTED_LED) $fatal(1,"LEDs: %h",leds);
  if(dut.u_soc.qnn_result_o!==32'dEXPECTED_RESULT || dut.u_soc.qnn_done_o!==1'b1) $fatal(1,"QNN result");
  if(dut.u_soc.trap_cause_o!==5'd3 || dut.u_soc.trap_pc_o!==32'h48) $fatal(1,"Breakpoint metadata");
  runs=runs+1;
  $display("PASS board baseline boot %0d: 50MHz, UART=OK, QNN=%0d, LED=%h, EBREAK@0x48",runs,dut.u_soc.qnn_result_o,leds);
 end
endtask
initial begin
 boot_check();
 key[0]=0;
 repeat(10) @(negedge clk);
 if(leds!==10'd0) $fatal(1,"KEY reset LEDs");
 key[0]=1;
 boot_check();
 $display("RESULT: PASS board baseline POR + KEY reset (behavioral RTL)");
 $finish;
end
initial begin
 repeat(40000) @(negedge clk);
 $fatal(1,"Board baseline timeout");
end
endmodule
