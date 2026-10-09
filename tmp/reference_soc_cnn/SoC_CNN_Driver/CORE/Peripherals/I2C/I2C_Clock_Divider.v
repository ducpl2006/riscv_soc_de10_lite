// ============================================================================
// Module I2C_Clock_Divider
// ----------------------------------------------------------------------------
// Sinh nhịp thời gian cho I2C theo mô hình 4 pha (mục E của plan_i2c.md).
//
//   System Clock
//        |
//        v
//   Prescaler (down-counter)  -> prescale_zero mỗi (prescale+1) chu kỳ clk
//        |
//        v
//   Tick Generator (÷4)       -> 4 pha: A, B, C, D
//        |
//        v
//   Bit_Controller (dùng pha để canh cạnh SCL & sample SDA)
//
// Công thức:
//   f_SCL = f_sys / (4 × (prescale + 1))
//
// 4 pha mỗi bit:
//   A : SCL low, đổi SDA (data setup)
//   B : SCL rise (thả scl_oe) -> điểm kiểm tra clock stretching
//   C : SCL high, sample SDA (data valid) + kiểm tra arbitration
//   D : SCL fall
//
// Clock stretching:
//   Khi ở pha B mà slave còn giữ SCL low, Bit_Controller kéo `pause` = 1.
//   Clock_Divider ĐÓNG BĂNG toàn bộ (prescaler + phase) -> giữ nguyên pha,
//   không phát tick, cho tới khi `pause` hạ.
//
// Reset: active-low (theo convention project: if(!reset)).
// ============================================================================
module I2C_Clock_Divider #(

    parameter PRESCALE_WIDTH = 16
)
(
    input                           clk,
    input                           reset,      // active-low

    // Điều khiển
    input                           enable,     // CTRL.EN — chỉ chạy khi core bật
    input                           pause,      // clock stretching: đóng băng nhịp
    input [PRESCALE_WIDTH - 1:0]    prescale,   // hệ số chia (PRESCALE register)

    // Nhịp ra
    output [1:0]                    phase,      // 0=A, 1=B, 2=C, 3=D (pha hiện tại)
    output                          tick_a,     // strobe 1 cycle khi VÀO pha A
    output                          tick_b,     // strobe 1 cycle khi VÀO pha B
    output                          tick_c,     // strobe 1 cycle khi VÀO pha C
    output                          tick_d      // strobe 1 cycle khi VÀO pha D
);

    // ========================================================================
    // Mã hoá pha
    // ========================================================================
    localparam PHASE_A = 2'd0;
    localparam PHASE_B = 2'd1;
    localparam PHASE_C = 2'd2;
    localparam PHASE_D = 2'd3;

    // ========================================================================
    // Điều kiện chạy nhịp
    // + enable = 0 -> core tắt, giữ idle
    // + pause  = 1 -> clock stretching, đóng băng
    // ========================================================================
    wire run = enable && !pause;

    // ========================================================================
    // PRESCALER — down counter
    // + Đếm từ `prescale` về 0
    // + prescale_zero = 1 xung mỗi (prescale + 1) chu kỳ clk
    // ========================================================================
    reg [PRESCALE_WIDTH - 1:0] presc_cnt;

    wire prescale_zero = (presc_cnt == {PRESCALE_WIDTH{1'b0}});

    always @(posedge clk) begin

        if (!reset) begin
            presc_cnt <= {PRESCALE_WIDTH{1'b0}};
        end

        else if (!run) begin
            // Đóng băng: giữ nguyên bộ đếm (stretching) hoặc reload khi tắt core
            if (!enable)
                presc_cnt <= prescale;      // core tắt -> sẵn sàng cho lần bật sau
            // pause: giữ nguyên presc_cnt (không đụng)
        end

        else if (prescale_zero) begin
            presc_cnt <= prescale;          // reload
        end

        else begin
            presc_cnt <= presc_cnt - 1'b1;  // đếm xuống
        end

    end

    // ========================================================================
    // TICK — 1 xung khi hoàn tất 1 pha (đủ 1 chu kỳ prescaler)
    // ========================================================================
    wire advance = run && prescale_zero;

    // ========================================================================
    // TICK GENERATOR — bộ đếm pha ÷4 + strobe registered
    // + Mỗi `advance` -> chuyển sang pha kế tiếp: A -> B -> C -> D -> A
    // + Strobe registered -> tick_X lên CÙNG chu kỳ phase bước vào pha X
    //   (trùng khít với `phase`, giữ 1 cycle mỗi đầu pha)
    // ========================================================================
    reg [1:0] phase_reg;
    reg       tick_a_r, tick_b_r, tick_c_r, tick_d_r;

    wire [1:0] phase_next = phase_reg + 1'b1;   // 2-bit tự wrap D -> A

    always @(posedge clk) begin

        if (!reset) begin
            phase_reg <= PHASE_A;
            {tick_a_r, tick_b_r, tick_c_r, tick_d_r} <= 4'b0000;
        end

        else if (!enable) begin
            phase_reg <= PHASE_A;               // core tắt -> về pha A
            {tick_a_r, tick_b_r, tick_c_r, tick_d_r} <= 4'b0000;
        end

        else begin
            // Mặc định các strobe = 0 (chỉ lên 1 cycle khi vào pha mới)
            tick_a_r <= 1'b0;
            tick_b_r <= 1'b0;
            tick_c_r <= 1'b0;
            tick_d_r <= 1'b0;

            if (advance) begin
                phase_reg <= phase_next;
                case (phase_next)
                    PHASE_A: tick_a_r <= 1'b1;
                    PHASE_B: tick_b_r <= 1'b1;
                    PHASE_C: tick_c_r <= 1'b1;
                    PHASE_D: tick_d_r <= 1'b1;
                endcase
            end
        end

    end

    assign phase  = phase_reg;
    assign tick_a = tick_a_r;
    assign tick_b = tick_b_r;
    assign tick_c = tick_c_r;
    assign tick_d = tick_d_r;

endmodule
