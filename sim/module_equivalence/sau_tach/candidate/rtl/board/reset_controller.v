`default_nettype none
// Module: reset_controller
// Purpose: POR sau cấu hình FPGA và đồng bộ nhả reset nút KEY.
// Clock: clk_i. Reset: KEY active-low; POR tự khởi động nhờ power-up FF MAX10.
// Inputs: clk_i, key_reset_n_i bất đồng bộ. Outputs: rst_o active-high.
// Protocol: không có bus; KEY assert bất đồng bộ, release qua SYNC_STAGES FF.
// Latency: POR_CYCLES cạnh giữ POR, thêm SYNC_STAGES cạnh trước nhả rst_o.
// Error behavior: tham số sai bị báo trong mô phỏng; POR_CYCLES>=1, SYNC_STAGES>=2.
module reset_controller #(
    parameter integer POR_CYCLES = 1024,
    parameter integer SYNC_STAGES = 3
) (
    input wire clk_i,
    input wire key_reset_n_i,
    output wire rst_o
);
    localparam integer COUNT_WIDTH = (POR_CYCLES>1) ? $clog2(POR_CYCLES) : 1;
    // Giá trị khai báo được Quartus ánh xạ thành power-up level sau configuration.
    // Chỉ mạch POR có phụ thuộc này; các state SoC được reset bằng rst_o.
    reg [COUNT_WIDTH-1:0] count_q = {COUNT_WIDTH{1'b0}};
    reg por_q = 1'b1;
    (* preserve *) reg [SYNC_STAGES-1:0] sync_q = {SYNC_STAGES{1'b1}};
    wire reset_async = por_q || !key_reset_n_i;
    assign rst_o = sync_q[SYNC_STAGES-1];
    always @(posedge clk_i) begin
        if (por_q) begin
            if (count_q == POR_CYCLES-1) por_q <= 1'b0;
            else count_q <= count_q + 1'b1;
        end
    end
    always @(posedge clk_i or posedge reset_async) begin
        if (reset_async) sync_q <= {SYNC_STAGES{1'b1}};
        else sync_q <= {sync_q[SYNC_STAGES-2:0],1'b0};
    end
    // synthesis translate_off
    initial begin
        if (POR_CYCLES<1 || SYNC_STAGES<2) $fatal(1,"reset_controller: invalid parameters");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
