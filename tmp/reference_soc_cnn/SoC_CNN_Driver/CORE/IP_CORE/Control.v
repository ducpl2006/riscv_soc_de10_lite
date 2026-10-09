// =====================================
// Module Control
// + Control Signal
// =====================================

module Control (

	input is_rtype,
	input is_itype,
	input is_load,
	input is_store,
	input is_branch,
	input is_jal,
	input is_jalr,
	input is_lui,
	input is_auipc,
	input is_mul,
	input is_div,
	
	input [2:0] funct3,
	
	output reg RegWrite,
	output reg MemRead,
	output reg MemWrite,
	output reg [1:0] ResultSrc,	// MUX Write Back
	output reg AluSrcA,
	output reg AluSrcB,
	output reg [1:0] ALUOp,
	output reg [2:0] ImmSel,
	output reg Branch,
	output reg Jump,
	output reg BrUn,
	output reg MDU_En			// Kích hoạt MDU ở EX stage
);

	
	always @(*) begin
	
		// =============== DEFAULT ===============
		RegWrite	= 0;
		MemRead		= 0;
		MemWrite	= 0;
		ResultSrc	= 2'b00;
		AluSrcA		= 0;
		AluSrcB		= 0;
		ALUOp		= 2'b00;
		ImmSel		= 3'b000;
		Branch		= 0;
		Jump		= 0;
		BrUn		= 0;
		MDU_En		= 0;
		
		
		// =============== R_Type ================
		if (is_rtype) begin
			AluSrcA		= 0;
			AluSrcB		= 0;
			ALUOp		= 2'b10;
			RegWrite	= 1;
			ResultSrc	= 2'b00;
		end
		
		
		// =============== I_Type ================
		else if (is_itype) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			ALUOp		= 2'b10;
			RegWrite	= 1;
			ResultSrc	= 2'b00;
			ImmSel		= 3'b000;
		end
		
		
		// =============== LOAD ==================
		else if (is_load) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			RegWrite	= 1;
			MemRead		= 1;
			ResultSrc	= 2'b01;
			ImmSel		= 3'b000;
		end
		
		
		// =============== STORE =================
		else if (is_store) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			MemWrite	= 1;
			ImmSel		= 3'b001;
		end
		
		
		// =============== BRANCH ================
		else if (is_branch) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			ALUOp		= 2'b01;
			Branch		= 1;
			ImmSel		= 3'b010;
			
			// Select unsigned/signed
			case (funct3) 
			
				3'b110,
				3'b111:  BrUn = 1;
				
				default: BrUn = 0;
			
			endcase
			
		end
		
		
		// =============== JAL ===================
		else if (is_jal) begin
			AluSrcA		= 1;
			AluSrcB		= 1;
			RegWrite	= 1;
			Jump		= 1;
			ResultSrc	= 2'b10;
			ImmSel		= 3'b011;
		end
		
		
		// =============== JALR ==================
		else if (is_jalr) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			RegWrite	= 1;
			Jump		= 1;
			ResultSrc	= 2'b10;
			ImmSel		= 3'b000;
		end
		
		
		// =============== LUI ===================
		else if (is_lui) begin
			AluSrcA		= 0;
			AluSrcB		= 1;
			ALUOp		= 2'b11;
			RegWrite	= 1;
			ResultSrc	= 2'b00;
			ImmSel		= 3'b100;
		end
		
		
		// =============== AUIPC =================
		else if (is_auipc) begin
			AluSrcA		= 1;
			AluSrcB		= 1;
			RegWrite	= 1;
			ResultSrc	= 2'b00;
			ImmSel		= 3'b100;
		end

		// =============== MUL/DIV =================
		else if (is_mul || is_div) begin
			AluSrcA		= 0;		// rs1
			AluSrcB		= 0;		// rs2 (Giống R-Type)
			RegWrite	= 1;		// Ghi rd
			ResultSrc	= 2'b00;	// ALU path - sẽ bị override bởi MUX MDU/ALU ở EX
			MDU_En		= 1;
		end
	
	end
	
endmodule