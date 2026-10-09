// =================================================================
// Module MDU (Multiplier-Divider Unit)
// + Hỗ trợ RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
// + MUL: combinational (1 cycle) - 1 signed 33x33 multiplier
// + DIV: sequential restoring division (33 cycles)
// + Optimized cho Cyclone IV DSP blocks
// =================================================================

module MDU (

	input clk,
	input reset,

	input [31:0] SrcA,
	input [31:0] SrcB,

	input [2:0]  funct3,
	input        MDU_En,

	output [31:0] Result,
	output        Busy
);

	// =================================================
	// STATE MACHINE
	// =================================================
	localparam S_IDLE = 2'b00;
	localparam S_BUSY = 2'b01;
	localparam S_DONE = 2'b10;

	reg [1:0] state;

	// =================================================
	// GROUP DETECT
	// =================================================
	wire is_mul = (funct3[2] == 1'b0);		// 0xx: MUL group
	wire is_div = (funct3[2] == 1'b1);		// 1xx: DIV group


	// =================================================
	// MUL DATAPATH (COMBINATIONAL)
	// + Dùng 1 multiplier signed 33x33 cho cả 4 phép
	// + Quartus map sang DSP blocks Cyclone IV
	// =================================================
	reg signed [32:0] mul_a_ext;
	reg signed [32:0] mul_b_ext;

	always @(*) begin
		case (funct3[1:0])

			2'b01: begin				// MULH   (signed × signed)
				mul_a_ext = {SrcA[31], SrcA};
				mul_b_ext = {SrcB[31], SrcB};
			end

			2'b10: begin				// MULHSU (signed × unsigned)
				mul_a_ext = {SrcA[31], SrcA};
				mul_b_ext = {1'b0, SrcB};
			end

			default: begin				// MUL (00), MULHU (11) - cả 2 dùng unsigned
				mul_a_ext = {1'b0, SrcA};
				mul_b_ext = {1'b0, SrcB};
			end

		endcase
	end

	// 1 multiplier signed 33x33 -> DSP block
	wire signed [65:0] mul_full = mul_a_ext * mul_b_ext;

	reg [31:0] mul_result;
	always @(*) begin
		case (funct3[1:0])
			2'b00:   mul_result = mul_full[31:0];		// MUL    (lower 32)
			default: mul_result = mul_full[63:32];		// MULH / MULHSU / MULHU (upper 32)
		endcase
	end


	// =================================================
	// DIV PRE-PROCESSING (Signed -> Absolute)
	// =================================================
	wire is_signed_div = (funct3 == 3'b100) || (funct3 == 3'b110);	// DIV, REM
	wire src_a_neg     = is_signed_div && SrcA[31];
	wire src_b_neg     = is_signed_div && SrcB[31];

	wire [31:0] abs_a  = src_a_neg ? (~SrcA + 1'b1) : SrcA;
	wire [31:0] abs_b  = src_b_neg ? (~SrcB + 1'b1) : SrcB;

	wire div_by_zero   = (SrcB == 32'b0);
	wire overflow      = is_signed_div &&
						 (SrcA == 32'h8000_0000) &&
						 (SrcB == 32'hFFFF_FFFF);


	// =================================================
	// DIV LATCHED OPERANDS
	// =================================================
	reg [31:0] dividend_orig;
	reg [31:0] divisor_abs;
	reg        sign_q;
	reg        sign_r;
	reg [2:0]  funct3_reg;
	reg        div_by_zero_reg;
	reg        overflow_reg;


	// =================================================
	// DIV ITERATION REGISTERS
	// =================================================
	reg [63:0] shift_reg;		// {remainder[31:0], quotient[31:0]}
	reg [5:0]  counter;

	// Restoring step (combinational)
	// + remainder sau shift left 1 = shift_reg[62:31]
	wire [31:0] r_next_pre = shift_reg[62:31];
	wire        sub_ok     = (r_next_pre >= divisor_abs);
	wire [31:0] r_next     = sub_ok ? (r_next_pre - divisor_abs) : r_next_pre;


	// =================================================
	// STATE MACHINE
	// =================================================
	always @(posedge clk or negedge reset) begin

		if (!reset) begin
			state			<= S_IDLE;
			counter			<= 6'b0;
			shift_reg		<= 64'b0;
			dividend_orig	<= 32'b0;
			divisor_abs		<= 32'b0;
			sign_q			<= 1'b0;
			sign_r			<= 1'b0;
			funct3_reg		<= 3'b0;
			div_by_zero_reg	<= 1'b0;
			overflow_reg	<= 1'b0;
		end

		else begin
			case (state)

				// ============== IDLE ==============
				S_IDLE: begin
					if (MDU_En && is_div) begin
						// Latch operands
						dividend_orig	<= SrcA;
						divisor_abs		<= abs_b;
						sign_q			<= src_a_neg ^ src_b_neg;
						sign_r			<= src_a_neg;
						funct3_reg		<= funct3;
						div_by_zero_reg	<= div_by_zero;
						overflow_reg	<= overflow;

						// Init shift_reg = {32'b0, dividend_abs}
						shift_reg		<= {32'b0, abs_a};
						counter			<= 6'd32;
						state			<= S_BUSY;
					end
				end


				// ============== BUSY ==============
				S_BUSY: begin
					// shift_reg_next = {r_next, shift_reg[30:0], sub_ok}
					shift_reg	<= {r_next, shift_reg[30:0], sub_ok};
					counter		<= counter - 1'b1;

					if (counter == 6'd1) begin
						state	<= S_DONE;
					end
				end


				// ============== DONE ==============
				S_DONE: begin
					state	<= S_IDLE;
				end


				default: state <= S_IDLE;

			endcase
		end
	end


	// =================================================
	// DIV RESULT (COMBINATIONAL)
	// + funct3_reg[1] = 0: DIV/DIVU -> quotient
	// + funct3_reg[1] = 1: REM/REMU -> remainder
	// =================================================
	wire [31:0] quotient_raw  = shift_reg[31:0];
	wire [31:0] remainder_raw = shift_reg[63:32];

	wire [31:0] quotient_final  = sign_q ? (~quotient_raw  + 1'b1) : quotient_raw;
	wire [31:0] remainder_final = sign_r ? (~remainder_raw + 1'b1) : remainder_raw;

	wire [31:0] div_pick = funct3_reg[1] ? remainder_final : quotient_final;

	reg [31:0] div_result;
	always @(*) begin

		// ============== Div by zero ==============
		if (div_by_zero_reg) begin
			// DIV/DIVU -> -1; REM/REMU -> dividend
			div_result = funct3_reg[1] ? dividend_orig : 32'hFFFF_FFFF;
		end

		// ============== Signed overflow ==============
		else if (overflow_reg) begin
			// DIV -> INT_MIN (0x80000000); REM -> 0
			div_result = funct3_reg[1] ? 32'b0 : 32'h8000_0000;
		end

		// ============== Normal ==============
		else begin
			div_result = div_pick;
		end

	end


	// =================================================
	// OUTPUT
	// =================================================
	assign Result = is_mul ? mul_result : div_result;

	// + Busy = 1 khi state=BUSY HOẶC state=IDLE và có lệnh DIV mới
	//   -> Stall ngay cycle DIV vào EX, tránh mất stall ở cycle đầu
	assign Busy   = (state == S_BUSY) ||
					(state == S_IDLE && MDU_En && is_div);

endmodule
