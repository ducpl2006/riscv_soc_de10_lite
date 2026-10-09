module top_test (

    input CLOCK_50,
    input [9:0] SW,
    output [7:0] LED

);

    wire [31:0] instruction;

    Instr_Memory mem (

        .clk(CLOCK_50),

        .addr({20'b0, SW, 2'b00}),
        .instruction(instruction),

        .boot_mode(1'b0),
        .we_boot(1'b0),
        .addr_boot(32'b0),
        .data_boot(32'b0)
    );

//    assign LED = instruction[7:0];
		assign LED = instruction[7:0] ^ instruction[15:8] ^ instruction[23:16] ^ instruction[31:24];

endmodule