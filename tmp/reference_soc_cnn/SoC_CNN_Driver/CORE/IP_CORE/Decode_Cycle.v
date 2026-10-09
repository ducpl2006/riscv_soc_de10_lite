// =========================================
// Module Decode_Cycle
// + Decode stage
// =========================================

module Decode_Cycle (

	input clk,
	input reset,
	
	// -----------------------------
	// Từ Write Back (WB stage)
	// -----------------------------
	input RegWriteW,			// Tín hiệu có ghi vào Register hay không
	input [4:0] RDW,			// Địa chỉ thanh ghi đích
	input [31:0] ResultW,		// Dữ liệu ghi vào Register
	
	
	// -----------------------------
	// Từ Fetch (IF stage)
	// -----------------------------
	input [31:0] InstrD,
	input [31:0] PCD,					// Địa chỉ PC hiện tại
	input [31:0] PCPlus4D,
	
	// Hazard
	input FlushD,
	input StallD,
	input HoldE,
	
	// -----------------------------
	// Output đi sang Exceucte
	// -----------------------------
	output RegWriteE,					// Tín hiện điều khiển Instr ở EX có ghi vào Register không
	output AluSrcAE,
	output AluSrcBE,
	output MemWriteE,					// Tín hiệu điều khiển Instr ở EX có ghi vào Data Memory không
	output MemReadE,
	output [1:0] ResultSrcE,			// Chọn dữ liệu WB
	output BranchE,						// Lệnh Branch
	output JumpE,						// Lệnh Jump
	output BrUnE,
	output [3:0] ALUControlE,	
	output MDU_EnE,

	output [2:0] funct3E,
	
	// -----------------------------
	// Data Path
	// -----------------------------
	output [31:0] RD1_E,				// Giá trị rs1 (data)
	output [31:0] RD2_E,				// Giá trị rs2 (data)
	output [31:0] Imm_Ext_E,
	
	// -----------------------------
	// Register Address
	// -----------------------------
	output [4:0] RS1_E,
	output [4:0] RS2_E,
	output [4:0] RD_E,
	
	output [4:0] RS1_D,
	output [4:0] RS2_D,
	
	// -----------------------------
	// PC
	// -----------------------------
	output [31:0] PCE,
	output [31:0] PCPlus4E
);

	wire RegWriteD;
	wire MemReadD;
	wire MemWriteD;
	wire [1:0] ResultSrcD;
	wire AluSrcAD;
	wire AluSrcBD;
	wire [2:0] ImmSrcD;
	wire BranchD;
	wire JumpD;
	wire BrUnD;
	wire [3:0] ALUControlD;
	wire MDU_EnD;
	
	wire [2:0] funct3D;
	
	wire [31:0] RD1_D;
	wire [31:0] RD2_D;
	wire [31:0] Imm_Ext_D;
	
	
	reg RegWriteD_r;
	reg MemReadD_r;
	reg MemWriteD_r;
	reg [1:0] ResultSrcD_r;
	reg AluSrcAD_r;
	reg AluSrcBD_r;
	reg BranchD_r;
	reg JumpD_r;
	reg BrUnD_r;
	reg [3:0] ALUControlD_r;
	reg MDU_EnD_r;
	
	reg [2:0] funct3D_r;
	
	reg [31:0] RD1_D_r;
	reg [31:0] RD2_D_r;
	reg [31:0] Imm_Ext_D_r;
	
	reg [4:0] RS1_D_r;
	reg [4:0] RS2_D_r;
	reg [4:0] RD_D_r;
	
	reg [31:0] PCD_r;
	reg [31:0] PCPlus4D_r;

	// =============== Control Unit ===============
	Control_Unit control_top (
		
		// Input
		.InstrD			(InstrD),
		
		// Ouput
		.RegWrite		(RegWriteD),
		.MemRead		(MemReadD),
		.MemWrite		(MemWriteD),
		.ResultSrc		(ResultSrcD),
		.AluSrcA		(AluSrcAD),
		.AluSrcB		(AluSrcBD),
		.ImmSel			(ImmSrcD),
		.Branch			(BranchD),
		.Jump			(JumpD),
		.BrUn			(BrUnD),
		.ALUControl		(ALUControlD),
		.MDU_En 		(MDU_EnD)
	);
	

	// =============== Register File ===============
	Register_File regfile (
		
		// Input
		.clk			(clk),
		.reset			(reset),
		
		.we				(RegWriteW),
		
		.rs1_addr		(InstrD[19:15]),
		.rs2_addr		(InstrD[24:20]),
		.rd_addr		(RDW),
		
		.write_data		(ResultW),
		
		// Output
		.rs1_data		(RD1_D),
		.rs2_data		(RD2_D)
	);
	
	
	// =============== Imm Generator ===============
	ImmGen imm_type (
		
		// Input
		.InstrD			(InstrD),
		.ImmSrc			(ImmSrcD),
		
		// Output
		.Imm_Ext		(Imm_Ext_D)
	);
	
	
	// =============== Instruction ===============
	assign funct3D = InstrD[14:12];
	
	always @(posedge clk or negedge reset) begin
	
		if (!reset) begin
			RegWriteD_r		<= 0;
			MemReadD_r		<= 0;
			MemWriteD_r		<= 0;
			ResultSrcD_r	<= 2'b00;
			AluSrcAD_r		<= 0;
			AluSrcBD_r		<= 0;
			BranchD_r		<= 0;
			JumpD_r			<= 0;
			BrUnD_r			<= 0;
			ALUControlD_r	<= 4'b0000;
			MDU_EnD_r		<= 0;
			
			funct3D_r		<= 3'b000;
			
			RD1_D_r			<= 32'h0000_0000;
			RD2_D_r			<= 32'h0000_0000;
			Imm_Ext_D_r		<= 32'h0000_0000;
			
			RS1_D_r			<= 5'b00000;
			RS2_D_r			<= 5'b00000;
			RD_D_r			<= 5'b00000;
			
			PCD_r			<= 32'h0000_0000;
			PCPlus4D_r		<= 32'h0000_0000;
		end
		
		else if (FlushD) begin
			RegWriteD_r		<= 0;
			MemReadD_r		<= 0;
			MemWriteD_r		<= 0;
			ResultSrcD_r	<= 2'b00;
			AluSrcAD_r		<= 0;
			AluSrcBD_r		<= 0;
			BranchD_r		<= 0;
			JumpD_r			<= 0;
			BrUnD_r			<= 0;
			ALUControlD_r	<= 4'b0000;
			MDU_EnD_r		<= 0;
			
			funct3D_r		<= 3'b000;
			
			RD1_D_r			<= 32'h0000_0000;
			RD2_D_r			<= 32'h0000_0000;
			Imm_Ext_D_r		<= 32'h0000_0000;
			
			RS1_D_r			<= 5'b00000;
			RS2_D_r			<= 5'b00000;
			RD_D_r			<= 5'b00000;
			
			PCD_r			<= 32'h0000_0000;
			PCPlus4D_r		<= 32'h0000_0000;
		end

		// BRAM stall: giữ nguyên toàn bộ ID/EX để I1 re-execute cycle sau
		else if (HoldE) begin
		end

		// Thêm tín hiệu StallD
		else if (StallD) begin
			// Bubble: Chỉ zero control 
			RegWriteD_r		<= 0;
			MemReadD_r		<= 0;
			MemWriteD_r		<= 0;
			ResultSrcD_r	<= 2'b00;
			AluSrcAD_r		<= 0;
			AluSrcBD_r		<= 0;
			BranchD_r		<= 0;
			JumpD_r			<= 0;
			BrUnD_r			<= 0;
			ALUControlD_r	<= 4'b0000;
			MDU_EnD_r		<= 0;
			
			funct3D_r		<= 3'b000;
			
			// Giữ data + address từ input
			RD1_D_r			<= RD1_D;
			RD2_D_r			<= RD2_D;
			Imm_Ext_D_r		<= Imm_Ext_D;
			
			RS1_D_r			<= InstrD[19:15];
			RS2_D_r			<= InstrD[24:20];
			//RD_D_r			<= InstrD[11:7];
			RD_D_r			<= 5'b0;

			PCD_r			<= PCD;
			PCPlus4D_r		<= PCPlus4D;
		end
		
		else if (!StallD) begin
			RegWriteD_r		<= RegWriteD;
			MemReadD_r		<= MemReadD;
			MemWriteD_r		<= MemWriteD;
			ResultSrcD_r	<= ResultSrcD;
			AluSrcAD_r		<= AluSrcAD;
			AluSrcBD_r		<= AluSrcBD;
			BranchD_r		<= BranchD;
			JumpD_r			<= JumpD;
			BrUnD_r			<= BrUnD;
			ALUControlD_r	<= ALUControlD;
			MDU_EnD_r		<= MDU_EnD;
			
			funct3D_r		<= funct3D;
			
			RD1_D_r			<= RD1_D;
			RD2_D_r			<= RD2_D;
			Imm_Ext_D_r		<= Imm_Ext_D;
			
			RS1_D_r			<= InstrD[19:15];
			RS2_D_r			<= InstrD[24:20];
			RD_D_r			<= InstrD[11:7];
			
			PCD_r			<= PCD;
			PCPlus4D_r		<= PCPlus4D;
		end
		
	end
	
	
	// =============== OUTPUT ===============
	
	assign RegWriteE		= RegWriteD_r;
	assign MemReadE			= MemReadD_r;
	assign MemWriteE		= MemWriteD_r;
	assign AluSrcAE			= AluSrcAD_r;
	assign AluSrcBE			= AluSrcBD_r;
	assign ResultSrcE		= ResultSrcD_r;
	assign BranchE			= BranchD_r;
	assign JumpE			= JumpD_r;
	assign BrUnE			= BrUnD_r;
	assign ALUControlE		= ALUControlD_r;
	assign MDU_EnE			= MDU_EnD_r;
	
	assign funct3E			= funct3D_r;
	
	assign RD1_E			= RD1_D_r;
	assign RD2_E			= RD2_D_r;
	assign Imm_Ext_E		= Imm_Ext_D_r;
	
	assign RS1_E			= RS1_D_r;
	assign RS2_E			= RS2_D_r;
	assign RD_E				= RD_D_r;
	
	assign RS1_D			= InstrD[19:15];
	assign RS2_D			= InstrD[24:20];
	
	assign PCE				= PCD_r;
	assign PCPlus4E			= PCPlus4D_r;
	
endmodule