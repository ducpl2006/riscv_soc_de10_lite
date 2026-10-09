// ===============================================
// Module Mux_3_by_1
// + Module chọn giá trị cho AluIn1, AluIn2
// + Có Forwarding
// ===============================================

module Mux_3_by_1 (

	input [31:0] a,
	input [31:0] b,
	input [31:0] c,
	
	input [1:0] s,
	
	output reg [31:0] d
);

	always @(*) begin
	
		case (s)
		
			2'b00:	d = a;	// Normal (No Forwarding)
			
			2'b01:	d = b;	// Từ WB Stage
			
			2'b10:	d = c;	// Từ Mem stage
			
			default: d = a;
			
		endcase
		
	end
	
endmodule