`default_nettype none
// Module: uart_rx_fifo
// Purpose: hàng đợi byte nhận; drop byte mới nhất khi đầy và không có pop cùng cạnh.
// Clock: clk_i. Reset: rst_i synchronous active-high, xóa occupancy/con trỏ.
// Inputs: push_i/data_i từ RX, pop_i từ successful MMIO read.
// Outputs: data_o là head khi !empty_o; full/empty, overrun_o một clock khi drop.
// Protocol: push+pop đồng thời giữ count; pop rỗng không tác động.
// Latency: head đọc tổ hợp; push/pop chốt tại cạnh lên.
// Error behavior: overflow báo overrun_o, bảo toàn byte cũ. DEPTH>=1, không cần 2^n.
module uart_rx_fifo #(parameter integer DEPTH=16) (
    input wire clk_i, input wire rst_i,
    input wire push_i, input wire [7:0] data_i, input wire pop_i,
    output wire [7:0] data_o, output wire empty_o, output wire full_o,
    output reg overrun_o
);
    localparam integer PTR_WIDTH=(DEPTH>1)?$clog2(DEPTH):1;
    localparam integer COUNT_WIDTH=(DEPTH>1)?$clog2(DEPTH+1):1;
    // FIFO nhỏ đọc head tổ hợp; giữ trong logic để không cần M9K/read-through mux.
    (* ramstyle = "logic" *) reg [7:0] bytes_q [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] read_q, write_q;
    reg [COUNT_WIDTH-1:0] count_q;
    wire pop=pop_i && !empty_o;
    wire push=push_i && (!full_o || pop);
    assign empty_o=(count_q==0);
    assign full_o=(count_q==DEPTH);
    assign data_o=empty_o ? 8'd0 : bytes_q[read_q];
    always @(posedge clk_i) begin
        if (rst_i) begin read_q<=0; write_q<=0; count_q<=0; overrun_o<=0; end
        else begin
            overrun_o<=push_i && !push;
            if (push) begin
                bytes_q[write_q]<=data_i;
                write_q <= (write_q==DEPTH-1) ? {PTR_WIDTH{1'b0}} : write_q+1'b1;
            end
            if (pop) read_q <= (read_q==DEPTH-1) ? {PTR_WIDTH{1'b0}} : read_q+1'b1;
            case ({push,pop})
                2'b10: count_q<=count_q+1'b1;
                2'b01: count_q<=count_q-1'b1;
                default: begin end
            endcase
        end
    end
    // synthesis translate_off
    initial if (DEPTH<1) $fatal(1,"uart_rx_fifo DEPTH must be positive");
    // synthesis translate_on
endmodule
`default_nettype wire
