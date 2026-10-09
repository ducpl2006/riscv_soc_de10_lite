// =====================================================
// Module Fetch_Cycle
// + Fetch
// =====================================================

module Fetch_Cycle (
	
	// --------------------------
	// Nhóm Input từ hệ thống
	// --------------------------
	input clk,					// Clock hệ thống 50MHz
	input reset,
	
	// Control Signal từ EX satge (Fetch không tự quyết định, chỉ nhận kết quả từ EX)
	input PCSrcE,				// Tín hiệu quyết định có branch/jump hay không (= 0: chạy bình thường, = 1: nhảy)
	
	// Địa chỉ nhảy (Branch Target)
	// Được tính ở EX (PCTarget = PC + Imm)
	input [31:0] PCTargetE,		// Nếu Branch --> PC nhảy tới đây
	
	// ---------------------------
	// Hazard
	// ---------------------------
	input StallF,
	input StallD,
	input FlushD,
	
	
	// ---------------------------
	// Output sang Decode
	// ---------------------------
	output [31:0] InstrD,		// Instruction tại Decode stage
	
	output [31:0] PCD,			// PC tại Decode stage
	output [31:0] PCPlus4D		// PC + 4 tại Decode stage
);

	// ====================================
	// Tín hiệu nội bộ Fetch
	// ====================================
	wire [31:0] PCF;			// PC Current (Giá trị hiện tại của PC)
	wire [31:0] PC_F;			// PC next (Ouput của PC_MUX)
	wire [31:0] PCPlus4F;	// PC + 4 tại Fetch (PCF + 4)
	
	wire [31:0] InstrF;		// Instruction tại Fetch stage (Đọc từ Instruction Memory InstrF = mem[PCF])
	
	
	// ====================================
	// Pipeline Register (IF --> ID)
	// ====================================
	reg [31:0] InstrF_reg;		// Instruction đã được chốt sang Decode stage (InstrF --> InstrD)
	
	reg [31:0] PCF_reg;			// PC của InstrF_reg
	reg [31:0] PCPlus4F_reg;	//	PC + 4 của InstrF_reg

	// ===================================
	// FIX Bug delay 1 cycle PC, PCPus4
	// ===================================
	reg [31:0] PCF_prev;
	reg [31:0] PCPlus4F_prev;

	
	// ====================================
	// Declare PC MUX
	// ====================================
	PC_MUX pc_mux (
	
		// Input
		.din_0			(PCPlus4F),
		.din_1			(PCTargetE),
		.sel			(PCSrcE),
		
		// Output
		.mux_out		(PC_F)
	);
	
	
	// ====================================
	// Declare PC Counter
	// ====================================
	Program_Counter pc_counter (
	
		// Input
		.clk			(clk),
		.reset			(reset),
		.stall			(StallF),
		.PCNextF		(PC_F),
		
		// Ouput
		.PCF			(PCF)
	);
	
	
	// ===================================
	// Instrction Memory
	// ===================================
	Instr_Memory instruction_memory (
	
		// Input
		.clk			(clk),
		
		// CPU Interface
		.addr			(PCF),
		.instruction	(InstrF),
		
		// Bootloader
		.boot_mode		(1'b0),
		.we_boot		(1'b0),
		.addr_boot		(1'b0),
		.data_boot		(1'b0)
	);
	
	
	// ===================================
	// PC Adder (Plus 4)
	// ===================================
	PC_Adder pc_adder (
	
		// Input
		.pc_current		(PCF),
		.plus_value		(32'd4),
		
		// Output
		.PCPlus			(PCPlus4F)
	);
	
	
	// ===================================
	// Fetch Cycle Register Logic
	// ===================================
	always @(posedge clk or negedge reset) begin
		
		if (!reset) begin
			InstrF_reg		<= 32'h0000_0000;
			PCF_reg			<= 32'h0000_0000;
			PCPlus4F_reg	<= 32'h0000_0000;

			// Fix Bug delay 1 cycle
			//PCF_prev		<= 32'h0000_0000;
			//PCPlus4F_prev	<= 32'h0000_0000;
		end
		
		
		// =============== FLUSH - HAZARD ===============
		else if (FlushD) begin
			InstrF_reg		<= 32'h0000_0000;
			PCF_reg			<= 32'h0000_0000;
			PCPlus4F_reg	<= 32'h0000_0000;

			// Fix Bug delay 1 cycle
			//PCF_prev		<= 32'h0000_0000;
			//PCPlus4F_prev	<= 32'h0000_0000;
		end
		
		
		// =============== STALL - HAZARD ===============
		else if (!StallD) begin
			InstrF_reg		<= InstrF;
			//PCF_prev		<= PCF;
			PCF_reg			<= PCF;
			//PCPlus4F_prev	<= PCPlus4F;
			PCPlus4F_reg	<= PCPlus4F;
		end
		
//		else begin
//			InstrF_reg		<= InstrF;
//			PCF_reg			<= PCF;
//			PCPlus4F_reg	<= PCPlus4F;
//		end
		
	end
	
	
	// ===================================
	// Ouput (Chuyển sang Decode)
	// IF --> ID
	// ===================================
	assign InstrD		= InstrF_reg;
	assign PCD			= PCF_reg;
	assign PCPlus4D		= PCPlus4F_reg;

endmodule