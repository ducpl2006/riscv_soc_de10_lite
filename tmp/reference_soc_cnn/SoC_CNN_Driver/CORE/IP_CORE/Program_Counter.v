// ==========================================
// Module Program_Counter
// PC counter
// ==========================================

module Program_Counter (

	input clk,
	input reset,
	
	input stall,				// Điều khiển PC
	
	input [31:0] PCNextF,		// Đưa Ouput của MUX vào PC Counter
	
	output reg [31:0] PCF		// Giá trị PC hiện tại
);
	
	always @(posedge clk) begin
		
		if (!reset) begin
			PCF	<= 32'h0000_0000;
		end
		
		else if (!stall) begin
			PCF	<= PCNextF;
		end

	end

endmodule