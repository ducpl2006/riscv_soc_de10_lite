// =======================================
// Module PC_Adder
// + PC Plus 4
// =======================================

module PC_Adder (

	input [31:0] pc_current,
	input [31:0] plus_value,
	
	output [31:0] PCPlus
);

	assign PCPlus = pc_current + plus_value;
endmodule