`timescale 1ns/1ps

module tb_Execute_Cycle;

    // =========================
    // CLOCK
    // =========================
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================
    // RESET
    // =========================
    reg reset;

    task reset_dut;
    begin
        reset = 0;
        repeat(2) @(posedge clk);
        reset = 1;
        repeat(2) @(posedge clk);
    end
    endtask

    // =========================
    // INPUTS
    // =========================
    reg [31:0] RD1_E, RD2_E;
    reg [31:0] Imm_Ext_E;
    reg [4:0] RD_E;
    reg [31:0] PCE, PCPlus4E;

    reg RegWriteE, MemReadE, MemWriteE;
    reg AluSrcAE, AluSrcBE;
    reg [1:0] ResultSrcE;
    reg BranchE, JumpE, BrUnE;
    reg [3:0] ALUControlE;
    reg [2:0] funct3E;

    reg [31:0] ResultW;
    reg [1:0] ForwardA_E, ForwardB_E;
    reg [31:0] ALU_ResultM;

    reg FlushE;

    // =========================
    // OUTPUTS
    // =========================
    wire [31:0] ALU_ResultM_out;
    wire PCSrcE;
    wire [31:0] PCTargetE;
    wire RegWriteM;

    // =========================
    // DUT
    // =========================
    Execute_Cycle dut (
        .clk(clk),
        .reset(reset),

        .RD1_E(RD1_E),
        .RD2_E(RD2_E),
        .Imm_Ext_E(Imm_Ext_E),
        .RD_E(RD_E),

        .PCE(PCE),
        .PCPlus4E(PCPlus4E),

        .RegWriteE(RegWriteE),
        .MemReadE(MemReadE),
        .MemWriteE(MemWriteE),
        .AluSrcAE(AluSrcAE),
        .AluSrcBE(AluSrcBE),
        .ResultSrcE(ResultSrcE),
        .BranchE(BranchE),
        .JumpE(JumpE),
        .BrUnE(BrUnE),
        .ALUControlE(ALUControlE),
        .funct3E(funct3E),

        .ResultW(ResultW),
        .ForwardA_E(ForwardA_E),
        .ForwardB_E(ForwardB_E),
        .ALU_ResultM(ALU_ResultM),

        .FlushE(FlushE),

        .ALU_ResultM_out(ALU_ResultM_out),
        .PCSrcE(PCSrcE),
        .PCTargetE(PCTargetE),
        .RegWriteM(RegWriteM)
    );

    // =========================
    // INIT (QUAN TRỌNG)
    // =========================
    task init_signals;
    begin
        RD1_E = 0; RD2_E = 0; Imm_Ext_E = 0;
        PCE = 0; PCPlus4E = 4;

        RegWriteE = 0; MemReadE = 0; MemWriteE = 0;
        AluSrcAE = 0; AluSrcBE = 0;
        ResultSrcE = 0;

        BranchE = 0; JumpE = 0; BrUnE = 0;
        ALUControlE = 4'b0000;
        funct3E = 0;

        ResultW = 0;
        ForwardA_E = 0;
        ForwardB_E = 0;
        ALU_ResultM = 0;

        FlushE = 0;
    end
    endtask

    // =========================
    // CHECK TASK
    // =========================
    task check;
        input [31:0] actual;
        input [31:0] expected;
        input [100:0] name;
    begin
        if (actual === expected)
            $display("✅ PASS: %s = %d", name, actual);
        else begin
            $display("❌ FAIL: %s = %d (expected %d)", name, actual, expected);
            $display("   Debug: SrcA=%d SrcB=%d", dut.SrcA, dut.SrcB);
        end
    end
    endtask

    // =========================
    // TEST SEQUENCE
    // =========================
    initial begin

        // RESET
        init_signals();
        reset_dut();

        // =====================
        // TEST 1: ALU ADD
        // =====================
        $display("\nTEST 1: ALU ADD");
        init_signals();

        RD1_E = 10;
        RD2_E = 5;
        ALUControlE = 4'b0000; // ADD

        @(posedge clk);
        @(posedge clk);
        check(ALU_ResultM_out, 15, "ALU ADD");

        // =====================
        // TEST 2: FORWARD MEM
        // =====================
        $display("\nTEST 2: Forward MEM");
        init_signals();

        ForwardA_E = 2'b10;
        ALU_ResultM = 20;
        RD2_E = 5;
        ALUControlE = 4'b0000;

        @(posedge clk);
        @(posedge clk);
        check(ALU_ResultM_out, 25, "Forwarding");

        // =====================
        // TEST 3: BEQ
        // =====================
        $display("\nTEST 3: BEQ");
        init_signals();

        RD1_E = 15;
        RD2_E = 15;
        BranchE = 1;
        funct3E = 3'b000;

        @(posedge clk);
        check(PCSrcE, 1, "BEQ");

        // =====================
        // TEST 4: JAL
        // =====================
        $display("\nTEST 4: JAL");
        init_signals();

        JumpE = 1;
        AluSrcAE = 1;
        PCE = 100;
        Imm_Ext_E = 16;

        @(posedge clk);
        check(PCTargetE, 116, "JAL");

        // =====================
        // TEST 5: JALR
        // =====================
        $display("\nTEST 5: JALR");
        init_signals();

        JumpE = 1;
        RD1_E = 200;
        Imm_Ext_E = 4;

        @(posedge clk);
        check(PCTargetE, 204, "JALR");

        // =====================
        // TEST 6: FLUSH
        // =====================
        $display("\nTEST 6: FLUSH");
        init_signals();

        RegWriteE = 1;
        FlushE = 1;

        @(posedge clk);
        @(posedge clk);
        check(RegWriteM, 0, "Flush");

        $display("\n🎯 ALL TEST DONE");
        $stop;
    end

endmodule