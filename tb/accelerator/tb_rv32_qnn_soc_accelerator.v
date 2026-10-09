`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Testbench : tb_rv32_qnn_soc_accelerator
// Mục tiêu  : Kiểm tra MMIO, thứ tự MAC 80-16-8-1, ReLU, cờ busy/done,
//             bộ đếm chu kỳ và chặn kết quả SOC.
//
// Model vàng cực nhỏ nằm trong topology thật:
//   h1[0] = ReLU(input[0]*2 + 1)
//   h2[0] = ReLU(h1[0]*3)
//   y      = clamp(h2[0]*4, 0, 1000)
// Với input[0]=3, kết quả mong đợi là (3*2+1)*3*4 = 84.
// =============================================================================
module tb_rv32_qnn_soc_accelerator;

    reg clk;
    reg rst;
    reg req;
    reg we;
    reg [11:0] addr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire [31:0] rdata;
    wire ready;
    wire err;
    wire busy;
    wire done;
    wire [31:0] result_value;

    integer checks;
    integer timeout;

    qnn_soc_accelerator dut (
        .clk_i(clk), .rst_i(rst),
        .bus_req_i(req), .bus_we_i(we), .bus_addr_i(addr),
        .bus_wdata_i(wdata), .bus_wstrb_i(wstrb),
        .bus_rdata_o(rdata), .bus_ready_o(ready), .bus_err_o(err),
        .busy_o(busy), .done_o(done), .result_o(result_value)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL tb_rv32_qnn_soc_accelerator: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task mmio_write;
        input [11:0] write_addr;
        input [31:0] write_data;
        begin
            @(negedge clk);
            req   = 1'b1;
            we    = 1'b1;
            addr  = write_addr;
            wdata = write_data;
            wstrb = 4'b1111;
            #1;
            check(ready && !err, "giao dich ghi MMIO phai duoc chap nhan");
            @(negedge clk);
            req   = 1'b0;
            we    = 1'b0;
            addr  = 12'd0;
            wdata = 32'd0;
            wstrb = 4'd0;
        end
    endtask

    task mmio_read_check;
        input [11:0] read_addr;
        input [31:0] mask;
        input [31:0] expected;
        begin
            @(negedge clk);
            req  = 1'b1;
            we   = 1'b0;
            addr = read_addr;
            #1;
            check(ready && !err, "giao dich doc MMIO phai duoc chap nhan");
            check((rdata & mask) == expected, "du lieu doc MMIO khong dung");
            @(negedge clk);
            req  = 1'b0;
            addr = 12'd0;
        end
    endtask

    initial begin
        clk    = 1'b0;
        rst    = 1'b1;
        req    = 1'b0;
        we     = 1'b0;
        addr   = 12'd0;
        wdata  = 32'd0;
        wstrb  = 4'd0;
        checks = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        // Ghi model kiểm thử sau initial zero-fill của DUT.
        dut.u_l1_weight_rom.mem[0] = 8'sd2;
        dut.l1_biases[0]  = 32'sd1;
        dut.u_l2_weight_rom.mem[0] = 8'sd3;
        dut.out_weights[0] = 8'sd4;

        mmio_read_check(12'h010, 32'hFFFF_FFFF, {8'd80, 8'd16, 8'd8, 8'd1});
        mmio_write(12'h100, 32'd3);
        mmio_read_check(12'h100, 32'hFFFF_FFFF, 32'd3);
        mmio_write(12'h000, 32'd1);
        check(busy && !done, "start phai dua accelerator vao busy");

        // Giữ write pending suốt suy luận: không được báo success rồi bỏ dữ liệu.
        @(negedge clk); req=1; we=1; addr=12'h100; wdata=9; wstrb=1;
        #1;
        check(!ready && !err, "feature busy write phai stall");
        timeout = 0;
        while (busy && timeout < 4000) begin
            check(!ready && !err && dut.feature_mem[0] == 8'sd3,
                  "pending write khong duoc success hoac thay snapshot");
            @(negedge clk); #1;
            timeout = timeout + 1;
        end
        check(done && !busy && timeout < 4000,
              "accelerator phai ket thuc truoc timeout");
        check(result_value == 32'd84, "ket qua QNN phai bang 84");
        check(ready && !err, "feature write duoc nhan sau busy");
        @(negedge clk); req=0; we=0;
        check(dut.feature_mem[0] == 8'sd9, "successful feature write phai cap nhat memory");
        check(dut.cycle_count_q == 32'd2849,
              "latency phai gom fetch/MAC dong bo va chu ky store/done");
        mmio_read_check(12'h008, 32'hFFFF_FFFF, 32'd84);
        mmio_write(12'h000, 32'd2);
        check(!done, "lenh clear phai xoa done");

        @(negedge clk);
        req = 1'b1;
        we = 1'b0;
        addr = 12'h014;
        #1;
        check(ready && err, "dia chi thanh ghi khong hop le phai bao err");
        req = 1'b0;

        $display("PASS tb_rv32_qnn_soc_accelerator: %0d checks", checks);
        $finish;
    end

endmodule

`default_nettype wire
