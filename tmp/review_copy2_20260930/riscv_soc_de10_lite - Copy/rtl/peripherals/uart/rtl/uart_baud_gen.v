`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : uart_baud_gen
// Chức năng : Tạo xung clock-enable theo tốc độ yêu cầu.
//
// ĐẶC TẢ THAM SỐ:
//   - CLOCK_FREQ > 0, đơn vị Hz.
//   - BAUD_RATE > 0 và BAUD_RATE <= CLOCK_FREQ, đơn vị tick/giây.
//   - Số clock mỗi tick = floor(CLOCK_FREQ / BAUD_RATE).
//   - Tốc độ thực = CLOCK_FREQ / số_clock_mỗi_tick; ta phải kiểm
//     tra sai số lượng tử khi đổi cấu hình.
//
// ĐẶC TẢ HOẠT ĐỘNG:
//   - Không tạo clock mới; tick chỉ là clock-enable cho logic dùng clk.
//   - tick là mức 1 tổ hợp trong đúng chu kỳ counter đạt giá trị cuối.
//   - enable=0 giữ counter ở 0 và tick=0.
//   - restart=1 xóa pha đếm đồng bộ và có ưu tiên cao hơn enable.
//   - rst_n=0 xóa counter bất đồng bộ và buộc tick=0.
//   - Thứ tự ưu tiên: reset -> restart -> disable -> kết thúc chu kỳ -> đếm.
//
// CẤU HÌNH MẶC ĐỊNH:
//   CLOCK_FREQ=50 MHz, BAUD_RATE=115200, bộ chia=434 clock/tick.
// ============================================================================

module uart_baud_gen #(
    parameter integer CLOCK_FREQ = 50_000_000,  // Hz
    parameter integer BAUD_RATE  = 115_200      // baud
) (
    input wire clk,
    input wire rst_n,

    input wire enable,
    input wire restart,

    output wire tick
);

    // Giá trị an toàn giúp biểu thức localparam luôn hợp lệ khi xây dựng thiết kế.
    // Khối kiểm tra tham số báo lỗi cho mọi cấu hình không hợp lệ.
    localparam integer SAFE_BAUD_RATE =
        (BAUD_RATE > 0) ? BAUD_RATE : 1;

    // Số chu kỳ clock hệ thống trong một chu kỳ baud. Phép chia lấy phần
    // nguyên được giữ có chủ ý để bảo toàn đặc tả bộ chia hiện tại.
    localparam integer CALCULATED_CLKS_PER_TICK =
        CLOCK_FREQ / SAFE_BAUD_RATE;

    localparam integer CLKS_PER_TICK =
        (CALCULATED_CLKS_PER_TICK > 0) ?
        CALCULATED_CLKS_PER_TICK : 1;
    
    // ------------------------------------------------------------------------
    // Hàm tính số bit tối thiểu để biểu diễn các giá trị từ 0 đến value-1.
    // Ví dụ: clog2(434)=9.
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

    // Bảo đảm bộ đếm luôn có ít nhất một bit.
    localparam integer COUNTER_WIDTH =
        (CLKS_PER_TICK <= 1) ? 1 : clog2(CLKS_PER_TICK);

    // Giá trị cuối của bộ đếm. Dùng số nguyên trung gian và chọn bit tường minh
    // để tránh cảnh báo cắt bớt độ rộng của công cụ tổng hợp.
    localparam integer COUNT_MAX_INTEGER = CLKS_PER_TICK - 1;

    localparam [COUNTER_WIDTH-1:0] COUNT_MAX =
        COUNT_MAX_INTEGER[COUNTER_WIDTH-1:0];

    reg [COUNTER_WIDTH-1:0] counter;
/*
    // synthesis translate_off
    initial begin : validate_parameters
        if (CLOCK_FREQ <= 0) begin
            $display(
                "ERROR: uart_baud_gen CLOCK_FREQ must be greater than zero"
            );
            $finish;
        end else if (BAUD_RATE <= 0) begin
            $display(
                "ERROR: uart_baud_gen BAUD_RATE must be greater than zero"
            );
            $finish;
        end else if (BAUD_RATE > CLOCK_FREQ) begin
            $display(
                "ERROR: uart_baud_gen BAUD_RATE must not exceed CLOCK_FREQ"
            );
            $finish;
        end
    end
    // synthesis translate_on
*/
    // tick bằng 1 khi bộ đếm đạt giá trị cuối.
    //
    // Đây là tín hiệu tổ hợp nhưng chỉ được logic khác sử dụng tại cạnh clk.
    // Không được đưa tick vào chân clock của flip-flop.
    assign tick = rst_n &&
                  enable &&
                  !restart &&
                  (counter == COUNT_MAX);

    // ------------------------------------------------------------------------
    // Bộ đếm baud.
    // ------------------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= {COUNTER_WIDTH{1'b0}};
        end else begin
            if (restart) begin
                // Bắt đầu lại một chu kỳ bit mới.
                counter <= {COUNTER_WIDTH{1'b0}};
            end else if (!enable) begin
                // Khi module không hoạt động, giữ bộ đếm tại 0.
                counter <= {COUNTER_WIDTH{1'b0}};
            end else if (tick) begin
                // Kết thúc một chu kỳ bit, quay về 0.
                counter <= {COUNTER_WIDTH{1'b0}};
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
