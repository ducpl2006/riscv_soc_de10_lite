// =================================================
// Module ALU_Decoder
// + Xác định các phép toán mà ALU cần thưc hiện
// =================================================

module ALU_Decoder (

	input [1:0] ALUOp,
	input [2:0] funct3,
	input [6:0] funct7,
	input is_rtype,

	output reg [3:0] ALUControl
);

	// =============== ALU Encoding ===============
	localparam ALU_ADD	= 4'b0000;
	localparam ALU_SUB	= 4'b0001;
	localparam ALU_AND	= 4'b0010;
	localparam ALU_OR	= 4'b0011;
	localparam ALU_XOR	= 4'b0100;
	localparam ALU_SLL	= 4'b0101;
	localparam ALU_SRL	= 4'b0110;
	localparam ALU_SRA	= 4'b0111;
	localparam ALU_SLT	= 4'b1000;
	localparam ALU_SLTU	= 4'b1001;
	localparam ALU_PASS	= 4'b1010;
	
	
	always @(*) begin
	
		case (ALUOp)
			
			// =============== LOAD / STORE / AUIPC ===============
			2'b00:	ALUControl = ALU_ADD;
			
			// =============== BRANCH ===============
			2'b01: 	ALUControl = ALU_SUB;
			
			// =============== R-TYPE / I-TYPE ===============
			2'b10: begin
			
				case (funct3) 
				
					3'b000:	ALUControl = (funct7[5] && is_rtype) ? ALU_SUB : ALU_ADD;
					
					3'b111: ALUControl = ALU_AND;
					
					3'b110:	ALUControl = ALU_OR;
					
					3'b100:	ALUControl = ALU_XOR;
					
					3'b001: ALUControl = ALU_SLL;
					
					3'b101: ALUControl = (funct7[5]) ? ALU_SRA : ALU_SRL;
					
					3'b010:	ALUControl = ALU_SLT;
					
					3'b011:	ALUControl = ALU_SLTU;
					
					default: ALUControl = ALU_ADD;
				endcase
			
			end
			
			2'b11:	 ALUControl = ALU_PASS;
			
			default: ALUControl = ALU_ADD;
		endcase
	
	end
	
endmodule