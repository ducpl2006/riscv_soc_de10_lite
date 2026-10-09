// ======================================
// Module Main_Decoder
// + Decode Instruction
//
// Version mới: FULL ISA RV32IM
// + Bổ sung: LB, LH, LBU, LHU, SB, SH
// + Bổ sung: MUL, MULH, MULHSU, MULHU
// + Bổ sung: DIV, DIVU, REM, REMU
// ======================================

module Main_Decoder (

	input [31:0] InstrD,
	
	// Fields
	output [6:0] opcode,
	output [2:0] funct3,
	output [6:0] funct7,
	output [4:0] rs1_addr,
	output [4:0] rs2_addr,
	output [4:0] rd_addr,
	
	// Type flag
	output reg is_rtype,
	output reg is_itype,
	output reg is_load,
	output reg is_store,
	output reg is_branch,
	output reg is_jal,
	output reg is_jalr,
	output reg is_lui,
	output reg is_auipc,
	output reg is_mul,
	output reg is_div
);

	// ==================================
	// Fields
	// ==================================
	assign opcode		= InstrD[6:0];
	assign funct3		= InstrD[14:12];
	assign funct7		= InstrD[31:25];
	assign rs1_addr		= InstrD[19:15];
	assign rs2_addr		= InstrD[24:20];
	assign rd_addr		= InstrD[11:7];

	// ==================================
	// Decode opcode
	// ==================================
	always @(*) begin
		
		// Khởi tạo giá trị ban đầu
		is_rtype	= 0;
		is_itype	= 0;
		is_load		= 0;
		is_store	= 0;
		is_branch	= 0;
		is_jal		= 0;
		is_jalr		= 0;
		is_lui		= 0;
		is_auipc	= 0;
		is_mul		= 0;
		is_div		= 0;
		
		case (opcode)

			7'b0110011:
			begin
				// RV32M
				if (funct7 == 7'b0000001) begin
					// MUL Group
					if (funct3[2] == 0) begin
						is_mul	= 1;
					end
					// DIV/REM Group
					else if (funct3[2] == 1) begin
						is_div	= 1;
					end
				end

				// RV32I - R-Type
				else begin
					is_rtype	= 1;			// R_Type (ADD, SUB, AND, OR, XOR,...)
				end
			end
			
			7'b0010011: is_itype		= 1;	// I_Type (ADDI, ANDI,...)
			
			7'b0000011: is_load			= 1;	// LW
			
			7'b0100011: is_store		= 1;	// SW
			
			7'b1100011: is_branch		= 1;	// BEQ, BNE, BLT, BGE
			
			7'b1101111: is_jal			= 1;	// JAL
			
			7'b1100111: is_jalr			= 1;	// JALR
			
			7'b0110111: is_lui			= 1;	// LUI
			
			7'b0010111: is_auipc		= 1;	// AUIPC
		
		endcase
		
	end

endmodule