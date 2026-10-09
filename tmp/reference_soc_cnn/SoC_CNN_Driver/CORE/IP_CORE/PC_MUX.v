// ======================================================
// Module PC_MUX (Fetch)
// + Chọn địa chỉ tiếp theo cho PC (Program Counter)
// ======================================================

module PC_MUX (

	input [31:0] din_0,
	input [31:0] din_1,
	
	input sel,
	
	output [31:0] mux_out
);

	assign mux_out = (~sel) ? din_0 : din_1;
	
endmodule