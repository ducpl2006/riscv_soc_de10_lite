// ==========================================
// Module Register_File
// + Các thanh ghi lưu dữ liệu của CPU
// ==========================================

module Register_File (

	input clk,
	input reset,
	
	input we,
	
	input [4:0] rs1_addr,
	input [4:0] rs2_addr,
	input [4:0] rd_addr,
	
	input [31:0] write_data,
	
	output [31:0] rs1_data,
	output [31:0] rs2_data
);
	
	reg [31:0] Register [0:31];
	
	
	// ==================================================
	// + Reset toàn bộ Register
	// + Ghi data vào thanh ghi đích (Từ Write Back)
	// ==================================================
	integer i;
	always @(posedge clk or negedge reset) begin
	
		if (!reset) begin
			for (i = 0; i < 32; i = i + 1) begin
				Register[i]	<= 0;
			end
		end
		
		else if (we && rd_addr != 0) begin
			Register[rd_addr]	<= write_data;
		end
	
	end

	
	// ==================================================
	// Đọc dữ liệu từ các thanh ghi nguồn
	// ==================================================
	assign rs1_data = (rs1_addr == 0) ? 32'h0 : 
							(we && rd_addr == rs1_addr) ? write_data : Register[rs1_addr];
							
	assign rs2_data = (rs2_addr == 0) ? 32'h0 : 
							(we && rd_addr == rs2_addr) ? write_data : Register[rs2_addr];

endmodule