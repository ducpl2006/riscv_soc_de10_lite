`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench SRAM on-chip và wrapper memory đồng bộ.
 *
 * Kiểm tra word read/write, từng byte lane, biên cuối vùng, lỗi alignment/range
 * và contract: ready chỉ xuất hiện sau khi request đã được chụp. Test này bảo vệ
 * cả hành vi RTL lẫn cấu trúc handshake dùng cho backend altsyncram khi tổng hợp.
 */
module tb_rv32_soc_ram;

    localparam integer WORDS = 16;
    reg clk;
    reg rst;
    reg req;
    reg we;
    reg [31:0] addr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire [31:0] rdata;
    wire ready;
    wire err;
    integer checks;

    soc_ram #(.WORDS(WORDS)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we),
        .addr_i(addr), .wdata_i(wdata), .wstrb_i(wstrb),
        .rdata_o(rdata), .ready_o(ready), .err_o(err)
    );

    always #5 clk = ~clk;

    task access;
        input        access_we;
        input [31:0] access_addr;
        input [31:0] access_wdata;
        input [3:0]  access_wstrb;
        input        expected_err;
        output [31:0] read_value;
        integer timeout;
        begin
            @(negedge clk);
            req = 1'b1; we = access_we; addr = access_addr;
            wdata = access_wdata; wstrb = access_wstrb;
            #1;
            if (ready)
                $fatal(1, "ready khong duoc combinational trong chu ky request dau");

            timeout = 0;
            while (!ready && timeout < 8) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!ready || err !== expected_err)
                $fatal(1, "Sai response addr=%08x ready=%b err=%b", access_addr, ready, err);
            read_value = rdata;
            checks = checks + 2;

            @(negedge clk);
            req = 1'b0; we = 1'b0; wstrb = 4'b0000;
        end
    endtask

    reg [31:0] value;
    initial begin
        clk = 0; rst = 1; req = 0; we = 0; addr = 0;
        wdata = 0; wstrb = 0; checks = 0;
        repeat (3) @(posedge clk);
        rst = 0;

        access(1, 32'h00, 32'h1122_3344, 4'b1111, 0, value);
        access(0, 32'h00, 32'h0000_0000, 4'b0000, 0, value);
        if (value !== 32'h1122_3344) $fatal(1, "Sai full-word read");
        checks = checks + 1;

        access(1, 32'h00, 32'h0000_AA00, 4'b0010, 0, value);
        access(1, 32'h00, 32'hBBBB_0000, 4'b1100, 0, value);
        access(0, 32'h00, 32'h0000_0000, 4'b0000, 0, value);
        if (value !== 32'hBBBB_AA44) $fatal(1, "Sai byte-enable: %08x", value);
        checks = checks + 1;

        access(1, WORDS*4-4, 32'hCAFE_BABE, 4'b1111, 0, value);
        access(0, WORDS*4-4, 32'h0000_0000, 4'b0000, 0, value);
        if (value !== 32'hCAFE_BABE) $fatal(1, "Sai word cuoi RAM");
        checks = checks + 1;

        access(0, 32'h0000_0002, 0, 0, 1, value);
        if (value !== 32'd0) $fatal(1, "Misaligned read phai tra 0");
        access(0, WORDS*4, 0, 0, 1, value);
        if (value !== 32'd0) $fatal(1, "Out-of-range read phai tra 0");
        checks = checks + 2;

        // Invalid and zero-strobe writes must preserve the previously stored word.
        access(1, 32'h00, 32'hFFFF_FFFF, 0, 0, value);
        access(1, 32'h02, 32'hFFFF_FFFF, 15, 1, value);
        access(1, WORDS*4, 32'hFFFF_FFFF, 15, 1, value);
        access(0, 32'h00, 0, 0, 0, value);
        if (value !== 32'hBBBB_AA44) $fatal(1, "Invalid write changed RAM");

        // Reset must not enable the storage primitive, even with an active write.
        @(negedge clk);
        rst = 1; req = 1; we = 1; addr = 0; wdata = 32'hDEAD_BEEF; wstrb = 15;
        repeat (3) @(negedge clk);
        req = 0; we = 0; rst = 0;
        access(0, 0, 0, 0, 0, value);
        if (value !== 32'hBBBB_AA44) $fatal(1, "Reset wrote storage");
        checks = checks + 2;

        $display("PASS tb_rv32_soc_ram: %0d checks", checks);
        $finish;
    end

endmodule

`default_nettype wire
