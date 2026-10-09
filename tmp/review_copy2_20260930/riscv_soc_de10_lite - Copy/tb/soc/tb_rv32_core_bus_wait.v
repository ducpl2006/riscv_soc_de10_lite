`timescale 1ns/1ps
`default_nettype none
// Core thật + registered bus; scoreboard độc lập với forwarding/state nội bộ core.
module tb_rv32_core_bus_wait;
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    wire ireq,dreq,dwe,dready,derr,halted,trap,retire,rd_we;
    wire [31:0] iaddr,daddr,wdata,rdata,trap_pc,rd_data;
    wire [3:0] strb;
    wire [4:0] cause,rd;
    reg iv=0;
    reg [31:0] instruction=0;
    reg [31:0] program_mem[0:15], memory[0:3], observed[0:31];
    wire [6:0] select;
    wire [31:0] saddr,swdata;
    wire [3:0] sstrb;
    wire swe;
    reg [223:0] sdata;
    integer mode,n,remaining,watchdog,transactions,retires,stalled;
    wire [6:0] sready={7{remaining==0}};
    reg [31:0] random_q=32'h1458239A;
    reg mheld=0,sheld=0;
    reg [68:0] mpayload,spayload;
    rv32_core core(.clk_i(clk),.rst_i(rst),.imem_req_o(ireq),.imem_addr_o(iaddr),
        .imem_gnt_i(!rst),.imem_rvalid_i(iv),.imem_rdata_i(instruction),.imem_err_i(1'b0),
        .dmem_req_o(dreq),.dmem_we_o(dwe),.dmem_addr_o(daddr),.dmem_wdata_o(wdata),
        .dmem_wstrb_o(strb),.dmem_rdata_i(rdata),.dmem_ready_i(dready),.dmem_err_i(derr),
        .halted_o(halted),.trap_valid_o(trap),.trap_cause_o(cause),.trap_pc_o(trap_pc),
        .trap_instr_o(),.retire_valid_o(retire),.retire_pc_o(),.retire_instr_o(),
        .retire_rd_we_o(rd_we),.retire_rd_addr_o(rd),.retire_rd_data_o(rd_data),.debug_fetch_pc_o());
    soc_bus bus(.clk_i(clk),.rst_i(rst),.req_i(dreq),.we_i(dwe),.addr_i(daddr),
        .wdata_i(wdata),.wstrb_i(strb),.rdata_o(rdata),.ready_o(dready),.err_o(derr),
        .slave_req_o(select),.slave_addr_o(saddr),.slave_we_o(swe),
        .slave_wdata_o(swdata),.slave_wstrb_o(sstrb),.slave_rdata_i(sdata),
        .slave_ready_i(sready),.slave_err_i(7'b0));
    always @* begin
        sdata=0;
        sdata[32 +: 32]=memory[saddr[3:2]];
        sdata[64 +: 32]=memory[3];
    end
    always @(posedge clk) begin
        if(rst) begin
            iv<=0; instruction<=0; remaining<=mode; transactions<=0; retires<=0; stalled<=0;
            mheld<=0; sheld<=0;
            for(n=0;n<4;n=n+1) memory[n]<=0;
            for(n=0;n<32;n=n+1) observed[n]<=0;
        end
        else begin
            iv<=ireq;
            if(ireq) instruction<=program_mem[iaddr[5:2]];
            if(retire) begin retires<=retires+1; if(rd_we) observed[rd]<=rd_data; end
            if(select!=0 && remaining>0) remaining<=remaining-1;
            if((select&sready)!=0) begin
                transactions<=transactions+1;
                if(swe) begin
                    if(sstrb!==15) $fatal(1,"Unexpected store strobe");
                    if(select[1]) memory[saddr[3:2]]<=swdata;
                    else if(select[2]) memory[3]<=swdata;
                    else $fatal(1,"Unexpected store lane");
                end
                random_q<= {random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
                remaining<= mode<3 ? mode : 3+random_q[3:0];
            end
            if(mheld && (!dreq || {dwe,daddr,wdata,strb}!==mpayload)) $fatal(1,"Core changed pending request");
            if(sheld && (select==0 || {swe,saddr,swdata,sstrb}!==spayload)) $fatal(1,"Bus changed pending request");
            mheld<=dreq&&!dready; mpayload<={dwe,daddr,wdata,strb};
            sheld<=select!=0 && (select&sready)==0; spayload<={swe,saddr,swdata,sstrb};
            if(dreq&&!dready) stalled<=stalled+1;
        end
    end
    initial begin
        for(n=0;n<16;n=n+1) program_mem[n]=32'h00100073;
        program_mem[0]=32'h10000537; // lui x10,RAM
        program_mem[1]=32'h02A00093; // addi x1,42
        program_mem[2]=32'h00052023; // sw x0,0(x10), giữ MEM nhiều clock
        program_mem[3]=32'h00108113; // addi x2,x1,1: operand WB phải sống qua stall
        program_mem[4]=32'h00252223; // sw x2,4(x10): store forwarding
        program_mem[5]=32'h00452183; // lw x3,4(x10)
        program_mem[6]=32'h00218233; // add x4,x3,x2: load-use
        program_mem[7]=32'h00452423; // sw x4,8(x10)
        program_mem[8]=32'h200005B7; // lui x11,GPIO
        program_mem[9]=32'h0045A023; // sw x4,0(x11)
        program_mem[10]=32'h0005A283; // lw x5,0(x11)
        program_mem[11]=32'h00100073;
        for(mode=0;mode<4;mode=mode+1) begin
            rst=1; repeat(3) @(negedge clk); rst=0; watchdog=0;
            while(!trap && watchdog<1000) begin @(negedge clk); watchdog=watchdog+1; end
            if(!halted || cause!==3 || trap_pc!==44 || transactions!=6 || retires!=11 || stalled==0 ||
                observed[1]!==42 || observed[2]!==43 || observed[3]!==43 || observed[4]!==86 || observed[5]!==86 ||
                memory[1]!==43 || memory[2]!==86 || memory[3]!==86)
                $fatal(1,"Core/bus wait mode=%0d result/side-effect mismatch transactions=%0d retires=%0d",mode,transactions,retires);
        end
        $display("PASS tb_rv32_core_bus_wait: 0/1/2/random wait, WB operand retention, forwarding/load-use, RAM/MMIO");
        $finish;
    end
    initial begin #100000; $fatal(1,"Core/bus timeout"); end
endmodule
`default_nettype wire
