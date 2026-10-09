// ==================================================
// Module Execute_Cycle
// Execute Stage
// ==================================================

module Execute_Cycle (

	input clk,
	input reset,
	
	// ----------------------------
	// Nhóm Input (Từ ID sang EX)
	// ----------------------------

	// Dữ liệu từ Register
	input [31:0] RD1_E,
	input [31:0] RD2_E,
	
	// Immediate
	input [31:0] Imm_Ext_E,
	
	// Địa chỉ thanh ghi đích 
	input [4:0] RD_E,
	
	// Program Counter
	input [31:0] PCE,
	input [31:0] PCPlus4E,
	
	// Control Signal từ Decode
	input RegWriteE,
	input MemReadE,
	input MemWriteE,
	input AluSrcAE,
	input AluSrcBE,
	input [1:0] ResultSrcE,
	input BranchE,
	input JumpE,
	input BrUnE,
	input [3:0] ALUControlE,
	input MDU_EnE,				// Kích hoạt MDU
	
	input [2:0] funct3E,
	
	// -------------------------------------------
	// Nhóm Input (Từ các stage khác (forwarding)
	// -------------------------------------------
	
	// Write Back data
	input [31:0] ResultW,			// Giá trị vừa ghi về Register (WB stage) --> Dùng để forward
	
	// Forward control
	input [1:0] ForwardA_E,
	input [1:0] ForwardB_E,
	
	// Từ MEM
	input [31:0] ALU_ResultM,		// Kết quả ALU tính toán ở 1 cycle trước (lệnh instruction trước đó)
	
	// BRAM Stall
	input StallE,
	
	// -------------------------------
	// Nhóm Output sang Memory stage
	// -------------------------------
	
	// Control Signals
	output RegWriteM,
	output MemWriteM,
	output MemReadM,
	output [1:0] ResultSrcM,
	
	// Thanh ghi đích
	output [4:0] RD_M,						// Pass xuống WB để biết ghi vào đâu
	output [31:0] ALU_ResultM_out,			// Kết quả chính xác của EX (Kết quả của instruction hiện tại (tính ở EX) --> MEM stage)	
	
	// Write data (Cho store)
	output [31:0] WriteDataM,				// Giá trị của rs2 sau khi forwarding
	
	// PC
	output [31:0] PCPlus4M,
	
	// Branch Decision
	output PCSrcE,
	
	// Branch Target
	output [31:0] PCTargetE,

	// MUL/DIV
	output MDU_Busy,						// Báo Hazard_Unit stall cho DIV

	// LB/LH/LBU/LHU/SB/SH
	output [2:0] funct3M	
);

	// =============== FORWARDING ===============
	wire [31:0] ForwardA_out;
	wire [31:0] ForwardB_out;
	
	Mux_3_by_1 muxA (
	
		// Input
		.a			(RD1_E),
		.b			(ResultW),
		.c			(ALU_ResultM),
		.s			(ForwardA_E),
		
		// Output 
		.d			(ForwardA_out)
	);
	
	Mux_3_by_1 muxB (
	
		// Input
		.a			(RD2_E),
		.b			(ResultW),
		.c			(ALU_ResultM),
		.s			(ForwardB_E),
		
		// Output 
		.d			(ForwardB_out)
	);
	
	
	// =============== ALU Source ===============
	wire [31:0] SrcA;
	wire [31:0] SrcB;
	
	// Chọn giá trị cho ALU In 
	
	assign SrcA = (AluSrcAE) ? PCE : ForwardA_out;
	assign SrcB = (AluSrcBE) ? Imm_Ext_E : ForwardB_out;
	
	
	// =============== ALU ===============
	wire [31:0] ALU_ResultE;
	wire Zero;
	
	ALU alu (
	
		// Input
		.SrcA			(SrcA),
		.SrcB			(SrcB),
		.ALUControlE	(ALUControlE),
		
		// Output
		.ResultE		(ALU_ResultE),
		.Zero			(Zero)
	);
	
	
	// =============== BRANCH UNIT ===============
	wire PCSrc_Branch;
	
	Branch_Unit branch_unit (
	
		// Input 
		.A				(ForwardA_out),
		.B				(ForwardB_out),
		.funct3			(funct3E),
		.Branch			(BranchE),
		.BrUn			(BrUnE),
		
		// Output
		.PCSrc			(PCSrc_Branch)
	);

	// =============== MDU ===============
	wire [31:0] MDU_Result;
	wire 		MDU_Busy_w;
	wire [31:0] EX_Result;

	MDU mdu (

		.clk			(clk),
		.reset			(reset),

		.SrcA			(ForwardA_out),
		.SrcB			(ForwardB_out),
		.funct3 		(funct3E),
		.MDU_En 		(MDU_EnE),
		.Result 		(MDU_Result),
		.Busy 			(MDU_Busy_w)
	);
	
	assign EX_Result = MDU_EnE ? MDU_Result : ALU_ResultE;
	
	// =============== JUMP LOGIC ===============
	assign PCSrcE = PCSrc_Branch | JumpE;
	
	
	// =============== PC TARGET ADDRESS ===============
	wire [31:0] PC_jalr = (SrcA + Imm_Ext_E) & ~32'b1;
	
	assign PCTargetE = (JumpE && (AluSrcAE == 0)) ?
							 PC_jalr :		// JALR
							 (PCE + Imm_Ext_E);			// Branch/JAL
							 
	
	// =============== PIPELINE REGISTER ===============
	reg RegWriteE_r;
	reg MemReadE_r;
	reg MemWriteE_r;
	reg [1:0] ResultSrcE_r;
	reg [4:0] RD_E_r;
	reg [31:0] ALU_ResultE_r;
	reg [31:0] WriteDataE_r;
	reg [31:0] PCPlus4E_r;
	reg [2:0]  funct3E_r;
	
	always @(posedge clk or negedge reset) begin
	
		if (!reset) begin
			RegWriteE_r		<= 0;
			MemReadE_r		<= 0;
			MemWriteE_r		<= 0;
			ResultSrcE_r	<= 0;
			RD_E_r			<= 0;
			ALU_ResultE_r	<= 0;
			WriteDataE_r	<= 0;
			PCPlus4E_r		<= 0;
			funct3E_r		<= 3'b000;
		end
		
		else if (StallE) begin
			// Hold EX/MEM registers - giữ nguyên để LW ở MEM thêm 1 cycle
		end

		else begin
			RegWriteE_r		<= RegWriteE;
			MemReadE_r		<= MemReadE;
			MemWriteE_r		<= MemWriteE;
			ResultSrcE_r	<= ResultSrcE;
			RD_E_r			<= RD_E;
			ALU_ResultE_r	<= EX_Result;
			WriteDataE_r	<= ForwardB_out;		// Store data
			PCPlus4E_r		<= PCPlus4E;
			funct3E_r		<= funct3E;
		end
		
	end
	
	
	// =============== OUTPUT MEM ===============
	assign RegWriteM		= RegWriteE_r;
	assign MemReadM			= MemReadE_r;
	assign MemWriteM		= MemWriteE_r;
	assign ResultSrcM		= ResultSrcE_r;
	assign RD_M				= RD_E_r;
	assign ALU_ResultM_out	= ALU_ResultE_r;
	assign WriteDataM		= WriteDataE_r;
	assign PCPlus4M			= PCPlus4E_r;
	assign MDU_Busy			= MDU_Busy_w;
	assign funct3M			= funct3E_r;

endmodule