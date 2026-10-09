// ==========================================
// Module Hex7_Seg
// + Module hiển thị màn hình LED 7 đoạn
// ==========================================

module Hex7_Seg (

    input clk,
	input reset,
	input write_en,
	input [31:0] wr_data,
	
	output [6:0] HEX0,
	output [6:0] HEX1,
	output [6:0] HEX2,
	output [6:0] HEX3,
	output [6:0] HEX4,
	output [6:0] HEX5
);

    reg [23:0] seg_reg;
	
	always @(posedge clk) begin
		
		if (!reset) begin
			seg_reg <= 24'b0;
		end
		
		else if (write_en) begin
			seg_reg <= wr_data[23:0];
		end
		
	end
	
	Seg7_Decoder d0 (.data(seg_reg[3:0]),   .seg7_display(HEX0));
	Seg7_Decoder d1 (.data(seg_reg[7:4]),   .seg7_display(HEX1));
	Seg7_Decoder d2 (.data(seg_reg[11:8]),  .seg7_display(HEX2));
	Seg7_Decoder d3 (.data(seg_reg[15:12]), .seg7_display(HEX3));
	Seg7_Decoder d4 (.data(seg_reg[19:16]), .seg7_display(HEX4));
	Seg7_Decoder d5 (.data(seg_reg[23:20]), .seg7_display(HEX5));

endmodule