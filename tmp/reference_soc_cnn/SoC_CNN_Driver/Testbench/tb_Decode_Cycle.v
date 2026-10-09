`timescale 1ns/1ps

module tb_Decode_Cycle;

    // ================= CLOCK =================
    reg clk;
    initial clk = 0;
    always #5 clk = ~clk;

    // ================= INPUT =================
    reg reset;

    // WB
    reg RegWriteW;
    reg [4:0] RDW;
    reg [31:0] ResultW;

    // IF
    reg [31:0] InstrD;
    reg [31:0] PCD;
    reg [31:0] PCPlus4D;

    // ================= OUTPUT =================
    wire RegWriteE;
    wire MemReadE;
    wire MemWriteE;
    wire [1:0] ResultSrcE;
    wire AluSrcAE;
    wire AluSrcBE;
    wire BranchE;
    wire JumpE;
    wire BrUnE;
    wire [3:0] ALUControlE;

    wire [31:0] RD1_E;
    wire [31:0] RD2_E;
    wire [31:0] Imm_Ext_E;

    wire [4:0] RS1_E;
    wire [4:0] RS2_E;
    wire [4:0] RD_E;

    // ================= DUT =================
    Decode_Cycle dut (
        .clk(clk),
        .reset(reset),

        .RegWriteW(RegWriteW),
        .RDW(RDW),
        .ResultW(ResultW),

        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),

        .RegWriteE(RegWriteE),
        .MemReadE(MemReadE),
        .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE),
        .AluSrcAE(AluSrcAE),
        .AluSrcBE(AluSrcBE),
        .BranchE(BranchE),
        .JumpE(JumpE),
        .BrUnE(BrUnE),
        .ALUControlE(ALUControlE),

        .RD1_E(RD1_E),
        .RD2_E(RD2_E),
        .Imm_Ext_E(Imm_Ext_E),

        .RS1_E(RS1_E),
        .RS2_E(RS2_E),
        .RD_E(RD_E),

        .PCE(),
        .PCPlus4E()
    );

    // ================= TASK =================
    task check;
        input [31:0] expected_imm;
        input exp_branch;
        input exp_jump;
        begin
            #1;
            if (Imm_Ext_E !== expected_imm)
                $display("❌ IMM ERROR | got=%h expected=%h", Imm_Ext_E, expected_imm);
            else
                $display("✅ IMM OK   | %h", Imm_Ext_E);

            if (BranchE !== exp_branch)
                $display("❌ BRANCH ERROR");
            if (JumpE !== exp_jump)
                $display("❌ JUMP ERROR");

            $display("------------------------------------------");
        end
    endtask

    // ================= INIT =================
    initial begin

        // Reset
        reset = 0;
        RegWriteW = 0;
        RDW = 0;
        ResultW = 0;
        InstrD = 0;
        PCD = 32'h1000;
        PCPlus4D = 32'h1004;

        #12 reset = 1;

        // =========================================
        // WRITE BACK TEST
        // =========================================
        RegWriteW = 1;
        RDW = 5'd1;
        ResultW = 32'hAAAA_BBBB;
        #10;
        RegWriteW = 0;

        // =========================================
        // R-TYPE (ADD)
        // =========================================
        InstrD = 32'b0000000_00010_00001_000_00011_0110011;
        #10;
        $display("R-TYPE ADD");
        check(32'd2, 0, 0);

        // =========================================
        // I-TYPE (ADDI x4 = x1 + 5)
        // =========================================
        InstrD = 32'b000000000101_00001_000_00100_0010011;
        #10;
        $display("I-TYPE ADDI");
        check(32'd5, 0, 0);

        // =========================================
        // LOAD (LW offset = 4)
        // =========================================
        InstrD = 32'b000000000100_00001_010_00101_0000011;
        #10;
        $display("LOAD LW");
        check(32'd4, 0, 0);

        // =========================================
        // STORE (SW offset = 8)
        // =========================================
        InstrD = 32'b0000000_00101_00001_010_01000_0100011;
        #10;
        $display("STORE SW");
        check(32'd8, 0, 0);

        // =========================================
        // BRANCH (BEQ offset = 16)
        // =========================================
        InstrD = 32'b0000000_00010_00001_000_10000_1100011;
        #10;
        $display("BRANCH BEQ");
        check(32'd16, 1, 0);

        // =========================================
        // JAL (offset = 8)
        // =========================================
        InstrD = 32'b00000000010000000000_00001_1101111;
        #10;
        $display("JAL");
        check(32'd4, 0, 1);

        // =========================================
        // LUI
        // =========================================
        InstrD = 32'b00000000000000000001_00001_0110111;
        #10;
        $display("LUI");
        check(32'h00001000, 0, 0);

        $display("========= TEST DONE =========");
        $stop;
    end

endmodule