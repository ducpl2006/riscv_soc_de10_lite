// ===============================================
// Module Branch_Unit
// + Đưa ra tín hiệu có NHẢY hay không
// ===============================================

module Branch_Unit(

	input [31:0] A,			// Toán hạng để so sánh (đã qua forward)
	input [31:0] B,			// Toán hạng để so sánh (đã qua forward)
	
	input [2:0] funct3,		// Xác định loại Branch
	
	input Branch,			// Tín hiệu xác định có phải lệnh Branch hay không
	input BrUn,				// Xác định loại so sánh (signed / unsigned)
	
	output reg PCSrc		// Tín hiệu quyết định PC lấy tín hiệu từ đâu (branch: PCSrc: pc next = pc target)
);

	wire eq;				// So sánh bắng nhau
	wire lt_signed;			// So sánh bé hơn có dấu
	wire lt_unsigned;		// So sánh bé hơn không dấu
	
	assign eq = (A == B);
	assign lt_signed = ($signed(A) < $signed(B));
	assign lt_unsigned = (A < B);
	
	wire lt;		// Chọn tín hiệu so sánh có dấu hay không dấu
	assign lt = (BrUn) ? lt_unsigned : lt_signed;
	
	
	// =============== KIỂU BRANCH ===============
	always @(*) begin
	
		case (funct3) 
		
			3'b000:	PCSrc	= Branch & eq;			// BEQ
			
			3'b001:	PCSrc = Branch & ~eq;			// BNE
			
			3'b100:	PCSrc = Branch & lt;			// BLT
			
			3'b101:	PCSrc = Branch & ~lt;			// BGE
			
			3'b110:	PCSrc = Branch & lt;			// BLTU
			
			3'b111:	PCSrc = Branch & ~lt;			// BGEU
			
			default: PCSrc = 1'b0;
		endcase
	
	end

endmodule