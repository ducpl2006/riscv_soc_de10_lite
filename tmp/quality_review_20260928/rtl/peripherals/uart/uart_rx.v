`default_nettype none
// Module: uart_rx
// Purpose: nhận UART 8N1, đồng bộ hai FF và lấy mẫu giữa bit bằng clock hệ thống.
// Clock: clk_i. Reset: rst_i synchronous active-high, bỏ frame đang nhận.
// Inputs: rx_i bất đồng bộ, CLOCK_HZ/BAUD xác định chu kỳ bit làm tròn gần nhất.
// Outputs: data_o cùng valid_o một clock; framing_error_o/false_start_o là xung.
// Protocol: byte hợp lệ chỉ phát sau kiểm tra stop=1; không có backpressure dây RX.
// Latency: nhận start ở giữa bit, 8 data bit LSB-first rồi lấy mẫu giữa stop.
// Error behavior: loại frame lỗi, chờ line cao sau break; tham số cần >=8 clock/bit.
module uart_rx #(
    parameter integer CLOCK_HZ=50000000,
    parameter integer BAUD=115200
) (
    input wire clk_i,
    input wire rst_i,
    input wire rx_i,
    output reg [7:0] data_o,
    output reg valid_o,
    output reg framing_error_o,
    output reg false_start_o
);
    localparam integer BIT_CYCLES=(BAUD>0)?(CLOCK_HZ+BAUD/2)/BAUD:1;
    localparam integer COUNT_WIDTH=(BIT_CYCLES>1)?$clog2(BIT_CYCLES):1;
    localparam integer BIT_RELOAD=BIT_CYCLES-1;
    localparam integer HALF_RELOAD=BIT_CYCLES/2-1;
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4;
    // rx_meta_q là FF duy nhất nhận pad; SDC chỉ false-path tới FF này.
    (* preserve *) reg rx_meta_q, rx_sync_q;
    reg rx_previous_q;
    reg [2:0] state_q, bit_q;
    reg [COUNT_WIDTH-1:0] count_q;
    reg [7:0] shift_q;
    always @(posedge clk_i) begin
        if (rst_i) begin
            rx_meta_q<=1; rx_sync_q<=1; rx_previous_q<=1;
            state_q<=IDLE; bit_q<=0; count_q<=0; shift_q<=0;
            data_o<=0; valid_o<=0; framing_error_o<=0; false_start_o<=0;
        end
        else begin
            rx_meta_q<=rx_i; rx_sync_q<=rx_meta_q; rx_previous_q<=rx_sync_q;
            valid_o<=0; framing_error_o<=0; false_start_o<=0;
            case (state_q)
                IDLE: if (rx_previous_q && !rx_sync_q) begin
                    count_q<=HALF_RELOAD[COUNT_WIDTH-1:0]; state_q<=START;
                end
                START: if (count_q!=0) count_q<=count_q-1'b1;
                    else if (rx_sync_q) begin false_start_o<=1; state_q<=IDLE; end
                    else begin count_q<=BIT_RELOAD[COUNT_WIDTH-1:0]; bit_q<=0; state_q<=DATA; end
                DATA: if (count_q!=0) count_q<=count_q-1'b1;
                    else begin
                        shift_q[bit_q]<=rx_sync_q;
                        count_q<=BIT_RELOAD[COUNT_WIDTH-1:0];
                        if (bit_q==7) state_q<=STOP;
                        else bit_q<=bit_q+1'b1;
                    end
                STOP: if (count_q!=0) count_q<=count_q-1'b1;
                    else if (rx_sync_q) begin data_o<=shift_q; valid_o<=1; state_q<=IDLE; end
                    else begin framing_error_o<=1; state_q<=WAIT_HIGH; end
                WAIT_HIGH: if (rx_sync_q) state_q<=IDLE;
                default: state_q<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial if (CLOCK_HZ<=0 || BAUD<=0 || BIT_CYCLES<8)
        $fatal(1,"uart_rx requires at least 8 system clocks per bit");
    // synthesis translate_on
endmodule
`default_nettype wire
