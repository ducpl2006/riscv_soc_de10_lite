`timescale 1ns/1ps

module tb_Forwarding_Unit;

    // =========================
    // INPUTS
    // =========================
    reg RegWriteM;
    reg RegWriteW;

    reg [4:0] RD_M;
    reg [4:0] RD_W;

    reg [4:0] RS1_E;
    reg [4:0] RS2_E;

    // =========================
    // OUTPUTS
    // =========================
    wire [1:0] ForwardA_E;
    wire [1:0] ForwardB_E;

    // =========================
    // DUT
    // =========================
    Forwarding_Unit dut (
        .RegWriteM(RegWriteM),
        .RegWriteW(RegWriteW),
        .RD_M(RD_M),
        .RD_W(RD_W),
        .RS1_E(RS1_E),
        .RS2_E(RS2_E),
        .ForwardA_E(ForwardA_E),
        .ForwardB_E(ForwardB_E)
    );

    // =========================
    // TASK: RESET INPUTS
    // =========================
    task reset_inputs;
        begin
            RegWriteM = 0;
            RegWriteW = 0;
            RD_M = 0;
            RD_W = 0;
            RS1_E = 0;
            RS2_E = 0;
            #1;
        end
    endtask

    // =========================
    // TASK: CHECK RESULT
    // =========================
    task check;
        input [1:0] expA;
        input [1:0] expB;
        begin
            #1;
            if (ForwardA_E === expA && ForwardB_E === expB)
                $display("PASS: A=%b B=%b", ForwardA_E, ForwardB_E);
            else
                $display("FAIL: A=%b B=%b (expected A=%b B=%b)",
                         ForwardA_E, ForwardB_E, expA, expB);
        end
    endtask

    // =========================
    // TEST SEQUENCE
    // =========================
    initial begin

        $display("\n===== FORWARDING TEST START =====");

        // =====================
        // TEST 1: NO FORWARD
        // =====================
        reset_inputs();
        $display("\nTEST 1: NO FORWARD");

        RS1_E = 5'd1;
        RS2_E = 5'd2;

        check(2'b00, 2'b00);

        // =====================
        // TEST 2: FORWARD A FROM MEM
        // =====================
        reset_inputs();
        $display("\nTEST 2: FORWARD A FROM MEM");

        RegWriteM = 1;
        RD_M  = 5'd1;
        RS1_E = 5'd1;
        RS2_E = 5'd2;

        check(2'b10, 2'b00);

        // =====================
        // TEST 3: FORWARD B FROM MEM
        // =====================
        reset_inputs();
        $display("\nTEST 3: FORWARD B FROM MEM");

        RegWriteM = 1;
        RD_M  = 5'd3;
        RS1_E = 5'd1;
        RS2_E = 5'd3;

        check(2'b00, 2'b10);

        // =====================
        // TEST 4: FORWARD BOTH FROM MEM
        // =====================
        reset_inputs();
        $display("\nTEST 4: FORWARD BOTH FROM MEM");

        RegWriteM = 1;
        RD_M  = 5'd4;
        RS1_E = 5'd4;
        RS2_E = 5'd4;

        check(2'b10, 2'b10);

        // =====================
        // TEST 5: FORWARD FROM WB
        // =====================
        reset_inputs();
        $display("\nTEST 5: FORWARD FROM WB");

        RegWriteW = 1;
        RD_W  = 5'd5;
        RS1_E = 5'd5;
        RS2_E = 5'd5;

        check(2'b01, 2'b01);

        // =====================
        // TEST 6: PRIORITY MEM > WB
        // =====================
        reset_inputs();
        $display("\nTEST 6: PRIORITY MEM > WB");

        RegWriteM = 1;
        RegWriteW = 1;
        RD_M = 5'd6;
        RD_W = 5'd6;
        RS1_E = 5'd6;
        RS2_E = 5'd6;

        check(2'b10, 2'b10);

        // =====================
        // TEST 7: IGNORE x0
        // =====================
        reset_inputs();
        $display("\nTEST 7: IGNORE x0");

        RegWriteM = 1;
        RegWriteW = 1;
        RD_M = 5'd0;
        RD_W = 5'd0;
        RS1_E = 5'd0;
        RS2_E = 5'd0;

        check(2'b00, 2'b00);

        // =====================
        // TEST 8: MIXED CASE
        // =====================
        reset_inputs();
        $display("\nTEST 8: MIXED CASE");

        RegWriteM = 1;
        RegWriteW = 1;
        RD_M = 5'd8;   // match A
        RD_W = 5'd9;   // match B
        RS1_E = 5'd8;
        RS2_E = 5'd9;

        check(2'b10, 2'b01);

        // =====================
        // FINISH
        // =====================
        #10;
        $display("\n✅ FORWARDING TEST DONE");
        $stop;

    end

endmodule