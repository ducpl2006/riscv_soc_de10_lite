`timescale 1ns/1ps
`default_nettype none
// Giữ coverage địa chỉ cũ, kiểm tra latency mới và cả hai ranh giới handshake.
module tb_rv32_soc_bus;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, req=0, we=0;
    reg [31:0] addr=0, wdata=0;
    reg [3:0] wstrb=0;
    wire [31:0] rdata, saddr, swdata;
    wire [3:0] sstrb;
    wire ready, err, swe;
    wire [6:0] select;
    reg [223:0] slave_data;
    reg [6:0] slave_ready=0, slave_err=0;
    integer checks=0, lane, offset, i, slave_commits=0, before_commits;
    reg [31:0] base, random_q=32'h713BC08F;
    reg m_wait=0, s_wait=0;
    reg [68:0] m_previous, s_previous;
    reg [6:0] select_previous;
    soc_bus #(.ROM_WORDS(16), .RAM_WORDS(8)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we), .addr_i(addr),
        .wdata_i(wdata), .wstrb_i(wstrb), .slave_addr_o(saddr),
        .slave_we_o(swe), .slave_wdata_o(swdata), .slave_wstrb_o(sstrb),
        .rdata_o(rdata), .ready_o(ready), .err_o(err), .slave_req_o(select),
        .slave_rdata_i(slave_data), .slave_ready_i(slave_ready), .slave_err_i(slave_err));
    always @(posedge clk) begin
        if (rst) begin m_wait<=0; s_wait<=0; end
        else begin
            if (m_wait && (!req || {addr,we,wdata,wstrb} !== m_previous))
                $fatal(1, "Master changed stalled payload");
            if (s_wait && (select !== select_previous || {saddr,swe,swdata,sstrb} !== s_previous))
                $fatal(1, "Bus changed stalled slave payload");
            if (ready && !req) $fatal(1, "Response without transaction");
            if ((select & (select-1'b1)) != 0) $fatal(1, "Slave select not one-hot");
            if ((select & slave_ready) != 0) slave_commits=slave_commits+1;
            m_wait <= req && !ready;
            s_wait <= (select != 0) && ((select & slave_ready) == 0);
            m_previous <= {addr,we,wdata,wstrb};
            s_previous <= {saddr,swe,swdata,sstrb};
            select_previous <= select;
        end
    end
    task transfer;
        input [31:0] address;
        input write_access;
        input integer expected_lane;
        input integer delay_cycles;
        input fault;
        integer n;
        begin
            // Caller đang ở negedge; req giữ cao qua các giao dịch liên tiếp.
            addr=address; we=write_access; req=1;
            wdata=address ^ 32'h1234ABCD; wstrb=checks % 16;
            slave_ready=7'h7F; slave_err=7'h7F;
            if (expected_lane>=0) begin
                slave_ready[expected_lane]=0;
                slave_err[expected_lane]=fault;
            end
            before_commits=slave_commits;
            #1;
            if (ready || select) $fatal(1, "Request bypassed register");
            @(negedge clk); #1;
            if (ready) $fatal(1, "Response bypassed register");
            if (expected_lane<0) begin
                if (select) $fatal(1, "Invalid access selected slave");
            end
            else begin
                if (select !== (7'b1 << expected_lane) || saddr !== addr ||
                    swe !== we || swdata !== wdata || sstrb !== wstrb)
                    $fatal(1, "Latched decode/payload mismatch address=%h", addr);
                for (n=0;n<delay_cycles;n=n+1) begin
                    @(negedge clk); #1;
                    if (ready || err || rdata) $fatal(1, "Premature completion while waiting");
                end
                slave_ready[expected_lane]=1;
            end
            @(negedge clk); #1;
            if (!ready || select || err !== (fault || expected_lane<0))
                $fatal(1, "Response error addr=%h ready=%b err=%b", addr,ready,err);
            if (rdata !== ((fault || expected_lane<0) ? 0 : 32'hA0000000+expected_lane))
                $fatal(1, "Response data mismatch");
            slave_ready=0; slave_err=~slave_err;
            #1;
            if (!ready || err !== (fault || expected_lane<0)) $fatal(1, "Response not registered");
            @(negedge clk);
            if (slave_commits-before_commits != (expected_lane>=0 ? 1 : 0))
                $fatal(1, "Missing/duplicate slave transaction");
            checks=checks+1;
        end
    endtask
    initial begin
        for (lane=0;lane<7;lane=lane+1) slave_data[lane*32 +: 32]=32'hA0000000+lane;
        repeat (3) @(negedge clk); rst=0;
        transfer(0,0,0,0,0); transfer(60,0,0,1,0); transfer(64,0,-1,0,0);
        transfer(0,1,-1,0,0); transfer(32'h10000000,1,1,2,0);
        transfer(32'h1000001C,0,1,7,0); transfer(32'h10000020,1,-1,0,0);
        transfer(32'h0FFFFFFC,0,-1,0,0); transfer(32'hFFFFFFFF,0,-1,0,0);
        for (lane=2;lane<7;lane=lane+1) begin
            base=32'h20000000+(lane-2)*4096;
            for (offset=0;offset<4096;offset=offset+4)
                transfer(base+offset,0,lane,0,0);
            transfer(base+1,0,-1,0,0); transfer(base+2,1,-1,0,0);
        end
        transfer(32'h20005000,0,-1,0,0);
        for (i=0;i<128;i=i+1) begin
            random_q=random_q^(random_q<<13);
            random_q=random_q^(random_q>>17);
            random_q=random_q^(random_q<<5);
            lane=1+(random_q%6);
            base=(lane==1)?32'h10000000:32'h20000000+(lane-2)*4096;
            transfer(base,random_q[8],lane,random_q[3:0],random_q[9]);
        end
        req=0; #1;
        if (ready || err || select || rdata) $fatal(1, "Idle isolation");
        req=1; addr=32'h10000000; slave_ready=0;
        @(negedge clk); rst=1; #1;
        if (ready || select || err) $fatal(1, "Reset isolation");
        @(negedge clk); req=0; rst=0; slave_ready=7'h7F;
        repeat (3) @(negedge clk);
        if (ready || select) $fatal(1, "Reset left pending transaction");
        $display("PASS tb_rv32_soc_bus: %0d address/stress transfers; registered request/response, no duplicates",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Bus test timeout"); end
endmodule
`default_nettype wire
