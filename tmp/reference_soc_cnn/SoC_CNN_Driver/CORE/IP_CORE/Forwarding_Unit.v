// ====================================
// Module Forwarding_Unit
// ====================================

module Forwarding_Unit (

	input RegWriteM,			// Insruction ở MEM có ghi vào Register không
	input RegWriteW_fwd,			
	
	input [4:0] RD_M,			// Thanh ghi đích của Instruction ở MEM
	input [4:0] RD_W,			// Thanh ghi đích ở WB stage
	
	input [4:0] RS1_E,			// Từ Decode stage
	input [4:0] RS2_E,			// Từ Decode stage
	
	// -----------------------
	// Output sang EX satge
	// -----------------------
	output reg [1:0] ForwardA_E,
	output reg [1:0] ForwardB_E
);

	always @(*) begin
		
		// =============== DEFAULT ===============
		ForwardA_E = 2'b00;
		ForwardB_E = 2'b00;
		
		
		// =============== Forward A ===============
		if (RegWriteM && (RD_M != 0) && (RD_M == RS1_E)) begin
			ForwardA_E = 2'b10;
		end
		
		else if (RegWriteW_fwd && (RD_W != 0) && (RD_W == RS1_E)) begin
			ForwardA_E = 2'b01;
		end
		
		// =============== Forward B ===============
		if (RegWriteM && (RD_M != 0) && (RD_M == RS2_E)) begin
			ForwardB_E = 2'b10;
		end
		
		else if (RegWriteW_fwd && (RD_W != 0) && (RD_W == RS2_E)) begin
			ForwardB_E = 2'b01;
		end
		
	end

endmodule