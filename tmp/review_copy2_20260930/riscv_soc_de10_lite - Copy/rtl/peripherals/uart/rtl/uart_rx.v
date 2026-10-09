`default_nettype none
`timescale 1ns/1ps

// ============================================================================
// Module    : uart_rx
// Chức năng : Nhận một byte theo chuẩn UART 8N1.
//
// ĐẶC TẢ KHUNG VÀ LẤY MẪU:
//   - Nghỉ=1, bắt đầu=0, 8 bit dữ liệu LSB trước, không bit chẵn lẻ, dừng=1.
//   - uart_rx_i được đồng bộ qua hai flip-flop trước khi FSM sử dụng.
//   - OVERSAMPLE >= 4; tốc độ sample phải không vượt CLOCK_FREQ.
//   - Mỗi bit dùng biểu quyết đa số của ba mẫu gần tâm tại các chỉ số
//     OVERSAMPLE/2-2, OVERSAMPLE/2-1 và OVERSAMPLE/2.
//   - Bit bắt đầu có kết quả đa số=1 là khởi đầu giả và bị bỏ.
//
// ĐẶC TẢ READY/VALID VÀ LỖI:
//   - rx_data, framing_error hợp lệ khi rx_valid=1.
//   - Khi rx_valid=1 và rx_ready=0, payload phải được giữ ổn định.
//   - Handshake xảy ra tại cạnh lên khi rx_valid && rx_ready.
//   - Bit dừng có kết quả đa số=0 vẫn xuất byte với framing_error=1.
//   - Sau framing error, FSM chờ RX trở lại mức high rồi mới nhận frame mới;
//     BREAK mức thấp liên tục chỉ tạo một frame lỗi cho mỗi lần trở lại nghỉ.
//   - Nếu frame mới hoàn tất khi slot cũ chưa được đọc, frame mới bị loại và
//     overrun_error phát xung đúng một chu kỳ clk.
//   - Nếu đọc byte cũ đúng cạnh frame mới hoàn tất, byte mới thay thế hợp lệ.
//
// ĐẶC TẢ RESET:
//   - rst_n tích cực thấp; khi reset, rx_valid và các cờ lỗi về 0.
//   - rst_n phải được nhả đồng bộ với clk.
// ============================================================================

module uart_rx #(
    parameter integer CLOCK_FREQ = 50_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    // Chan UART RX bat dong bo.
    input  wire       uart_rx_i,

    // Giao tiep du lieu dau ra.
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    input  wire       rx_ready,

    // Thong tin loi.
    output reg        framing_error,
    output reg        overrun_error
);

    // ------------------------------------------------------------------------
    // Ma hoa trang thai FSM
    // ------------------------------------------------------------------------
    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_START     = 3'd1;
    localparam [2:0] ST_DATA      = 3'd2;
    localparam [2:0] ST_STOP      = 3'd3;
    localparam [2:0] ST_WAIT_IDLE = 3'd4;

    // Giá trị an toàn để mô phỏng báo lỗi tham số rõ ràng, thay vì để module
    // con gặp phép chia cho 0 khi xây dựng thiết kế.
    localparam integer SAMPLE_BAUD_RATE =
        (BAUD_RATE <= 0) ? 1 :
        (OVERSAMPLE <= 0) ? 1 :
        (BAUD_RATE > (CLOCK_FREQ / OVERSAMPLE)) ? 1 :
        (BAUD_RATE * OVERSAMPLE);

