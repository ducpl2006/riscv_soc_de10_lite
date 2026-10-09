// =============================
// Testbench ALU
// =============================

`timescale 1ns/1ps

module tb_ALU;

    reg [31:0] SrcA;
    reg [31:0] SrcB;
    reg [3:0] ALUControlE;

    wire [31:0] ResultE;
    wire Zero;

    // =============== ALU Encoding ===============
	localparam ALU_ADD	= 4'b0000;
	localparam ALU_SUB	= 4'b0001;
	localparam ALU_AND	= 4'b0010;
	localparam ALU_OR	= 4'b0011;
	localparam ALU_XOR	= 4'b0100;
	localparam ALU_SLL	= 4'b0101;
	localparam ALU_SRL	= 4'b0110;
	localparam ALU_SRA	= 4'b0111;
	localparam ALU_SLT	= 4'b1000;
	localparam ALU_SLTU	= 4'b1001;
	localparam ALU_PASS	= 4'b1010;

    ALU alu_uut (

        .SrcA           (SrcA),
        .SrcB           (SrcB),
        .ALUControlE    (ALUControlE),
        .ResultE        (ResultE),
        .Zero           (Zero)
    );

    // ==========================
    // TASKE: CHECK RESULT
    // ==========================
    task check;
        input [31:0] exp_result;
        input exp_zero;

        begin
            #1
            if (ResultE == exp_result & Zero == exp_zero) begin
                $display ("PASS | A = %0d | B = %0d CTRL = %b | Result = %0d | Zero = %b",
                                    SrcA, SrcB, ALUControlE, ResultE, Zero);
            end

            else begin
                $display ("FAIL | A = %0d | B = %0d CTRL = %b | Result = %0d (exp = %0d) | Zero = %b (exp = %b)",
                                    SrcA, SrcB, ALUControlE, ResultE, exp_result, Zero, exp_zero);
            end
        end
    endtask

    // ==================================
    // TEST CASE
    // ================================= 
    initial begin
        
        $display (" ======================================");
        $display ("                 ALU CHECK");
        $display ("=======================================");

        // Test case 1: ADD
        SrcA = 10;
        SrcB = 5;
        ALUControlE = ALU_ADD;
        #10
        check (15, 0);

        // Test case 2: SUB
        SrcA = 20;
        SrcB = 10;
        ALUControlE = ALU_SUB;
        #10
        check (10, 0);

        // Test case 3: AND
        SrcA = 12;
        SrcB = 10;
        ALUControlE = ALU_AND;
        #10 
        check (8, 0);

        // Test case 2: OR
        SrcA = 12;
        SrcB = 10;
        ALUControlE = ALU_OR;
        #10
        check (14, 0);

        // =====================
        // TEST 5: SLT
        // =====================
        SrcA = 5; SrcB = 10; ALUControlE = ALU_SLT; // SLT
        #10;
        check(1, 0);

        // =====================
        // TEST 6: ZERO FLAG
        // =====================
        SrcA = 10; SrcB = 10; ALUControlE = ALU_SUB; // SUB
        #10;
        check(0, 1);

        // =====================
        // TEST 7: NEGATIVE CASE
        // =====================
        SrcA = -5; SrcB = 3; ALUControlE = ALU_ADD; // ADD
        #10;
        check(-2, 0);

        // =====================
        // TEST 8: LARGE VALUE
        // =====================
        SrcA = 32'hFFFFFFFF; SrcB = 1; ALUControlE = 4'b0000;
        #10;
        check(0, 1);

        $display("=========================================");
        $display("           ALU TEST END");
        $display("=========================================");

        $finish;
    end
    
endmodule