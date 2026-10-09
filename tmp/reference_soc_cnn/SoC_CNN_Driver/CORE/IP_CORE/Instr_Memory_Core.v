// ==========================================
// Instruction Memory M9K
// ==========================================

module Instr_Memory_Core (

	input clk,
	
	input we,
	input [9:0] addr,
	input [31:0] wr_data,
	
	output reg [31:0] rd_data
);

	(* ramstyle = "M9K" *) 
	reg [31:0] mem [0:1023];
	
//	initial begin
//		$readmemh ("firmware.hex", mem);
//	end

	always @(posedge clk) begin
	
		if (we) begin
			mem [addr] <= wr_data;
		end
		
		rd_data <= mem[addr];
	
	end
	
endmodule