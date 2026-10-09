// ====================================
// Module Writeback_Cycle
// + WB stage
// ====================================

module Writeback_Cycle (

	// ---------------------------
	// Input từ Memory stage
	// ---------------------------
	input RegWriteW,
	input [1:0] ResultSrcW,
	input [4:0] RD_W,
	input [31:0] PCPlus4W,
	input [31:0] ALU_ResultW,
	input [31:0] ReadDataW,
	
	
	// ---------------------------
	// Output về Register
	// ---------------------------
	output RegWriteW_out,
	output [4:0] RD_out,
	output reg [31:0] ResultW
);
	
	// ===============================
	// MUX chọn dữ liệu về Register
	// ===============================
	always @(*) begin
	
		case (ResultSrcW) 
		
			2'b00:	ResultW	= ALU_ResultW;
			
			2'b01:	ResultW	= ReadDataW;
			
			2'b10:	ResultW	= PCPlus4W;
			
			default:	ResultW	= 32'b0;
		endcase
	
	end
	
	
	// =============== OUTPUT ===============
	assign RegWriteW_out	= RegWriteW;
	assign RD_out			= RD_W;

endmodule