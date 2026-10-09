// ==================================================
// Module ALU
// + Bộ ALU
// ==================================================

module ALU (

	input [31:0] SrcA,
	input [31:0] SrcB,
	
	input [3:0] ALUControlE,
	
	output reg [31:0] ResultE,
	output Zero
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
	
	
	// =============== ALU Logic ===============
	always @(*) begin
	
		case (ALUControlE) 
		
			ALU_ADD:	ResultE	= SrcA + SrcB;
			ALU_SUB:	ResultE	= SrcA - SrcB;
			
			ALU_AND: 	ResultE	= SrcA & SrcB;
			ALU_OR:		ResultE	= SrcA | SrcB;
			ALU_XOR:	ResultE	= SrcA ^ SrcB;
			
			ALU_SLL: 	ResultE	= SrcA << SrcB[4:0];
			ALU_SRL: 	ResultE	= SrcA >> SrcB[4:0];
			ALU_SRA:	ResultE	= $signed(SrcA) >>> SrcB[4:0];
			
			ALU_SLT:	ResultE	= ($signed(SrcA) < $signed(SrcB)) ? 32'd1 : 32'd0;
			ALU_SLTU: 	ResultE = (SrcA < SrcB) ? 32'd1 : 32'd0;
			
			ALU_PASS: 	ResultE = SrcB;		// Dùng cho LUI/AUIPC nếu cần
			
			default: 	ResultE	= 32'd0;
		
		endcase
	
	end
	
	
	// =============== ZERO FLAG ===============
	assign Zero = (ResultE == 32'd0);

endmodule