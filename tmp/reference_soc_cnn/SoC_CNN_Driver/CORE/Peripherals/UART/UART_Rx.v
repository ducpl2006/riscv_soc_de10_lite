// =============================================================
// Module UART_RX
// + Bộ Rx của UART
// + Nhận tín hiệu từ máy tính từ máy tính về kit qua CP2102
// + Thiết kế theo FSM
// =============================================================

module UART_Rx #(

    parameter DATA_BITS     = 8,
    parameter OVERSAMPLE    = 16
)
(

    input clk,
    input reset,
    input baud_tick,
    input rx,                    // Chân Rx nhận tín hiệu vào kit (Nhận lần lượt từng bit)

    output reg [DATA_BITS - 1:0] data_out,
    output reg rx_valid                     // Cờ báo đã nhận xong một farme dữ liệu
);

    // =============== STATE FSM ===============
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] START    = 2'b01;
    localparam [1:0] DATA     = 2'b10;
    localparam [1:0] STOP     = 2'b11;

    reg [1:0] state;            // Trạng thái hiện tại của FSM

    reg [$clog2(OVERSAMPLE) - 1:0] tick_cnt;
    reg [$clog2(DATA_BITS) - 1:0] bit_cnt;
    reg [DATA_BITS - 1:0] shift;

    // Đồng bộ tín hiệu Rx nhận vào
    reg rx_d1;
    reg rx_d2;

    // =============== ĐỒNG BỘ RX NHẬN VÀO ===============
    always @(posedge clk) begin
        
        if (!reset) begin
            rx_d1   <= 1'b1;
            rx_d2   <= 1'b1;
        end

        else begin
            rx_d1   <= rx;
            rx_d2   <= rx_d1;
        end

    end

    reg rx_prev;
    always @(posedge clk) begin
        
        if (!reset) begin
            rx_prev     <= 1'b1;
        end

        else begin
            rx_prev     <= rx_d2;
        end

    end


    // =============== FSM ===============
    always @(posedge clk) begin
        
        if (!reset) begin
            state       <= IDLE;
            tick_cnt    <= 0;
            bit_cnt     <= 0;
            shift       <= 0;
            data_out    <= 0;
            rx_valid    <= 0;
        end 
        
        // =============== FSM ===============
        else begin
            rx_valid    <= 1'b0;

            case (state) 

                // =============== IDLE ===============
                IDLE:
                begin
                    tick_cnt    <= 0;
                    bit_cnt     <= 0;

                    if (rx_prev == 1'b1 && rx_d2 == 1'b0) begin
                        state   <= START;       // Rx nhận được tín hiệu bit START
                    end
                end


                // =============== START ===============
                START:
                begin
                    if (baud_tick) begin
                        if (tick_cnt == (OVERSAMPLE/2 - 1)) begin
                            if (rx_d2 == 1'b0) begin
                                tick_cnt    <= 0;
                                bit_cnt     <= 0;
                                state       <= DATA;
                            end
                            else begin
                                state       <= IDLE;
                            end
                        end

                        else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end


                // =============== DATA ===============
                DATA:
                begin
                    if (baud_tick) begin
                        if (tick_cnt == OVERSAMPLE - 1) begin
                            tick_cnt    <= 0;
                            shift       <= {rx_d2, shift[DATA_BITS - 1:1]};

                            if (bit_cnt == DATA_BITS - 1) begin
                                bit_cnt <= 0;
                                state   <= STOP;
                            end
                            else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end

                        else begin
                            tick_cnt    <= tick_cnt + 1;
                        end
                    end
                end


                // =============== STOP ===============
                STOP:
                begin
                    if (baud_tick) begin
                        if (tick_cnt == OVERSAMPLE - 1) begin
                            tick_cnt    <= 0;

                            if (rx_d2 == 1) begin
                                data_out    <= shift;
                                rx_valid    <= 1'b1;
                                state       <= IDLE;
                            end
                        end

                        else begin
                            tick_cnt    <= tick_cnt + 1;
                        end
                    end
                end


                // =============== DEFAULT ===============
                default: state  <= IDLE;

            endcase
        end

    end

endmodule