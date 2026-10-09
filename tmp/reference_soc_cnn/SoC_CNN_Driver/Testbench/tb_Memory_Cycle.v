`timescale 1ns/1ps

module tb_Memory_Cycle;

    // =========================
    // Signals
    // =========================
    reg clk;
    reg reset;

    // Input từ EX
    reg RegWriteM;
    reg MemReadM;
    reg MemWriteM;
    reg [1:0] ResultSrcM;
    reg [4:0] RD_M;
    reg [31:0] PCPlus4M;
    reg [31:0] WriteDataM;
    reg [31:0] ALU_ResultM;

    // Output sang WB
    wire RegWriteW;
    wire [1:0] ResultSrcW;
    wire [4:0] RD_W;
    wire [31:0] PCPlus4W;
    wire [31:0] ALU_ResultW;
    wire [31:0] ReadDataW;

    // =========================
    // DUT
    // =========================
    Memory_Cycle dut (
        .clk(clk),
        .reset(reset),

        .RegWriteM(RegWriteM),
        .MemReadM(MemReadM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),

        .RD_M(RD_M),
        .PCPlus4M(PCPlus4M),
        .WriteDataM(WriteDataM),
        .ALU_ResultM(ALU_ResultM),

        .RegWriteW(RegWriteW),
        .ResultSrcW(ResultSrcW),
        .RD_W(RD_W),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW)
    );

    // =========================
    // Clock (20ns)
    // =========================
    initial clk = 0;
    always #10 clk = ~clk;

    // =========================
    // RESET TASK
    // =========================
task reset_dut;
begin
    reset = 0;
    repeat(2) @(posedge clk);

    reset = 1;
    repeat(2) @(posedge clk);
end
endtask
    // =========================
    // STORE TASK
    // =========================
    task store(input [31:0] addr, input [31:0] data);
begin
    // set trước clock
    MemWriteM   <= 1;
    MemReadM    <= 0;
    WriteDataM  <= data;
    ALU_ResultM <= addr;

    @(posedge clk);  // RAM ghi tại đây

    MemWriteM <= 0;

    $display("STORE: mem[%0d] = %0d", addr, data);
end
endtask

    // =========================
    // LOAD TASK
    // =========================
   task load(input [31:0] addr);
begin
    MemReadM    <= 1;
    MemWriteM   <= 0;
    ALU_ResultM <= addr;

    @(posedge clk);  // gửi request

    MemReadM <= 0;

    @(posedge clk);  // RAM trả data
    @(posedge clk);  // WB nhận

    $display("LOAD: mem[%0d] -> ReadDataW = %0d", addr, ReadDataW);
end
endtask

    // =========================
    // MAIN TEST
    // =========================
    initial begin

        // Init
        RegWriteM   = 0;
        MemReadM    = 0;
        MemWriteM   = 0;
        ResultSrcM  = 0;
        RD_M        = 0;
        PCPlus4M    = 0;
        WriteDataM  = 0;
        ALU_ResultM = 0;

        // RESET
        reset_dut();

        // =====================
        // TEST 1: STORE
        // =====================
        $display("\n===== TEST 1: STORE =====");
        store(32'd100, 32'd123);

        // =====================
        // TEST 2: LOAD
        // =====================
        $display("\n===== TEST 2: LOAD =====");
        load(32'd100);

        // =====================
        // TEST 3: WB CHECK
        // =====================
        $display("\n===== TEST 3: WB =====");

        @(posedge clk);
        RegWriteM  <= 1;
        ResultSrcM <= 2'b01;   // chọn Memory
        RD_M       <= 5'd3;

        @(posedge clk);

        $display("WB: RD_W = %0d | Data = %0d", RD_W, ReadDataW);

        // =====================
        // RESULT CHECK
        // =====================
        if (ReadDataW == 123)
            $display("\n✅ PASS: MEMORY WORKS CORRECT");
        else
            $display("\n❌ FAIL: WRONG DATA");

        #20;
        $stop;
    end

endmodule