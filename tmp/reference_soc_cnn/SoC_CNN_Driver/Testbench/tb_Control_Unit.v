`timescale 1ns/1ps

module tb_Control_Unit;

    // ================= INPUT =================
    reg [31:0] InstrD;

    // ================= OUTPUT =================
    wire RegWrite;
    wire MemRead;
    wire MemWrite;
    wire [1:0] ResultSrc;
    wire AluSrcA;
    wire AluSrcB;
    wire [2:0] ImmSel;
    wire Branch;
    wire Jump;
    wire BrUn;
    wire [3:0] ALUControl;

    // ================= DUT =================
    Control_Unit dut (
        .InstrD(InstrD),

        .RegWrite(RegWrite),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .AluSrcA(AluSrcA),
        .AluSrcB(AluSrcB),
        .ImmSel(ImmSel),
        .Branch(Branch),
        .Jump(Jump),
        .BrUn(BrUn),
        .ALUControl(ALUControl)
    );

    // ================= TASK PRINT =================
    task print_signal;
        begin
            $display("--------------------------------------------------");
            $display("Instr = %h", InstrD);
            $display("RegWrite=%b MemRead=%b MemWrite=%b", RegWrite, MemRead, MemWrite);
            $display("ResultSrc=%b ALUSrcA=%b ALUSrcB=%b", ResultSrc, AluSrcA, AluSrcB);
            $display("ImmSel=%b Branch=%b Jump=%b BrUn=%b", ImmSel, Branch, Jump, BrUn);
            $display("ALUControl=%b", ALUControl);
        end
    endtask

    // ================= TEST =================
    initial begin

        $display("========= START TEST CONTROL UNIT =========");

        // ================= R-TYPE: ADD =================
        // add x1, x2, x3
        InstrD = 32'b0000000_00011_00010_000_00001_0110011;
        #10 print_signal();

        // ================= R-TYPE: SUB =================
        InstrD = 32'b0100000_00011_00010_000_00001_0110011;
        #10 print_signal();

        // ================= I-TYPE: ADDI =================
        InstrD = 32'b000000000101_00010_000_00001_0010011;
        #10 print_signal();

        // ================= LOAD: LW =================
        InstrD = 32'b000000000100_00010_010_00001_0000011;
        #10 print_signal();

        // ================= STORE: SW =================
        InstrD = 32'b0000000_00001_00010_010_00000_0100011;
        #10 print_signal();

        // ================= BRANCH: BEQ =================
        InstrD = 32'b0000000_00011_00010_000_00000_1100011;
        #10 print_signal();

        // ================= BRANCH: BLTU =================
        InstrD = 32'b0000000_00011_00010_110_00000_1100011;
        #10 print_signal();

        // ================= JAL =================
        InstrD = 32'b00000000000100000000_00001_1101111;
        #10 print_signal();

        // ================= JALR =================
        InstrD = 32'b000000000100_00010_000_00001_1100111;
        #10 print_signal();

        // ================= LUI =================
        InstrD = 32'b00000000000000000001_00001_0110111;
        #10 print_signal();

        // ================= AUIPC =================
        InstrD = 32'b00000000000000000001_00001_0010111;
        #10 print_signal();

        $display("========= END TEST =========");
        $stop;
    end

endmodule