//`include "Hazard_Unit.v"

`timescale 1ns/1ps

module tb_Hazard_Unit;

    // =========================
    // INPUTS
    // =========================
    reg RegWriteM;
    reg RegWriteW;
    reg [4:0] RD_M;
    reg [4:0] RD_W;
    reg [4:0] RS1_E;
    reg [4:0] RS2_E;

    reg MemReadE;
    reg [4:0] RD_E;
    reg [4:0] RS1_D;
    reg [4:0] RS2_D;

    reg PCSrcE;

    // =========================
    // OUTPUTS
    // =========================
    wire [1:0] ForwardA_E;
    wire [1:0] ForwardB_E;
    wire StallF;
    wire StallD;
    wire FlushD;
    wire FlushE;

    // =========================
    // DUT
    // =========================
    Hazard_Unit dut (
        .RegWriteM(RegWriteM),
        .RegWriteW(RegWriteW),
        .RD_M(RD_M),
        .RD_W(RD_W),
        .RS1_E(RS1_E),
        .RS2_E(RS2_E),

        .MemReadE(MemReadE),
        .RD_E(RD_E),
        .RS1_D(RS1_D),
        .RS2_D(RS2_D),

        .PCSrcE(PCSrcE),

        .ForwardA_E(ForwardA_E),
        .ForwardB_E(ForwardB_E),
        .StallF(StallF),
        .StallD(StallD),
        .FlushD(FlushD),
        .FlushE(FlushE)
    );

    // =========================
    // RESET TASK
    // =========================
    task reset_all;
        begin
            RegWriteM = 0;
            RegWriteW = 0;
            RD_M = 0;
            RD_W = 0;
            RS1_E = 0;
            RS2_E = 0;

            MemReadE = 0;
            RD_E = 0;
            RS1_D = 0;
            RS2_D = 0;

            PCSrcE = 0;
            #1;
        end
    endtask

    // =========================
    // CHECK TASK
    // =========================
    task check;
        input [1:0] expA;
        input [1:0] expB;
        input expStallF;
        input expStallD;
        input expFlushD;
        input expFlushE;
        begin
            #1;
            if (ForwardA_E===expA && ForwardB_E===expB &&
                StallF===expStallF && StallD===expStallD &&
                FlushD===expFlushD && FlushE===expFlushE)
                $display("PASS");
            else begin
                $display("FAIL:");
                $display(" A=%b B=%b | StallF=%b StallD=%b | FlushD=%b FlushE=%b",
                         ForwardA_E, ForwardB_E, StallF, StallD, FlushD, FlushE);
                $display(" Expected:");
                $display(" A=%b B=%b | StallF=%b StallD=%b | FlushD=%b FlushE=%b",
                         expA, expB, expStallF, expStallD, expFlushD, expFlushE);
            end
        end
    endtask

    // =========================
    // TEST SEQUENCE
    // =========================
    initial begin

        $display("\n===== HAZARD UNIT TEST START =====");

        // =====================================
        // TEST 1: NO HAZARD
        // =====================================
        reset_all();
        $display("\nTEST 1: NO HAZARD");

        check(2'b00, 2'b00, 0, 0, 0, 0);

        // =====================================
        // TEST 2: FORWARD FROM MEM
        // =====================================
        reset_all();
        $display("\nTEST 2: FORWARD MEM");

        RegWriteM = 1;
        RD_M  = 5'd1;
        RS1_E = 5'd1;
        RS2_E = 5'd1;

        check(2'b10, 2'b10, 0, 0, 0, 0);

        // =====================================
        // TEST 3: FORWARD FROM WB
        // =====================================
        reset_all();
        $display("\nTEST 3: FORWARD WB");

        RegWriteW = 1;
        RD_W  = 5'd2;
        RS1_E = 5'd2;
        RS2_E = 5'd2;

        check(2'b01, 2'b01, 0, 0, 0, 0);

        // =====================================
        // TEST 4: PRIORITY MEM > WB
        // =====================================
        reset_all();
        $display("\nTEST 4: PRIORITY MEM");

        RegWriteM = 1;
        RegWriteW = 1;
        RD_M = 5'd3;
        RD_W = 5'd3;
        RS1_E = 5'd3;
        RS2_E = 5'd3;

        check(2'b10, 2'b10, 0, 0, 0, 0);

        // =====================================
        // TEST 5: LOAD-USE STALL
        // =====================================
        reset_all();
        $display("\nTEST 5: LOAD-USE STALL");

        MemReadE = 1;
        RD_E  = 5'd4;
        RS1_D = 5'd4;

        check(2'b00, 2'b00, 1, 1, 0, 1);

        // =====================================
        // TEST 6: BRANCH FLUSH
        // =====================================
        reset_all();
        $display("\nTEST 6: BRANCH");

        PCSrcE = 1;

        check(2'b00, 2'b00, 0, 0, 1, 1);

        // =====================================
        // TEST 7: LOAD + BRANCH (COMBINED)
        // =====================================
        reset_all();
        $display("\nTEST 7: LOAD + BRANCH");

        MemReadE = 1;
        RD_E = 5'd5;
        RS1_D = 5'd5;
        PCSrcE = 1;

        check(2'b00, 2'b00, 1, 1, 1, 1);

        // =====================================
        // TEST 8: MIXED FORWARD + STALL
        // =====================================
        reset_all();
        $display("\nTEST 8: MIXED");

        RegWriteM = 1;
        RD_M = 5'd6;
        RS1_E = 5'd6;

        MemReadE = 1;
        RD_E = 5'd7;
        RS2_D = 5'd7;

        check(2'b10, 2'b00, 1, 1, 0, 1);

        // =====================================
        // DONE
        // =====================================
        #10;
        $display("\n✅ ALL TEST DONE");
        $stop;

    end

endmodule