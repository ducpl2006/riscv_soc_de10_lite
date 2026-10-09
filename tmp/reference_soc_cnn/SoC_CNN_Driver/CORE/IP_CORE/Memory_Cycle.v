// ======================================
// module Memory_Cycle
// + MEM stage
// + Hỗ trợ LB/LH/LBU/LHU/SB/SH (byte/half align + sign/zero extend)
// + Latch AXI completion để tránh re-trigger khi mdu_stall=1
// ======================================

module Memory_Cycle (

	input clk,
	input reset,

	// ---------------------------------
	// Từ Execute stage (EX --> MEM)
	// ---------------------------------
	input RegWriteM,
	input MemReadM,
	input MemWriteM,

	input [1:0] ResultSrcM,			// Tín hiệu điều khiển WB sẽ lấy giá trị từ đâu

	input [4:0] RD_M,				// Địa chỉ của thanh ghi đích
	input [31:0] PCPlus4M,
	input [31:0] WriteDataM,		// Dữ liệu cần ghi vào RAM
	input [31:0] ALU_ResultM,		// Kết quả tính ở ALU (EX stage)


	// ----------------------------------
	// BUS Interface
	// ----------------------------------
	input [31:0] read_dataM_in,
	input mem_ready,

	output [31:0] addrM,
	output [31:0] write_dataM,
	output mem_writeM,
	output mem_readM,

	// BRAM Stall
	input StallM,

	input [2:0] funct3M,

	// ----------------------------------
	// Output sang Write Back (WB stage)
	// ----------------------------------
	output RegWriteW_actual,
	output RegWriteW_fwd,
	output [1:0] ResultSrcW,
	output [4:0] RD_W,
	output [31:0] PCPlus4W,
	output [31:0] ALU_ResultW,
	output [31:0] ReadDataW,
	output [3:0]  write_strbM
);

	// =============== DATA RAM ===============
	// wire [31:0] ReadDataM;

	// Data_RAM dmem (

	// 	// Input
	// 	.clk			(clk),
	// 	.addr			(ALU_ResultM),
	// 	.write_data		(WriteDataM),
	// 	.write_en		(MemWriteM),
	// 	.read_en		(MemReadM),

	// 	.read_data		(ReadDataM)
	// );

	// =============== BUS SIGNAL ===============
	reg [31:0] store_data_aligned;
	reg [3:0]  store_strb;

	reg [31:0] load_data_extended;

	assign addrM		= ALU_ResultM;
	assign write_dataM	= store_data_aligned;
	assign write_strbM	= store_strb;

	wire [31:0] ReadDataM;
	assign ReadDataM = load_data_extended;

	// =============== AXI DONE LATCH (Fix BUG 2) ===============
	// + Vấn đề: mem_ready là pulse 1 cycle. Khi mdu_stall=1, StallM=1
	//   --> MEM/WB không capture được mem_ready pulse
	//   --> AXI POST_READ --> IDLE thấy mem_re=1 --> RE-TRIGGER transaction mới
	//   --> Side-effect peripheral (UART RX) bị pop nhiều lần
	//
	// + Fix:
	//   1. Latch mem_ready + readdata khi AXI hoàn thành trong lúc stall
	//   2. Gate mem_readM/mem_writeM bằng axi_done_latch
	//      --> AXI thấy mem_re=0 --> không re-trigger
	//   3. Khi stall drops, MEM/WB capture từ readdata_latched
	// =========================================================
	reg        axi_done_latch;
	reg [31:0] readdata_latched;

	always @(posedge clk or negedge reset) begin

		if (!reset) begin
			axi_done_latch   <= 1'b0;
			readdata_latched <= 32'b0;
		end

		// Latch khi AXI cấp data nhưng pipeline đang stall (mdu_stall)
		else if ((MemReadM || MemWriteM) && mem_ready && StallM && !axi_done_latch) begin
			axi_done_latch <= 1'b1;
			if (MemReadM)
				readdata_latched <= ReadDataM;	// Đã sign/zero extend
		end

		// Clear khi MEM/WB đã capture (pipeline advance khỏi MEM stage)
		else if (!StallM && axi_done_latch) begin
			axi_done_latch <= 1'b0;
		end

	end

	// Gate AXI request: prevent re-trigger sau khi đã latched
	assign mem_readM	= MemReadM  && !axi_done_latch;
	assign mem_writeM	= MemWriteM && !axi_done_latch;

	// Effective ReadData: dùng latched nếu có
	wire [31:0] readdata_eff = axi_done_latch ? readdata_latched : ReadDataM;

	// =============== PIPELINE REGISTER ===============
	reg RegWriteM_r;
	reg [1:0] ResultSrcM_r;
	reg [4:0] RD_M_r;
	reg [31:0] PCPlus4M_r;
	reg [31:0] ALU_ResultM_r;
	reg [31:0] ReadDataM_r;

	wire mem_access;

	assign mem_access = MemReadM || MemWriteM;

	always @(posedge clk or negedge reset) begin

		if (!reset) begin
			RegWriteM_r		<= 0;
			ResultSrcM_r	<= 2'b0;
			RD_M_r			<= 5'b0;
			PCPlus4M_r		<= 32'h0000_0000;
			ALU_ResultM_r	<= 32'h0000_0000;
			ReadDataM_r		<= 32'h0000_0000;
		end

		else if (StallM) begin
			// Hold MEM/WB - giữ để BRAM có thêm 1 cycle output valid data
		end

		else if (mem_access) begin
			// Capture khi AXI ready HOẶC đã latched (sau khi mdu_stall drops)
			if (mem_ready || axi_done_latch) begin
				RegWriteM_r			<= RegWriteM;
				ResultSrcM_r		<= ResultSrcM;
				RD_M_r				<= RD_M;
				PCPlus4M_r			<= PCPlus4M;
				ALU_ResultM_r		<= ALU_ResultM;

				ReadDataM_r			<= readdata_eff;
			end
		end

		else begin
			RegWriteM_r			<= RegWriteM;
			ResultSrcM_r		<= ResultSrcM;
			RD_M_r				<= RD_M;
			PCPlus4M_r			<= PCPlus4M;
			ALU_ResultM_r		<= ALU_ResultM;

			ReadDataM_r			<= ReadDataM;
		end

	end

	// =============== STORE SIDE (SB/SH/SW) ===============
	wire [1:0] byte_off = ALU_ResultM[1:0];

	always @(*) begin

		case (funct3M[1:0])

			// ============== SB ==============
			2'b00: begin
				case (byte_off)
					2'b00: begin
						store_data_aligned 	= {24'b0, WriteDataM[7:0]};
						store_strb			= 4'b0001;
					end

					2'b01: begin
						store_data_aligned	= {16'b0, WriteDataM[7:0], 8'b0};
						store_strb			= 4'b0010;
					end

					2'b10: begin
						store_data_aligned	= {8'b0, WriteDataM[7:0], 16'b0};
						store_strb			= 4'b0100;
					end

					2'b11: begin
						store_data_aligned	= {WriteDataM[7:0], 24'b0};
						store_strb			= 4'b1000;
					end
				endcase
			end

			// ============== SH ==============
			2'b01: begin
				if (byte_off[1] == 1'b0) begin
					store_data_aligned	= {16'b0, WriteDataM[15:0]};
					store_strb			= 4'b0011;
				end

				else begin
					store_data_aligned	= {WriteDataM[15:0], 16'b0};
					store_strb			= 4'b1100;
				end
			end

			// ============== SW (DEFAULT) ==============
			default: begin
				store_data_aligned	= WriteDataM;
				store_strb			= 4'b1111;
			end

		endcase

	end

	// =============== LOAD SIDE (LB/LH/LBU/LHU/LW) ===============
	// Byte selected theo addr[1:0]
	reg [7:0]  byte_sel;
	reg [15:0] half_sel;

	always @(*) begin

		case (ALU_ResultM[1:0])

			2'b00: byte_sel	= read_dataM_in[7:0];

			2'b01: byte_sel	= read_dataM_in[15:8];

			2'b10: byte_sel = read_dataM_in[23:16];

			2'b11: byte_sel = read_dataM_in[31:24];

		endcase

		case (ALU_ResultM[1])

			1'b0: half_sel = read_dataM_in[15:0];

			1'b1: half_sel = read_dataM_in[31:16];

		endcase

		case (funct3M)

			3'b000: load_data_extended = {{24{byte_sel[7]}}, byte_sel};		// LB (signed)

			3'b001: load_data_extended = {{16{half_sel[15]}}, half_sel};	// LH (signed)

			3'b010: load_data_extended = read_dataM_in;						// LW

			3'b100: load_data_extended = {24'b0, byte_sel};					// LBU (unsigned)

			3'b101: load_data_extended = {16'b0, half_sel};					// LHU (unsigned)

			default: load_data_extended = read_dataM_in;

		endcase

	end


	// =============== OUPUT sang WB ===============
	assign RegWriteW_actual	= StallM ? 1'b0 : RegWriteM_r;	// Register file
	assign RegWriteW_fwd 	= RegWriteM_r;					// Forwarding
	assign ResultSrcW		= ResultSrcM_r;
	assign RD_W				= RD_M_r;
	assign PCPlus4W			= PCPlus4M_r;
	assign ALU_ResultW		= ALU_ResultM_r;
	assign ReadDataW		= ReadDataM_r;

endmodule