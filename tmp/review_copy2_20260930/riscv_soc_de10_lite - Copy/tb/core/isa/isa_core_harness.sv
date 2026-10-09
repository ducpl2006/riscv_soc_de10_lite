`timescale 1ns/1ps
`default_nettype none
// External memory + architectural trace only: never force DUT internal state.
// +IMAGE is a 64-KiB byte image; +PC/+CAUSE specify the exact expected trap.
// +SEED=0 has no data wait; other seeds delay grants and data completion.
module isa_core_harness;
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    reg [7:0] memory[0:65535];
    reg [31:0] observed[0:31];
    wire ireq,dreq,dwe,halted,trap,retire,rd_we;
    wire [31:0] iaddr,daddr,wdata,trap_pc,trap_insn,rd_data,retire_pc,retire_insn;
    wire [3:0] strb;
    wire [4:0] cause,rd;
    reg iv=0,ie=0;
    reg [31:0] instruction=0;
    reg [31:0] rng=1;
    integer seed=0,expected_cause=3,cycles=0,retires=0,transactions=0,k;
    reg [31:0] expected_pc;
    reg [1023:0] image_file;
    wire grant=!rst && (seed==0 || rng[2:0]!=0);
    wire ready=!rst && (seed==0 || rng[6:3]==0);
    wire error=daddr>=65536;
    wire [15:0] base={daddr[15:2],2'b00};
    wire [31:0] data_read={memory[base+3],memory[base+2],memory[base+1],memory[base]};
    reg held=0;
    reg [68:0] payload;
    rv32_core dut(.clk_i(clk),.rst_i(rst),.imem_req_o(ireq),.imem_addr_o(iaddr),
        .imem_gnt_i(grant),.imem_rvalid_i(iv),.imem_rdata_i(instruction),.imem_err_i(ie),
        .dmem_req_o(dreq),.dmem_we_o(dwe),.dmem_addr_o(daddr),.dmem_wdata_o(wdata),
        .dmem_wstrb_o(strb),.dmem_rdata_i(data_read),.dmem_ready_i(ready),.dmem_err_i(error&&ready),
        .halted_o(halted),.trap_valid_o(trap),.trap_cause_o(cause),.trap_pc_o(trap_pc),
        .trap_instr_o(trap_insn),.retire_valid_o(retire),.retire_pc_o(retire_pc),
        .retire_instr_o(retire_insn),.retire_rd_we_o(rd_we),.retire_rd_addr_o(rd),
        .retire_rd_data_o(rd_data),.debug_fetch_pc_o());
    always @(posedge clk) begin
        if(rst) begin iv<=0; held<=0; end
        else begin
            rng <= {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            iv<=ireq&&grant;
            if(ireq&&grant) begin
                ie<=iaddr>=65536;
                instruction<=iaddr<65536 ? {memory[iaddr+3],memory[iaddr+2],memory[iaddr+1],memory[iaddr]} : 0;
            end
            if(held && (!dreq || {dwe,daddr,wdata,strb}!==payload))
                $fatal(1,"ISA pending data payload changed");
            held<=dreq&&!ready; payload<={dwe,daddr,wdata,strb};
            if(dreq&&ready) begin
                transactions<=transactions+1;
                if(dwe&&!error) for(k=0;k<4;k=k+1) if(strb[k]) memory[base+k]<=wdata[8*k+:8];
            end
            if(retire) begin
                retires<=retires+1;
                if(rd_we) begin
                    if(rd==0) $fatal(1,"ISA trace wrote x0");
                    observed[rd]<=rd_data;
                end
            end
        end
    end
    initial begin
        if(!$value$plusargs("IMAGE=%s",image_file)) $fatal(1,"Missing IMAGE");
        if(!$value$plusargs("PC=%h",expected_pc)) $fatal(1,"Missing PC");
        if($value$plusargs("CAUSE=%d",expected_cause)) begin end
        if($value$plusargs("SEED=%d",seed)) begin end
        rng=seed==0 ? 1 : seed;
        for(k=0;k<32;k=k+1) observed[k]=0;
        $readmemh(image_file,memory);
        repeat(4) @(negedge clk); rst=0;
        while(!trap&&cycles<300000) begin @(negedge clk); cycles=cycles+1; end
        if(!trap || !halted || cause!==expected_cause || trap_pc!==expected_pc || observed[10]!==1)
            $fatal(1,"ISA trap mismatch pc=%h expected=%h cause=%0d expected=%0d a0=%h testnum=%0d cycles=%0d",
                trap_pc,expected_pc,cause,expected_cause,observed[10],observed[3],cycles);
        if(memory[16'hff00]!==0) $fatal(1,"Younger/wrong-path store committed");
        repeat(8) @(negedge clk);
        if(retire||dreq) $fatal(1,"Activity after halt");
        $display("PASS ISA seed=%0d retired=%0d transactions=%0d cycles=%0d",seed,retires,transactions,cycles);
        $finish;
    end
endmodule
`default_nettype wire
