`timescale 1ns/1ps
`default_nettype none
`include "qnn_model_config.vh"

// =============================================================================
// Testbench : tb_rv32_qnn_model
// Mục tiêu  : Kiểm tra bit-exact model CALCE đã cài với chính các file HEX mà
//             accelerator dùng, thay vì ghi đè model bằng hierarchical access.
//
// Nguyên tắc:
//   1. Nạp 80 feature INT8 sinh từ một cửa sổ BJDST chưa dùng khi huấn luyện.
//   2. Start qua MMIO và chờ done với timeout hữu hạn.
//   3. So sánh RESULT với reference Python dùng cùng quy tắc INT8/INT32/shift.
//   4. Kiểm tra latency 2849 chu kỳ để phát hiện sai lệch FSM/ROM đồng bộ.
//
// Đường dẫn tương đối được tính từ sim/modelsim/work, là working directory của
// scripts/run_tests.ps1. Test này xác minh cả thứ tự flatten neuron-major và
// tính nhất quán giữa qnn_model_config.vh với các trọng số đã xuất.
// =============================================================================
module tb_rv32_qnn_model;

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

    reg [7:0] feature_vector [0:79];
    reg [31:0] expected_result [0:0];
    integer index;
    integer timeout;
    integer checks;

    qnn_soc_accelerator #(
        .USE_INIT_FILES(1),
        .L1_SHIFT(`QNN_MODEL_L1_SHIFT),
        .L2_SHIFT(`QNN_MODEL_L2_SHIFT),
        .OUT_SHIFT(`QNN_MODEL_OUT_SHIFT),
        .L1_WEIGHT_FILE("../../../firmware/model/l1_weights.hex"),
        .L1_BIAS_FILE("../../../firmware/model/l1_biases.hex"),
        .L2_WEIGHT_FILE("../../../firmware/model/l2_weights.hex"),
        .L2_BIAS_FILE("../../../firmware/model/l2_biases.hex"),
        .OUT_WEIGHT_FILE("../../../firmware/model/out_weights.hex"),
        .OUT_BIAS_FILE("../../../firmware/model/out_bias.hex")
    ) dut (
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
                $display("FAIL tb_rv32_qnn_model: %0s", message);
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
            check(ready && !err, "ghi MMIO model phai duoc chap nhan");
            @(negedge clk);
            req   = 1'b0;
            we    = 1'b0;
            addr  = 12'd0;
            wdata = 32'd0;
            wstrb = 4'd0;
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

        $readmemh("../../../firmware/model/verification_features.hex", feature_vector);
        $readmemh("../../../firmware/model/verification_expected.hex", expected_result);

        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (index = 0; index < 80; index = index + 1)
            mmio_write(12'h100 + index * 4, {24'd0, feature_vector[index]});

        mmio_write(12'h000, 32'd1);
        check(busy && !done, "start phai dua model vao busy");
        timeout = 0;
        while (!done && timeout < 4000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(done && !busy && timeout < 4000, "model phai ket thuc truoc timeout");
        check(result_value == expected_result[0], "RESULT phai bit-exact voi Python reference");
        check(dut.cycle_count_q == 32'd2849, "latency model phai bang 2849 chu ky");

        $display(
            "PASS tb_rv32_qnn_model: %0d checks, model=%h, result=%0d",
            checks, `QNN_MODEL_ID, result_value
        );
        $finish;
    end

endmodule

`default_nettype wire

