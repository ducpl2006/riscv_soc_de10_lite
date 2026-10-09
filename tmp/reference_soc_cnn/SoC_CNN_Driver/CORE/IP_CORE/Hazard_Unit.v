// =====================================
// Module Hazard_Unit
// Forward + Stall
// =====================================

//`include "Forwarding_Unit.v"
//`include "Stall_Unit.v"

module Hazard_Unit (

	input clk,
	input reset,

	// Forwarding
	input RegWriteM,
	input RegWriteW_fwd,
	input [4:0] RD_M,
	input [4:0] RD_W,
	input [4:0] RS1_E,
	input [4:0] RS2_E,

	// Stall
	input MemReadE,
	input [4:0] RD_E,
	input [4:0] RS1_D,
	input [4:0] RS2_D,

	// BRAM stall
	input MemReadM,
	input MemWriteM,

	// Branch
	input PCSrcE,

	input mem_ready,

	input MDU_Busy,

	//Ouput
	output [1:0] ForwardA_E,
	output [1:0] ForwardB_E,
	output StallF,
	output StallD,
	output StallE,
	output StallM,
	output HoldE,
	output FlushD,
	output FlushE

);

	// =============== FORWARDING ===============
	Forwarding_Unit forward (
	
		// Input 
		.RegWriteM			(RegWriteM),
		.RegWriteW_fwd			(RegWriteW_fwd),
		.RD_M				(RD_M),
		.RD_W				(RD_W),
		.RS1_E				(RS1_E),
		.RS2_E				(RS2_E),
		
		// Output
		.ForwardA_E			(ForwardA_E),
		.ForwardB_E			(ForwardB_E)
	);
	
	
	// =============== STALL ===============
	wire StallF_lw, StallD_lw, FlushE_stall;

	Stall_Unit stall (

		// Input
		.MemReadE			(MemReadE),
		.RD_E				(RD_E),
		.RS1_D				(RS1_D),
		.RS2_D				(RS2_D),

		.StallF				(StallF_lw),
		.StallD				(StallD_lw),
		.FlushE				(FlushE_stall)
	);


	// =============== BRAM Stall ===============
	// reg bram_wait;

	// always @(posedge clk or negedge reset) begin
	// 	if (!reset) bram_wait <= 1'b0;
	// 	else        bram_wait <= MemReadM && !bram_wait;
	// end

	// wire bram_stall = MemReadM && !bram_wait;

	wire axi_stall;

	assign axi_stall = (MemReadM || MemWriteM) && !mem_ready;

	wire mdu_stall;
	
	assign mdu_stall = MDU_Busy;


	// =============== Flush / Stall Outputs ===============
	assign StallF  = StallF_lw | axi_stall | mdu_stall;
	assign StallD  = StallD_lw | axi_stall | mdu_stall;
	assign StallE  = axi_stall | mdu_stall;
	assign StallM  = axi_stall | mdu_stall;
	assign HoldE   = axi_stall | mdu_stall;
	// Mask FlushD khi MEM/MDU stall: giữ branch/jump ở EX cho tới khi stall nhả,
	// tránh nuốt lệnh nhảy (PC bị StallF giữ nên chưa kịp nạp target)
	assign FlushD  = PCSrcE & ~(axi_stall | mdu_stall);
	assign FlushE  = FlushE_stall;

endmodule