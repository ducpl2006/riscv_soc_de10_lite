// ==============================================
// Module tb_Fetch_Cycle
// ==============================================

`timescale 1ns/1ps

module tb_Fetch_Cycle;

	reg clk;
	reg reset;
	
	reg PCSrcE;
	reg [31:0] PCTargetE;
	
	wire [31:0] InstrD;
	wire [31:0] PCD;
	wire [31:0] PCPlus4D;
	
	Fetch_Cycle fetch_dut (
		.clk			(clk),
		.reset		(reset),
		
		.PCSrcE		(PCSrcE),
		.PCTargetE	(PCTargetE),
		
		.InstrD		(InstrD),
		.PCD			(PCD),
		.PCPlus4D	(PCPlus4D)
	);
	
	
	// Clock 50MHz
	initial begin
		clk = 0;
		forever #10 clk = ~clk;
	end
	
	initial begin
		reset 		= 1'b0;
		PCSrcE		= 1'b0;
		PCTargetE	= 32'h0;
		
		#20 
		reset			= 1'b1;
		
		#200
		$finish;
	end
	
	
endmodule



// ==================================================================================================================
// ĐÁNH GIÁ TESTBENCH FETCH
// ------------------------------------------------------------------------------------------------------------------
/*
	* Có 1 delay cycle giữa PC và Instruction
	- Tại cycle 0: reset
	+ PCD = 0
	+ InstrD = 0
	--> Pipeline rỗng, chưa thực hiện các lệnh instruction
	
	- Tại cycle 1:
	+ PCF = 0: pc current (giá trị PC hiện tại khi thực hiện instruction)
	+ fetch mem[0]: Chưa có InstrD (Vì InstrD chậm 1 cycle --> do có register)
	
	- Tại cycle 2:
	+ PCD = 0 (Nhận PC từ PCF của Fetch)
	+ PCF = 4 (PC + 4 --> pc next)
	+ InstrD = mem[0] (InstrD đọc mem[0] để chuyển vào decode)
	
	==> Pipeline của Fetch và Decode (IF --> ID)
			+ Tại cycle 0: Fetch lệnh thứ 1
			+ Tại cycle 1: Decode lệnh thứ 1, fetch lệnh thứ 2
			
			==> CÁCH KIỂM TRA WAVEFORM: 
			+ Lệnh Decode (InstrD) luôn khớp với PCF của cycle trước
*/
// ==================================================================================================================