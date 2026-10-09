`timescale 1ns/1ps

module tb_Writeback_Cycle;

    // =========================
    // Inputs
    // =========================
    reg RegWriteW;
    reg [1:0] ResultSrcW;
    reg [4:0] RD_W;
    reg [31:0] PCPlus4W;
    reg [31:0] ALU_ResultW;
    reg [31:0] ReadDataW;

    // =========================
    // Outputs
    // =========================
    wire RegWriteW_out;
    wire [4:0] RD_out;
    wire [31:0] ResultW;

    // =========================
    // DUT
    // =========================
    Writeback_Cycle dut (
        .RegWriteW(RegWriteW),
        .ResultSrcW(ResultSrcW),
        .RD_W(RD_W),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW),

        .RegWriteW_out(RegWriteW_out),
        .RD_out(RD_out),
        .ResultW(ResultW)
    );

    // =========================
    // Task check
    // =========================
    task check;
        input [31:0] expected;
        begin
            #1; // chờ combinational settle
            if (ResultW === expected)
                $display("PASS: ResultW = %0d", ResultW);
            else
                $display("FAIL: ResultW = %0d (expected %0d)", ResultW, expected);
        end
    endtask

    // =========================
    // Test sequence
    // =========================
    initial begin

        // Init
        RegWriteW   = 0;
        ResultSrcW  = 0;
        RD_W        = 0;
        PCPlus4W    = 0;
        ALU_ResultW = 0;
        ReadDataW   = 0;

        // =====================
        // TEST 1: ALU RESULT
        // =====================
        $display("\n===== TEST 1: ALU =====");

        ALU_ResultW = 32'd50;
        ResultSrcW  = 2'b00;

        check(50);

        // =====================
        // TEST 2: LOAD
        // =====================
        $display("\n===== TEST 2: LOAD =====");

        ReadDataW  = 32'd123;
        ResultSrcW = 2'b01;

        check(123);

        // =====================
        // TEST 3: JAL (PC+4)
        // =====================
        $display("\n===== TEST 3: PC+4 =====");

        PCPlus4W   = 32'd200;
        ResultSrcW = 2'b10;

        check(200);

        // =====================
        // TEST 4: CONTROL PASS
        // =====================
        $display("\n===== TEST 4: CONTROL =====");

        RegWriteW = 1;
        RD_W = 5'd7;

        #1;
        if (RegWriteW_out == 1 && RD_out == 7)
            $display("PASS: Control OK");
        else
            $display("FAIL: Control ERROR");

        // =====================
        // FINISH
        // =====================
        #10;
        $display("\n✅ TEST DONE");
        $stop;

    end

endmodule