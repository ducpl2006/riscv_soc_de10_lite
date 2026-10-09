`timescale 1ns/1ps
`default_nettype none

// Kiểm tra hợp đồng hai cổng bằng scoreboard độc lập với trạng thái DUT.
module tb_rv32_soc_rom;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, ireq = 0, dreq = 0;
    reg [31:0] iaddr = 0, daddr = 0;
    wire [31:0] idata, ddata;
    wire ignt, irvalid, dready, ierr, derr;
    reg expected_valid = 0, expected_err = 0;
    reg [31:0] expected_data = 0;
    integer k, responses = 0, checks = 0;

    soc_rom_dp #(.WORDS(3)) dut (
        .clk_i(clk), .rst_i(rst), .i_req_i(ireq), .i_addr_i(iaddr),
        .i_gnt_o(ignt), .i_rdata_o(idata), .i_rvalid_o(irvalid),
        .i_err_o(ierr), .d_req_i(dreq), .d_addr_i(daddr),
        .d_rdata_o(ddata), .d_ready_o(dready), .d_err_o(derr));

    // Tại mỗi cạnh, đáp ứng phải khớp yêu cầu được nhận ở cạnh liền trước.
    always @(posedge clk) begin
        if (rst) expected_valid = 0;
        else begin
            if (irvalid !== expected_valid) $fatal(1, "ROM response latency is not one cycle");
            if (expected_valid) begin
                if (ierr !== expected_err || idata !== expected_data)
                    $fatal(1, "ROM response mismatch: data=%h err=%b", idata, ierr);
                responses = responses + 1;
            end
            expected_valid = ireq && ignt;
            expected_err = (iaddr >= 12) || (iaddr[1:0] != 0);
            expected_data = expected_err ? 32'b0 : 32'h12340000 + (iaddr >> 2);
        end
    end

    task data_read;
        input [31:0] address;
        input expected_fault;
        input [31:0] value;
        integer timeout;
        begin
            @(negedge clk); dreq = 1; daddr = address;
            timeout = 0;
            while (!dready && timeout < 8) begin
                @(negedge clk); timeout = timeout + 1;
            end
            if (!dready || derr !== expected_fault || ddata !== value)
                $fatal(1, "Data ROM response: data=%h err=%b", ddata, derr);
            // Giữ req qua cạnh hoàn tất, rồi hạ ở cạnh xuống.
            @(negedge clk); dreq = 0;
            @(negedge clk);
            checks = checks + 1;
        end
    endtask

    initial begin
        for (k = 0; k < 3; k = k + 1)
            dut.u_storage.mem[k] = 32'h12340000 + k;
        repeat (3) @(negedge clk); rst = 0;
        fork
            begin
                @(negedge clk); ireq = 1;
                for (k = 0; k < 12; k = k + 1) begin
                    case (k % 6)
                        0: iaddr = 0;
                        1: iaddr = 4;
                        2: iaddr = 8;
                        3: iaddr = 12;
                        4: iaddr = 2;
                        5: iaddr = 32'hFFFFFFFC;
                    endcase
                    @(negedge clk);
                    if (!ignt) $fatal(1, "ROM refused instruction request");
                end
                ireq = 0;
            end
            begin
                data_read(8, 0, 32'h12340002);
                data_read(2, 1, 0);
                data_read(12, 1, 0);
                data_read(32'hFFFFFFFC, 1, 0);
                data_read(0, 0, 32'h12340000);
            end
        join
        repeat (2) @(negedge clk);
        if (responses != 12) $fatal(1, "Instruction responses lost/duplicated");

        // Nhận yêu cầu ở cả hai cổng rồi reset trước cạnh lấy đáp ứng.
        ireq = 1; iaddr = 4; dreq = 1; daddr = 8;
        @(negedge clk); rst = 1; ireq = 0; dreq = 0;
        repeat (2) @(negedge clk);
        if (irvalid || dready || ierr || derr || ignt)
            $fatal(1, "ROM reset did not cancel pending response");
        rst = 0;
        repeat (3) @(negedge clk);
        if (irvalid || dready) $fatal(1, "ROM stale response after reset");
        data_read(4, 0, 32'h12340001);
        $display("PASS tb_rv32_soc_rom: 12 pipelined responses, %0d data cases, simultaneous ports/reset", checks);
        $finish;
    end
    initial begin #10000; $fatal(1, "ROM timeout"); end
endmodule

`default_nettype wire