`ifndef SYNTHESIS
    // Các ràng buộc này là một phần của giao diện cấu hình module.
    // Kiểm tra được lồng nhau để không đánh giá phép chia cho 0.
    initial begin
        if (CLOCK_FREQ <= 0) begin
            $display("ERROR: uart_rx CLOCK_FREQ must be greater than 0");
            $finish;
        end else if (BAUD_RATE <= 0) begin
            $display("ERROR: uart_rx BAUD_RATE must be greater than 0");
            $finish;
        end else if (OVERSAMPLE < 4) begin
            $display("ERROR: uart_rx OVERSAMPLE must be at least 4");
            $finish;
        end else if (BAUD_RATE > (CLOCK_FREQ / OVERSAMPLE)) begin
            $display(
                "ERROR: uart_rx requires BAUD_RATE * OVERSAMPLE <= CLOCK_FREQ"
            );
            $finish;
        end
    end
`endif

    // ------------------------------------------------------------------------
    // Hàm tính độ rộng bộ đếm.
    // ------------------------------------------------------------------------
    function integer clog2;
        input integer value;
        integer temp;

        begin
            temp  = value - 1;
            clog2 = 0;

            while (temp > 0) begin
                temp  = temp >> 1;
                clog2 = clog2 + 1;
            end
        end
    endfunction

    localparam integer SAMPLE_COUNT_WIDTH =
        (OVERSAMPLE <= 1) ? 1 : clog2(OVERSAMPLE);

    // Ba vi tri lay mau gan trung tam bit.
    localparam integer SAMPLE_A_COUNT =
        (OVERSAMPLE / 2) - 2;

    localparam integer SAMPLE_B_COUNT =
        (OVERSAMPLE / 2) - 1;

    localparam integer SAMPLE_C_COUNT =
        (OVERSAMPLE / 2);

    localparam integer LAST_SAMPLE_COUNT =
        OVERSAMPLE - 1;

    // ------------------------------------------------------------------------
    // Hàm biểu quyết đa số ba mẫu.
    // ------------------------------------------------------------------------
    function majority3;
        input a;
        input b;
        input c;

        begin
            majority3 = (a & b) |
                        (a & c) |
                        (b & c);
        end
    endfunction

    reg [2:0] state;

    reg [SAMPLE_COUNT_WIDTH-1:0] sample_count;
    reg [2:0]                    bit_index;
    reg [7:0]                    data_reg;

    reg sample_a;
    reg sample_b;
    reg stop_sample;

    wire uart_rx_sync;
    wire sample_tick;
    wire sample_enable;
    wire sample_restart;
    wire start_detect;

    // ------------------------------------------------------------------------
    // Đồng bộ uart_rx_i vào miền clock hệ thống.
    // ------------------------------------------------------------------------
    uart_rx_sync u_uart_rx_sync (
        .clk            (clk),
        .rst_n          (rst_n),
        .uart_rx_i      (uart_rx_i),
        .uart_rx_sync_o (uart_rx_sync)
    );

    // ------------------------------------------------------------------------
    // Phat hien bat dau frame
    //
    // Trong IDLE, muc 0 duoc xem la mot START bit tiem nang.
    // START được xác nhận lại bằng biểu quyết đa số tại giữa bit.
    // ------------------------------------------------------------------------
    assign start_detect =
        (state == ST_IDLE) && (uart_rx_sync == 1'b0);

    // Bộ tạo mẫu chỉ hoạt động khi RX đang xử lý một frame.
    // Trong ST_WAIT_IDLE, RX chỉ chờ mức MARK và không cần sample tick.
    assign sample_enable =
        (state == ST_START) ||
        (state == ST_DATA)  ||
        (state == ST_STOP);

    // Dong bo pha lay mau voi thoi diem phat hien START.
    assign sample_restart = start_detect;

    uart_baud_gen #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (SAMPLE_BAUD_RATE)
    ) u_sample_tick_gen (
        .clk     (clk),
        .rst_n   (rst_n),
        .enable  (sample_enable),
        .restart (sample_restart),
        .tick    (sample_tick)
    );

    // ------------------------------------------------------------------------
    // UART RX FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            sample_count   <= {SAMPLE_COUNT_WIDTH{1'b0}};
            bit_index      <= 3'd0;
            data_reg       <= 8'h00;
            sample_a       <= 1'b1;
            sample_b       <= 1'b1;
            stop_sample    <= 1'b1;

            rx_data        <= 8'h00;
            rx_valid       <= 1'b0;
            framing_error  <= 1'b0;
            overrun_error  <= 1'b0;
        end else begin
            // overrun_error là xung sự kiện kéo dài một clock.
            overrun_error <= 1'b0;

            // ------------------------------------------------------------
            // Xu ly handshake du lieu dau ra
            // ------------------------------------------------------------
            if (rx_valid && rx_ready) begin
                rx_valid      <= 1'b0;
                framing_error <= 1'b0;
            end

            case (state)

                // ========================================================
                // IDLE: Cho muc thap bat dau START bit
                // ========================================================
                ST_IDLE: begin
                    sample_count <=
                        {SAMPLE_COUNT_WIDTH{1'b0}};

                    bit_index <= 3'd0;

                    if (start_detect) begin
                        sample_a <= 1'b1;
                        sample_b <= 1'b1;
                        state    <= ST_START;
                    end
                end

                // ========================================================
                // START: Kiem tra START bit tai trung tam
                // ========================================================
                ST_START: begin
                    if (sample_tick) begin

                        if (sample_count == SAMPLE_A_COUNT) begin
                            sample_a <= uart_rx_sync;
                        end

                        if (sample_count == SAMPLE_B_COUNT) begin
                            sample_b <= uart_rx_sync;
                        end

                        if (
                            (sample_count == SAMPLE_C_COUNT) &&
                            (majority3(
                                sample_a,
                                sample_b,
                                uart_rx_sync
                            ) == 1'b1)
                        ) begin
                            // START bit khong hop le. Cac cap nhat ket thuc
                            // bit bên dưới loại trừ nhau để tránh nhiều phép
                            // gán không chặn cùng ghi đè một thanh ghi.
                            state        <= ST_IDLE;
                            sample_count <=
                                {SAMPLE_COUNT_WIDTH{1'b0}};
                            sample_a <= 1'b1;
                            sample_b <= 1'b1;
                        end else if (
                            sample_count == LAST_SAMPLE_COUNT
                        ) begin
                            sample_count <=
                                {SAMPLE_COUNT_WIDTH{1'b0}};

                            bit_index <= 3'd0;
                            sample_a  <= 1'b1;
                            sample_b  <= 1'b1;
                            state     <= ST_DATA;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                // ========================================================
                // DATA: Nhan D0 den D7
                // ========================================================
                ST_DATA: begin
                    if (sample_tick) begin

                        if (sample_count == SAMPLE_A_COUNT) begin
                            sample_a <= uart_rx_sync;
                        end

                        if (sample_count == SAMPLE_B_COUNT) begin
                            sample_b <= uart_rx_sync;
                        end

                        if (sample_count == SAMPLE_C_COUNT) begin
                            data_reg[bit_index] <=
                                majority3(
                                    sample_a,
                                    sample_b,
                                    uart_rx_sync
                                );
                        end

                        if (sample_count == LAST_SAMPLE_COUNT) begin
                            sample_count <=
                                {SAMPLE_COUNT_WIDTH{1'b0}};

                            sample_a <= 1'b1;
                            sample_b <= 1'b1;

                            if (bit_index == 3'd7) begin
                                stop_sample <= 1'b1;
                                state       <= ST_STOP;
                            end else begin
                                bit_index <= bit_index + 3'd1;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                // ========================================================
                // STOP: Kiem tra STOP bit va xuat byte
                // ========================================================
                ST_STOP: begin
                    if (sample_tick) begin

                        if (sample_count == SAMPLE_A_COUNT) begin
                            sample_a <= uart_rx_sync;
                        end

                        if (sample_count == SAMPLE_B_COUNT) begin
                            sample_b <= uart_rx_sync;
                        end

                        if (sample_count == SAMPLE_C_COUNT) begin
                            stop_sample <=
                                majority3(
                                    sample_a,
                                    sample_b,
                                    uart_rx_sync
                                );
                        end

                        if (sample_count == LAST_SAMPLE_COUNT) begin
                            sample_count <=
                                {SAMPLE_COUNT_WIDTH{1'b0}};

                            // Co the ghi byte moi neu:
                            //   - Khong co byte cu dang cho, hoac
                            //   - Byte cu duoc doc tai canh clock nay.
                            if (!rx_valid || rx_ready) begin
                                rx_data       <= data_reg;
                                rx_valid      <= 1'b1;
                                framing_error <= !stop_sample;
                            end else begin
                                // Byte moi bi loai vi byte cu chua duoc doc.
                                overrun_error <= 1'b1;
                            end

                            if (stop_sample) begin
                                state <= ST_IDLE;
                            end else begin
                                // Sau framing error, doi duong RX tro lai
                                // MARK de BREAK keo dai chi tao mot frame loi.
                                state <= ST_WAIT_IDLE;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                // ========================================================
                // WAIT_IDLE: Sau framing error, cho duong RX tro lai MARK
                // ========================================================
                ST_WAIT_IDLE: begin
                    sample_count <=
                        {SAMPLE_COUNT_WIDTH{1'b0}};
                    bit_index   <= 3'd0;
                    sample_a    <= 1'b1;
                    sample_b    <= 1'b1;
                    stop_sample <= 1'b1;

                    if (uart_rx_sync == 1'b1) begin
                        state <= ST_IDLE;
                    end
                end

                // ========================================================
                // Phuc hoi neu FSM roi vao trang thai khong hop le
                // ========================================================
                default: begin
                    state        <= ST_IDLE;
                    sample_count <=
                        {SAMPLE_COUNT_WIDTH{1'b0}};
                    bit_index    <= 3'd0;
                    data_reg     <= 8'h00;
                    sample_a     <= 1'b1;
                    sample_b     <= 1'b1;
                    stop_sample  <= 1'b1;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
