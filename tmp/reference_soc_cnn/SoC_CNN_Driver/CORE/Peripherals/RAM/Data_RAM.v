// ============================================================
// Module Data_RAM
// ============================================================

module Data_RAM (

	input clk,
	input [31:0] addr,
	input [31:0] write_data,

	input read_en,
	input write_en,
	
	output reg [31:0] read_data
);

	// =============== RAM ===============
	(* ramstyle = "M9K" *) reg [31:0] mem [0:1023];	
	
	integer i;
	
	initial begin
		for (i = 0; i < 1024; i = i + 1) begin
			mem[i] = 32'b0;
		end
	end
	
	always @(posedge clk) begin
	
		if (write_en) begin
			mem[addr[11:2]]	<= write_data;
		end
		
		 if (read_en) begin
		 	read_data	<= mem[addr[11:2]];
		 end

	end

	
endmodule