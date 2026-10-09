`timescale 1ns/1ps
// Review probes for the unmodified source archive; no project RTL is instantiated.
module tb_reference_apb_strobe;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 0;
    reg [31:0] addr = 0, data = 0;
    reg sel = 0, enable = 0, we = 0;
    reg [3:0] strb = 0;
    wire [31:0] rdata;
    wire ready, err;
    tri1 scl, sda;
    integer violations = 0;
    APB4_I2C_Slave dut (.clk(clk), .reset(reset), .PADDR(addr), .PSEL(sel),
        .PENABLE(enable), .PWRITE(we), .PWDATA(data), .PSTRB(strb), .PPROT(3'b0),
        .PRDATA(rdata), .PREADY(ready), .PSLVERR(err), .irq(), .scl(scl), .sda(sda));
    task write_timeout;
        input [31:0] value;
        input [3:0] mask;
        begin
            @(negedge clk); addr=32'h40000030; data=value; strb=mask; sel=1; we=1;
            @(negedge clk); enable=1;
            #1; if (!ready || err) $fatal(1, "Probe APB transaction rejected");
            @(negedge clk); sel=0; enable=0; we=0;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk); reset=1;
        write_timeout(32'h00123456, 4'hF);
        #1; if (rdata !== 32'h00123456) $fatal(1, "Probe initial write failed");
        write_timeout(32'h000000AB, 4'h1);
        #1;
        if (rdata !== 32'h001234AB) begin
            violations=violations+1;
            $display("VIOLATION partial write: expected 001234ab, actual %h", rdata);
        end
        write_timeout(32'h00123456, 4'hF);
        write_timeout(32'hFFFFFFFF, 4'h0);
        #1;
        if (rdata !== 32'h00123456) begin
            violations=violations+1;
            $display("VIOLATION zero strobe: expected 00123456, actual %h", rdata);
        end
        $display("REVIEW: %0d byte-strobe violations observed", violations);
        $finish;
    end
    initial begin #5000; $fatal(1, "Probe timeout"); end
endmodule

module tb_reference_mem_mdu_stall;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=0, raw_read=0, ready=0, mdu_busy=0;
    wire stall_m, bus_read;
    wire [31:0] wb_data;
    Memory_Cycle mem (.clk(clk), .reset(reset), .RegWriteM(1'b1),
        .MemReadM(raw_read), .MemWriteM(1'b0), .ResultSrcM(2'b01), .RD_M(5'd2),
        .PCPlus4M(32'd4), .WriteDataM(32'd0), .ALU_ResultM(32'h100),
        .read_dataM_in(32'h12345678), .mem_ready(ready), .StallM(stall_m),
        .funct3M(3'b010), .addrM(), .write_dataM(), .mem_writeM(), .mem_readM(bus_read),
        .RegWriteW_actual(), .RegWriteW_fwd(), .ResultSrcW(), .RD_W(),
        .PCPlus4W(), .ALU_ResultW(), .ReadDataW(wb_data), .write_strbM());
    // Same raw MemReadM -> Hazard and gated mem_readM -> manager connections as CPU.v.
    Hazard_Unit hazard (.clk(clk), .reset(reset), .RegWriteM(1'b1),
        .RegWriteW_fwd(1'b0), .RD_M(5'd2), .RD_W(5'd0), .RS1_E(5'd3), .RS2_E(5'd4),
        .MemReadE(1'b0), .RD_E(5'd5), .RS1_D(5'd6), .RS2_D(5'd7),
        .MemReadM(raw_read), .MemWriteM(1'b0), .PCSrcE(1'b0),
        .mem_ready(ready), .MDU_Busy(mdu_busy), .ForwardA_E(), .ForwardB_E(),
        .StallF(), .StallD(), .StallE(), .StallM(stall_m), .HoldE(), .FlushD(), .FlushE());
    initial begin
        repeat (3) @(negedge clk); reset=1; raw_read=1; mdu_busy=1;
        @(negedge clk); ready=1;
        @(negedge clk); ready=0;
        if (mem.axi_done_latch !== 1 || bus_read !== 0)
            $fatal(1, "Probe completion was not captured");
        @(negedge clk); mdu_busy=0;
        repeat (5) @(negedge clk);
        if (stall_m === 1 && bus_read === 0 && mem.axi_done_latch === 1)
            $display("VIOLATION: MDU idle, memory completion latched, but StallM=1 and bus request=0; no progress");
        else
            $display("REVIEW: completion released pipeline, StallM=%b", stall_m);
        $finish;
    end
    initial begin #5000; $fatal(1, "Probe timeout"); end
endmodule
