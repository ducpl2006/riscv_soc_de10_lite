// ========================================
// Module ImmGen
// + Phân loại Imm theo từng Type
// ========================================

module ImmGen (

	input [31:0] InstrD,
	input [2:0] ImmSrc,
	
	output reg [31:0] Imm_Ext
);

	always @(*) begin
	
		case (ImmSrc) 
		
			// =============== I - TYPE ===============
			3'b000: Imm_Ext = {{20{InstrD[31]}}, InstrD[31:20]};
			
			
			// =============== S - TYPE ===============
			3'b001: Imm_Ext = {{20{InstrD[31]}}, InstrD[31:25], InstrD[11:7]};
			
			
			// =============== B - TYPE ===============
			3'b010: Imm_Ext = {{19{InstrD[31]}}, InstrD[31], InstrD[7], InstrD[30:25], InstrD[11:8], 1'b0};
			
			
			// =============== J - TYPE ===============
			3'b011: Imm_Ext = {{11{InstrD[31]}}, InstrD[31], InstrD[19:12], InstrD[20], InstrD[30:21], 1'b0};
			
			
			// =============== U - TYPE ===============
			3'b100: Imm_Ext = {InstrD[31:12], 12'b0};
			
			default: Imm_Ext = 32'b0;
		endcase
	
	end
	
endmodule