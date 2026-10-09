// ==========================================================
// Module UART_Tx
// + Bộ Tx của UART
// + Gửi tín hiệu từ kit DE10 tới máy tính qua CP2102 TTL
// + Thiết kế theo FSM
// ==========================================================

module UART_Tx #(

    parameter DATA_BITS     = 8,    // Số bit dữ liệu mà Tx gửi đi trong 1 farme
    parameter OVERSAMPLE    = 8
)
(

    input clk,
    input reset,
    input baud_tick,
    input [DATA_BITS - 1:0] data_in,       // Dữ liệu cần gửi đi
    input i_send,                          // Enable cho phép gửi tín hiệu đi

    output reg tx,                         // Đường truyền dữ liệu ra ngoài (truyền 1 bit 1 lần)
    output tx_ready                        // Cờ báo Tx sẵn sàng nhận dữ liệu mới để truyền
);

    // =============== STATE FSM ===============
    localparam IDLE     = 0;
    localparam START    = 1;
    localparam DATA     = 2;
    localparam STOP     = 3;

    reg [1:0] state;                            // Trạng thái hiện tại của thanh ghi
    reg [$clog2(DATA_BITS) - 1:0] bit_cnt;      // Thanh ghi đếm số bit đã truyền đi
    reg [DATA_BITS - 1:0] shift;                // Thanh ghi trung gian cho data_in
    reg [$clog2(OVERSAMPLE) - 1:0] tick_cnt;    // Thanh ghi đếm số lần lấy mẫu bit

    // =============== READY TX ===============
    assign tx_ready = (state == IDLE) & ~i_send;

    always @(posedge clk) begin
        
        if (!reset) begin
            state       <= IDLE;
            tick_cnt    <= 0;
            bit_cnt     <= 0;
            shift       <= 0;
            tx          <= 1'b1;            // Đầu ra Tx luôn ở mức cao khi ở trạng thái IDLE 
        end

        // =============== FSM ===============
        else begin
            case (state)

            // =============== IDLE ===============
            IDLE:
            begin
                tx          <= 1'b1;
                tick_cnt    <= 0;

                if (i_send && state == IDLE) begin
                    shift   <= data_in;
                    bit_cnt <= 0;
                    state   <= START;
                end 
            end


            // =============== START ===============
            START:
            begin
                tx  <= 1'b0;

                if (baud_tick) begin
                    if (tick_cnt == OVERSAMPLE - 1) begin
                        tick_cnt    <= 0;
                        state       <= DATA;
                    end

                    else begin
                        tick_cnt    <= tick_cnt + 1;
                    end 
                end
            end 


            // =============== DATA ===============
            DATA:
            begin
                if (baud_tick) begin
                    if (tick_cnt == 0) begin
                        tx  <= shift[0];
                    end

                    if (tick_cnt == OVERSAMPLE - 1) begin
                        shift       <= shift >> 1;
                        tick_cnt    <= 0;

                        if (bit_cnt == DATA_BITS - 1) begin
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
                tx  <= 1'b1;

                if (baud_tick) begin    
                    if (tick_cnt == OVERSAMPLE - 1) begin
                        tick_cnt    <= 0;
                        state       <= IDLE;
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