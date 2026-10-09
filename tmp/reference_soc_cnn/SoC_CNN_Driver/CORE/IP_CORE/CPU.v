    // ==============================================
    // + Module top 5 pipeline CPU
    // + Fetch, Decode, Execute, Memory, Write Back
    // ==============================================

    //`include "Fetch_Cycle.v"
    //`include "Decode_Cycle.v"
    //`include "Execute_Cycle.v"
    //`include "Memory_Cycle.v"
    //`include "Writeback_Cycle.v"
    //`include "Hazard_Unit.v"

    module CPU (
        input clk,
        input reset,

        // Memory Interface
        input [31:0]    read_dataM,
        input           mem_ready,

        output [31:0]   addrM,
        output [31:0]   write_dataM,
        output          mem_writeM,
        output          mem_readM,
        
        output [3:0]    write_strbM
    );

        // =============== Interim Wires ===============
        wire PCSrcE;
        wire [31:0] PCTargetE;

        wire StallF;
        wire StallD;
        wire FlushD;

        wire [31:0] InstrD;
        wire [31:0] PCD;
        wire [31:0] PCPlus4D;

        wire RegWriteW_actual;
        wire RegWriteW_fwd;
        wire [4:0] RDW;
        wire [31:0] ResultW;

        wire RegWriteE;
        wire AluSrcAE;
        wire AluSrcBE;
        wire MemWriteE;
        wire MemReadE;
        wire [1:0] ResultSrcE;
        wire BranchE;
        wire JumpE;
        wire BrUnE;
        wire [3:0] ALUControlE;
        wire [2:0] funct3E;
        wire [31:0] RD1_E;
        wire [31:0] RD2_E;
        wire [31:0] Imm_Ext_E;
        wire [4:0] RS1_E;
        wire [4:0] RS2_E;
        wire [4:0] RD_E;
        wire [4:0] RS1_D;
        wire [4:0] RS2_D;
        wire [31:0] PCE;
        wire [31:0] PCPlus4E;

        wire FlushE;
        wire StallE;
        wire StallM;
        wire HoldE;
        wire [1:0] ForwardA_E;
        wire [1:0] ForwardB_E;

        // Tạm thời bỏ ALU_ResultM: Tránh floating
        //wire [31:0] ALU_ResultM;

        wire RegWriteM;
        wire MemWriteM;
        wire MemReadM;
        wire [1:0] ResultSrcM;
        wire [4:0] RD_M;
        wire [31:0] ALU_ResultM_out;
        wire [31:0] WriteDataM;
        wire [31:0] PCPlus4M;

        wire [1:0] ResultSrcW;
        wire [4:0] RD_W;
        wire [31:0] PCPlus4W;
        wire [31:0] ALU_ResultW;
        wire [31:0] ReadDataW;

        wire RegWriteW_out;
        wire [4:0] RD_out;

        wire MDU_EnE;
        wire MDU_Busy;
        wire [2:0] funct3M;

        // =============== FETCH CYLCLE ===============
        Fetch_Cycle Fetch (

            // Input
            .clk            (clk),
            .reset          (reset),

            .PCSrcE         (PCSrcE),
            .PCTargetE      (PCTargetE),
            
            .StallF         (StallF),
            .StallD         (StallD),
            .FlushD         (FlushD),

            // Output
            .InstrD         (InstrD),
            .PCD            (PCD),
            .PCPlus4D       (PCPlus4D)
        );


        // =============== DECODE CYLCLE ===============
        Decode_Cycle Decode (

            // Input
            .clk            (clk),
            .reset          (reset),

            .RegWriteW      (RegWriteW_out),
            .RDW            (RD_out),
            .ResultW        (ResultW),

            .InstrD         (InstrD),
            .PCD            (PCD),
            .PCPlus4D       (PCPlus4D),

            .FlushD         (FlushD),
            .StallD         (StallD),
            .HoldE          (HoldE),

            // Output
            .RegWriteE      (RegWriteE),
            .AluSrcAE       (AluSrcAE),
            .AluSrcBE       (AluSrcBE),
            .MemWriteE      (MemWriteE),
            .MemReadE       (MemReadE),
            .ResultSrcE     (ResultSrcE),
            .BranchE        (BranchE),
            .JumpE          (JumpE),
            .BrUnE          (BrUnE),
            .ALUControlE    (ALUControlE),
            .MDU_EnE        (MDU_EnE),

            .funct3E        (funct3E),

            .RD1_E          (RD1_E),
            .RD2_E          (RD2_E),
            .Imm_Ext_E      (Imm_Ext_E),

            .RS1_E          (RS1_E),
            .RS2_E          (RS2_E),
            .RD_E           (RD_E),

            .RS1_D          (RS1_D),
            .RS2_D          (RS2_D),

            .PCE            (PCE),
            .PCPlus4E       (PCPlus4E)
        );


        // =============== EXECUTE CYLCLE ===============
        Execute_Cycle Execute (

            // Input
            .clk            (clk),
            .reset          (reset),

            .RD1_E          (RD1_E),
            .RD2_E          (RD2_E),
            .Imm_Ext_E      (Imm_Ext_E),

            .RD_E           (RD_E),

            .PCE            (PCE),
            .PCPlus4E       (PCPlus4E),

            .RegWriteE      (RegWriteE),
            .MemReadE       (MemReadE),
            .MemWriteE      (MemWriteE),
            .AluSrcAE       (AluSrcAE),
            .AluSrcBE       (AluSrcBE),
            .ResultSrcE     (ResultSrcE),
            .BranchE        (BranchE),
            .JumpE          (JumpE),
            .BrUnE          (BrUnE),
            .ALUControlE    (ALUControlE),
            .MDU_EnE        (MDU_EnE),

            .funct3E        (funct3E),

            .ResultW        (ResultW),
            .ForwardA_E     (ForwardA_E),
            .ForwardB_E     (ForwardB_E),

            /* Fix ALU_Result
                - ALU_ResultM_out là output của EX -- > MEM
                - ALU_ResultM_out từ 
            */ 

            .ALU_ResultM    (ALU_ResultM_out),
            .StallE         (StallE),

            // Output
            .RegWriteM      (RegWriteM),
            .MemWriteM      (MemWriteM),
            .MemReadM       (MemReadM),
            .ResultSrcM     (ResultSrcM),

            .RD_M           (RD_M),
            .ALU_ResultM_out (ALU_ResultM_out),
            .WriteDataM     (WriteDataM),
            .PCPlus4M       (PCPlus4M),
            .PCSrcE         (PCSrcE),
            .PCTargetE      (PCTargetE),

            .MDU_Busy       (MDU_Busy),
            .funct3M        (funct3M)
        );


        // =============== MEMORY CYLCLE ===============
        // MEM new: Dùng Bus
        Memory_Cycle Memory (

            // Input
            .clk            (clk),
            .reset          (reset),

            .RegWriteM      (RegWriteM),
            .MemReadM       (MemReadM),
            .MemWriteM      (MemWriteM),

            .ResultSrcM     (ResultSrcM),

            .RD_M           (RD_M),

            .PCPlus4M       (PCPlus4M),
            .WriteDataM     (WriteDataM),
            .ALU_ResultM    (ALU_ResultM_out),

            // Input BUS
            .read_dataM_in  (read_dataM),
            .mem_ready      (mem_ready),
            .StallM         (StallM),
            .funct3M        (funct3M),
            // Output BUS
            .addrM          (addrM),
            .write_dataM    (write_dataM),
            .mem_writeM     (mem_writeM),
            .mem_readM      (mem_readM),

            // Output WB
            .RegWriteW_actual (RegWriteW_actual),
            .RegWriteW_fwd    (RegWriteW_fwd),         

            .ResultSrcW     (ResultSrcW),
            .RD_W           (RD_W),

            .PCPlus4W       (PCPlus4W),
            .ALU_ResultW    (ALU_ResultW),
            .ReadDataW      (ReadDataW),
            .write_strbM    (write_strbM)
        );


        // =============== WRITE BACK CYLCLE ===============
        Writeback_Cycle Writeback (

            // Input
            .RegWriteW      (RegWriteW_actual),
            .ResultSrcW     (ResultSrcW),
            .RD_W           (RD_W),
            .PCPlus4W       (PCPlus4W),
            .ALU_ResultW    (ALU_ResultW),
            .ReadDataW      (ReadDataW),

            // Output
            .RegWriteW_out  (RegWriteW_out),
            .RD_out         (RD_out),
            .ResultW        (ResultW)
        );


        // =============== HAZARD UNIT ===============
        Hazard_Unit Hazard (

            // Input
            .clk            (clk),
            .reset          (reset),

            .RegWriteM      (RegWriteM),
            .RegWriteW_fwd  (RegWriteW_fwd),

            .RD_M           (RD_M),
            .RD_W           (RD_W),

            .RS1_E          (RS1_E),
            .RS2_E          (RS2_E),

            .MemReadE       (MemReadE),
            .RD_E           (RD_E),
            .RS1_D          (RS1_D),
            .RS2_D          (RS2_D),

            .MemReadM       (MemReadM),
            .MemWriteM      (MemWriteM),
            .PCSrcE         (PCSrcE),

            .mem_ready      (mem_ready),

            .MDU_Busy       (MDU_Busy),

            // Output
            .ForwardA_E     (ForwardA_E),
            .ForwardB_E     (ForwardB_E),
            .StallF         (StallF),
            .StallD         (StallD),
            .StallE         (StallE),
            .StallM         (StallM),
            .HoldE          (HoldE),
            .FlushD         (FlushD),
            .FlushE         (FlushE)
        );

    endmodule