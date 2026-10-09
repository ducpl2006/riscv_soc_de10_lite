`timescale 1ns/1ps

// ============================================================
// Testbench: tb_CPU
// Firmware: firmware.hex (comprehensive CPU test)
//
// Architecture: CPU với external memory interface (SoC)
//   CPU ports: addrM, write_dataM, mem_writeM, mem_readM, read_dataM
//   Memory model: synchronous BRAM (khớp M9K latency + bram_stall)
//
// Expected final state:
//   x2 = 0x00000FE0  (SP = 0x1000 - 32)
//
//   tb_mem[64]  = 17          ADD   : 5 + 12
//   tb_mem[65]  = 7           SUB   : 12 - 5
//   tb_mem[66]  = 4           AND   : 5 & 12
//   tb_mem[67]  = 13          OR    : 5 | 12
//   tb_mem[68]  = 9           XOR   : 5 ^ 12
//   tb_mem[69]  = 20          SLL   : 5 << 2
//   tb_mem[70]  = 6           SRL   : 12 >> 1
//   tb_mem[71]  = 0xFFFFFFFC  SRA   : -8 >> 1
//   tb_mem[72]  = 1           SLT   : 5 < 12
//   tb_mem[73]  = 1           SLTU  : 5 < 12 unsigned
//   tb_mem[74]  = 0x12000000  LUI
//   tb_mem[75]  = 99          LW/SW + load-use hazard
//   tb_mem[76]  = 1           BEQ   taken
//   tb_mem[77]  = 1           BNE   taken
//   tb_mem[78]  = 1           BLT   taken
//   tb_mem[79]  = 1           BGE   taken
//   tb_mem[80]  = 1           BLTU  taken
//   tb_mem[81]  = 10          JAL + JALR : fn_add(3,7)
//   tb_mem[82]  = 39          Forwarding chain EX->EX
//   tb_mem[83]  = 5           Loop (backward branch x5)
// ============================================================

module tb_CPU;

    // ========================
    // SIGNALS
    // ========================
    reg  clk;
    reg  reset;

    // CPU Memory Interface
    wire [31:0] addrM;
    wire [31:0] write_dataM;
    wire        mem_writeM;
    wire        mem_readM;
    reg  [31:0] read_dataM;

    integer pass_count;
    integer fail_count;
    integer j;

    // ========================
    // CLOCK 50MHz (20ns)
    // ========================
    initial clk = 0;
    always #10 clk = ~clk;

    // ========================
    // RESET (active low)
    // ========================
    initial begin
        reset = 0;
        #50;
        reset = 1;
    end

    // ========================
    // DUT
    // ========================
    CPU dut (
        .clk        (clk),
        .reset      (reset),
        .read_dataM (read_dataM),
        .addrM      (addrM),
        .write_dataM(write_dataM),
        .mem_writeM (mem_writeM),
        .mem_readM  (mem_readM)
    );

    // ========================
    // MEMORY MODEL
    // Synchronous read: khớp M9K BRAM behavior
    // Tương thích bram_stall: posedge N clocks addr, data valid sau posedge N
    // Memory_Cycle capture ReadDataM_r tại posedge N+1 (sau khi stall release)
    // ========================
    reg [31:0] tb_mem [0:1023];

    initial begin
        read_dataM = 32'b0;
        for (j = 0; j < 1024; j = j + 1)
            tb_mem[j] = 32'b0;
    end

    always @(posedge clk) begin
        if (mem_writeM)
            tb_mem[addrM[11:2]] <= write_dataM;
        if (mem_readM)
            read_dataM <= tb_mem[addrM[11:2]];
    end

    // ========================
    // TASK: CHECK
    // ========================
    task check;
        input [255:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("  PASS | %-24s | got = 0x%08h", name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL | %-24s | got = 0x%08h | expected = 0x%08h", name, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ========================
    // FIRMWARE LOAD CHECK
    // ========================
    initial begin
        #5;
        $display("============================================================");
        $display("FIRMWARE CHECK");
        $display("  mem[0] = %h  (expected: 00001117 = AUIPC x2, 1)",  dut.Fetch.instruction_memory.mem[0]);
        $display("  mem[1] = %h  (expected: 00010113 = ADDI x2, x2, 0)", dut.Fetch.instruction_memory.mem[1]);
        $display("  mem[2] = %h  (expected: 00c000ef = JAL x1, 12)",   dut.Fetch.instruction_memory.mem[2]);
        $display("============================================================");
    end

    // ========================
    // PIPELINE MONITOR
    // ========================
    initial begin
        $display("\n============================================================");
        $display("PIPELINE MONITOR");
        $display("Time(ns) | PCD      | InstrD   | RegW | RD | ResultW  | StlF StlD | FlsD FlsE | FwdA FwdB | ALU_Result");
        $display("------------------------------------------------------------");
    end

    always @(posedge clk) begin
        if (reset) begin
            $display("%7t  | %h | %h |  %b   | x%-2d | %h |   %b    %b  |   %b    %b  |  %2b   %2b  | %h",
                $time,
                dut.Fetch.PCF_reg,
                dut.InstrD,
                dut.RegWriteW_out,
                dut.RD_out,
                dut.ResultW,
                dut.StallF,
                dut.StallD,
                dut.FlushD,
                dut.FlushE,
                dut.ForwardA_E,
                dut.ForwardB_E,
                dut.Execute.ALU_ResultM_out
            );
        end
    end

    // ========================
    // WRITEBACK LOG
    // ========================
    always @(posedge clk) begin
        if (reset && dut.RegWriteW_out && dut.RD_out != 0) begin
            $display("  >>> WB: x%-2d <= 0x%08h", dut.RD_out, dut.ResultW);
        end
    end

    // ========================
    // MEMORY ACCESS LOG
    // ========================
    always @(posedge clk) begin
        if (reset) begin
            if (mem_writeM)
                $display("  >>> SW: tb_mem[%0d] <= 0x%08h  (addr=0x%08h)", addrM[11:2], write_dataM, addrM);
            if (mem_readM)
                $display("  >>> LW: tb_mem[%0d] read req  (addr=0x%08h)", addrM[11:2], addrM);
        end
    end

    // ========================
    // BRANCH / STALL LOG
    // ========================
    always @(posedge clk) begin
        if (reset) begin
            if (dut.PCSrcE)
                $display("  >>> BRANCH/JUMP at t=%0t | PCTarget=0x%08h", $time, dut.PCTargetE);
            if (dut.Hazard.bram_stall)
                $display("  >>> BRAM STALL   at t=%0t (LW in MEM, waiting data)", $time);
            if (dut.StallF && !dut.Hazard.bram_stall)
                $display("  >>> LW-USE STALL at t=%0t", $time);
        end
    end

    // ========================
    // X DETECTOR
    // ========================
    always @(posedge clk) begin
        if (reset) begin
            if (^dut.ResultW                     === 1'bx) $display("  ERROR: ResultW   = X at t=%0t", $time);
            if (^dut.Fetch.PCF_reg               === 1'bx) $display("  ERROR: PC        = X at t=%0t", $time);
            if (^dut.InstrD                      === 1'bx) $display("  ERROR: InstrD    = X at t=%0t", $time);
            if (^dut.ForwardA_E                  === 1'bx) $display("  ERROR: ForwardA  = X at t=%0t", $time);
            if (^dut.ForwardB_E                  === 1'bx) $display("  ERROR: ForwardB  = X at t=%0t", $time);
            if (^dut.Execute.ALU_ResultM_out     === 1'bx) $display("  ERROR: ALU_Result= X at t=%0t", $time);
        end
    end

    // ========================
    // FORWARDING DEBUG
    // ========================
    initial begin
        $display("\n============================================================");
        $display("FORWARDING DEBUG");
        $display("Time(ns)  | RS1_E RS2_E | RD_E  RD_M  RD_W  | FwdA FwdB | InstrD   ");
        $display("------------------------------------------------------------");
    end

    always @(posedge clk) begin
        if (reset) begin
            $display("%7t  | x%-2d   x%-2d  | x%-2d   x%-2d   x%-2d  |  %2b    %2b  | %h",
                $time,
                dut.RS1_E,
                dut.RS2_E,
                dut.RD_E,
                dut.RD_M,
                dut.RD_W,
                dut.ForwardA_E,
                dut.ForwardB_E,
                dut.InstrD
            );
        end
    end

    // ========================
    // FORWARDING FAIL TRIGGER
    // ========================
    reg [31:0] tb_instrE;   // instruction đang ở EX
    reg [31:0] tb_instrM;   // instruction đang ở MEM

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            tb_instrE <= 32'h0000_0013;
            tb_instrM <= 32'h0000_0013;
        end
        else if (dut.Hazard.bram_stall) begin
            // EX + MEM frozen: hold cả hai
        end
        else if (dut.FlushD || dut.StallD) begin
            tb_instrE <= 32'h0000_0013;   // bubble vào EX
            tb_instrM <= tb_instrE;
        end
        else begin
            tb_instrE <= dut.InstrD;
            tb_instrM <= tb_instrE;
        end
    end

    always @(posedge clk) begin
        if (reset && (dut.ForwardA_E == 2'b00)) begin
            $display("  [FWD00] t=%0t | RS1_E=x%-2d  RD_M=x%-2d  RD_W=x%-2d | FwdA=%b FwdB=%b",
                $time,
                dut.RS1_E, dut.RD_M, dut.RD_W,
                dut.ForwardA_E, dut.ForwardB_E
            );
            $display("          instrE=%h (rd=x%0d rs1=x%0d rs2=x%0d op=%07b)",
                tb_instrE, tb_instrE[11:7], tb_instrE[19:15], tb_instrE[24:20], tb_instrE[6:0]
            );
            $display("          instrM=%h (rd=x%0d rs1=x%0d rs2=x%0d op=%07b)",
                tb_instrM, tb_instrM[11:7], tb_instrM[19:15], tb_instrM[24:20], tb_instrM[6:0]
            );
        end
    end

    // ========================
    // VERIFICATION
    // ~95 instr x avg 2.5 cycle + bram_stall overhead ~= 320 cycle x 20ns = 6400ns
    // #12000 de dam bao chay xong
    // ========================
    initial begin
        pass_count = 0;
        fail_count = 0;

        #12000;

        $display("\n============================================================");
        $display("REGISTER VERIFICATION");
        $display("------------------------------------------------------------");
        check("x2 (stack ptr)",      dut.Decode.regfile.Register[2],  32'h0000_0FE0);

        $display("\n------------------------------------------------------------");
        $display("DATA MEMORY VERIFICATION  (base addr 0x100, index = addr>>2)");
        $display("------------------------------------------------------------");
        check("mem[64]  ADD   5+12",  tb_mem[64],  32'd17        );
        check("mem[65]  SUB  12-5",   tb_mem[65],  32'd7         );
        check("mem[66]  AND   5&12",  tb_mem[66],  32'd4         );
        check("mem[67]  OR    5|12",  tb_mem[67],  32'd13        );
        check("mem[68]  XOR   5^12",  tb_mem[68],  32'd9         );
        check("mem[69]  SLL   5<<2",  tb_mem[69],  32'd20        );
        check("mem[70]  SRL  12>>1",  tb_mem[70],  32'd6         );
        check("mem[71]  SRA  -8>>1",  tb_mem[71],  32'hFFFF_FFFC );
        check("mem[72]  SLT   5<12",  tb_mem[72],  32'd1         );
        check("mem[73]  SLTU  5<12",  tb_mem[73],  32'd1         );
        check("mem[74]  LUI",         tb_mem[74],  32'h1200_0000 );
        check("mem[75]  LW/SW luse",  tb_mem[75],  32'd99        );
        check("mem[76]  BEQ  taken",  tb_mem[76],  32'd1         );
        check("mem[77]  BNE  taken",  tb_mem[77],  32'd1         );
        check("mem[78]  BLT  taken",  tb_mem[78],  32'd1         );
        check("mem[79]  BGE  taken",  tb_mem[79],  32'd1         );
        check("mem[80]  BLTU taken",  tb_mem[80],  32'd1         );
        check("mem[81]  JAL+JALR",    tb_mem[81],  32'd10        );
        check("mem[82]  Forwarding",  tb_mem[82],  32'd39        );
        check("mem[83]  Loop x5",     tb_mem[83],  32'd5         );

        $display("\n============================================================");
        $display("RESULT: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("============================================================\n");

        $display("DEBUG: RD1_E=%h RD2_E=%h | ForwA=%h ForwB=%h | SrcA=%h SrcB=%h",
            dut.Execute.RD1_E,
            dut.Execute.RD2_E,
            dut.Execute.ForwardA_out,
            dut.Execute.ForwardB_out,
            dut.Execute.SrcA,
            dut.Execute.SrcB
        );

        $display("DEBUG: RS2_E=%d ForwardB=%b WriteDataM=%h",
            dut.RS2_E,
            dut.ForwardB_E,
            dut.Memory.WriteDataM
        );

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - Kiem tra pipeline monitor phia tren");

        $stop;
    end

    // ========================
    // TIMEOUT GUARD
    // ========================
    initial begin
        #4000000;
        $display("TIMEOUT - Simulation exceeded limit");
        $stop;
    end

endmodule
