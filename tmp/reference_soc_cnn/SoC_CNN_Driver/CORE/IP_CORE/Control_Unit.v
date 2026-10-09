// ======================================================
// Module Control_Unit
// + Decoder
// + Control signal CPU
// ======================================================

module Control_Unit (

	input [31:0] InstrD, 
	
	output RegWrite,
	output MemRead,
	output MemWrite,
	output [1:0] ResultSrc,
	output AluSrcA,
	output AluSrcB,
	output [2:0] ImmSel,
	output Branch,
	output Jump,
	output BrUn,
	
	output [3:0] ALUControl,

	output MDU_En 				// Kích hoạt MDU ở EX stage
);

	// =====================================
	// Decode --> Control
	// =====================================
	wire [6:0] opcode;
	wire [2:0] funct3;
	wire [6:0] funct7;
	wire [4:0] rs1_addr;
	wire [4:0] rs2_addr;
	wire [4:0] rd_addr;
	
	wire is_rtype;
	wire is_itype;
	wire is_load;
	wire is_store;
	wire is_branch;
	wire is_jal;
	wire is_jalr;
	wire is_lui;
	wire is_auipc;
	wire is_mul;
	wire is_div;
	
	wire [1:0] ALUOp;

	// ============== DECODE ==============
	Main_Decoder decode (
	
		// Input
		.InstrD			(InstrD),
		
		// Output
		// Fields
		.opcode			(opcode),
		.funct3			(funct3),
		.funct7			(funct7),
		.rs1_addr		(rs1_addr),
		.rs2_addr		(rs2_addr),
		.rd_addr		(rd_addr),
		
		// Type Flag
		.is_rtype		(is_rtype),
		.is_itype		(is_itype),
		.is_load		(is_load),
		.is_store		(is_store),
		.is_branch		(is_branch),
		.is_jal			(is_jal),
		.is_jalr		(is_jalr),
		.is_lui			(is_lui),
		.is_auipc		(is_auipc),
		.is_mul			(is_mul),
		.is_div			(is_div)
	);
	
	
	// ============== CONTROL ==============
	Control control_signal (
	
		// Input
		.is_rtype		(is_rtype),
		.is_itype		(is_itype),
		.is_load		(is_load),
		.is_store		(is_store),
		.is_branch		(is_branch),
		.is_jal			(is_jal),
		.is_jalr		(is_jalr),
		.is_lui			(is_lui),
		.is_auipc		(is_auipc),
		.is_mul			(is_mul),
		.is_div			(is_div),
		
		.funct3			(funct3),
		
		// Ouput
		.RegWrite		(RegWrite),
		.MemRead		(MemRead),
		.MemWrite		(MemWrite),
		.ResultSrc		(ResultSrc),
		.AluSrcA		(AluSrcA),
		.AluSrcB		(AluSrcB),
		.ALUOp			(ALUOp),
		.ImmSel			(ImmSel),
		.Branch			(Branch),
		.Jump			(Jump),
		.BrUn			(BrUn),
		.MDU_En			(MDU_En)
	);
	
	
	// =====================================
	// ALU Control
	// =====================================
	ALU_Decoder alu_control (
		
		// Input
		.ALUOp			(ALUOp),
		.funct3			(funct3),
		.funct7			(funct7),
		.is_rtype		(is_rtype),
		
		// Ouput			
		.ALUControl		(ALUControl)
	);

endmodule