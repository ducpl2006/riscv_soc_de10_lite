// ==============================================
// Module Stall_Unit
// + Tạm dừng pipeline 1 cycle để chờ dữ liệu
// ==============================================

module Stall_Unit (

	input MemReadE,
	input [4:0] RD_E,
	input [4:0] RS1_D,
	input [4:0] RS2_D,
	
	output StallF,
	output StallD,
	output FlushE
);

	wire lw_stall;
	
	assign lw_stall = MemReadE &&
							((RD_E == RS1_D) || (RD_E == RS2_D)) &&
							(RD_E != 0);
							
	assign StallF	= lw_stall;
	assign StallD	= lw_stall;
	assign FlushE	= lw_stall;

endmodule