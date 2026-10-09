// ================================================
// Module giải mã, hiển thị màn hình LED 7 đoạn
// ================================================

module Seg7_Decoder (

    input [3:0] data,
    output reg [6:0] seg7_display
);

    always @(*) begin
        
        case (data)
		
			4'h0: seg7_display = 7'b1000000;
			
			4'h1: seg7_display = 7'b1111001;
			
			4'h2: seg7_display = 7'b0100100;
			
			4'h3: seg7_display = 7'b0110000;
			
			4'h4: seg7_display = 7'b0011001;
			
			4'h5: seg7_display = 7'b0010010;
			
			4'h6: seg7_display = 7'b0000010;
			
			4'h7: seg7_display = 7'b1111000;
			
			4'h8: seg7_display = 7'b0000000;
			
			4'h9: seg7_display = 7'b0010000;
			
			4'hA: seg7_display = 7'b0001000;
			
			4'hB: seg7_display = 7'b0000011;
			
			4'hC: seg7_display = 7'b1000110;
			
			4'hD: seg7_display = 7'b0100001;
			
			4'hE: seg7_display = 7'b0000110;
			
			4'hF: seg7_display = 7'b0001110;
			
			default: seg7_display = 7'b1111111;
			
		endcase

    end
endmodule