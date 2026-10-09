// =======================================
// Module Instr_Memory
// + Bộ nhớ lưu firmware
// =======================================

module Instr_Memory (
	
	input clk,
	
	// CPU interface
	input [31:0] addr,					// Địa chỉ CPU muốn đọc instruction trong Memory
	output [31:0] instruction,
	
	// Bootloader interface
	input boot_mode,
	input we_boot,
	input [31:0] addr_boot,
	input [31:0] data_boot
);

	(* ramstyle = "M9K" *)
	reg [31:0] mem [0:1023];			// 4KB
	
	// Load firmware mặc định
	initial begin
		$readmemh ("firmware.hex", mem);
	end
	
	// READ (CPU hoặc boot (Boot đọc lại firmware để kiểm tra)
	wire [31:0] addr_sel;
	
	assign addr_sel = boot_mode ? addr_boot : addr;
	
	// WRITE Bootloader
	always @(posedge clk) begin
		
		if (boot_mode && we_boot) begin
			mem[addr_boot[11:2]]	<= data_boot;
		end
		
		//instruction <= mem[addr_sel[11:2]];
		
	end

	assign instruction = mem[addr_sel[11:2]];
	
endmodule