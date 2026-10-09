// ============================================================================
// Module I2C_Bus_Recovery
// ----------------------------------------------------------------------------
// FSM khôi phục bus (mục I của plan, NXP UM10204 §3.1.16). Khi slave treo giữ
// SDA=0, phát tối đa 9 xung SCL để slave "xả" nốt byte, kiểm tra SDA sau mỗi
// xung; khi SDA nhả -> phát STOP đưa bus về IDLE. Hết 9 xung vẫn stuck -> lỗi.
//
// Dùng 4 pha của I2C_Clock_Divider để canh nhịp SCL (tick_a=đáy, tick_c=đỉnh).
// Khi chạy (recovery_active=1) khối này CHIẾM line qua mux trong SCL/SDA_Ctrl.
//
//   IDLE ─trigger─▶ CHK
//   CHK   : sda_in=1 -> DONE (bus sạch); sda_in=0 -> PULL_LOW (pulse_cnt=9)
//   PULL_LOW @tick_a : SCL low
//   REL_HIGH @tick_c : SCL high
//   SAMPLE   @tick_a : SCL đã cao 1 xung -> đọc sda_in
//        sda_in=1 -> ST1 (phát STOP)
//        sda_in=0 & pulse_cnt=1 -> FAIL
//        sda_in=0 -> pulse_cnt--, SCL low, REL_HIGH (xung kế)
//   ST1 @tick_a : SCL low, SDA low
//   ST2 @tick_c : SCL high (SDA vẫn low)
//   ST3 @tick_a : SDA high (SCL cao) -> STOP -> DONE
//   FAIL : sda_stuck=1 -> IDLE
//   DONE : done=1 -> IDLE
//
// Reset: active-low.
// ============================================================================
module I2C_Bus_Recovery (
    input           clk,
    input           reset,          // active-low
    input           core_en,
    input           trigger,        // kích khôi phục (COMMAND.BUS_RECOVER / auto)

    // 4 pha từ Clock_Divider
    input           tick_a,
    input           tick_c,

    // line đã lọc
    input           sda_in,

    // drive line (mux qua recovery_active trong SCL/SDA_Controller)
    output          rec_scl_oe,
    output          rec_sda_oe,
    output          recovery_active,

    // kết quả (pulse)
    output          done,
    output          sda_stuck
);

    localparam S_IDLE = 4'd0;
    localparam S_CHK  = 4'd1;
    localparam S_PLOW = 4'd2;
    localparam S_RHI  = 4'd3;
    localparam S_SMPL = 4'd4;
    localparam S_ST1  = 4'd5;
    localparam S_ST2  = 4'd6;
    localparam S_ST3  = 4'd7;
    localparam S_FAIL = 4'd8;
    localparam S_DONE = 4'd9;

    reg [3:0]   state;
    reg [3:0]   pulse_cnt;
    reg         scl_oe_r;
    reg         sda_oe_r;
    reg         done_r;
    reg         stuck_r;

    always @(posedge clk) begin

        if (!reset) begin
            state     <= S_IDLE;
            pulse_cnt <= 4'd0;
            scl_oe_r  <= 1'b0;
            sda_oe_r  <= 1'b0;
            done_r    <= 1'b0;
            stuck_r   <= 1'b0;
        end

        else if (!core_en) begin
            state    <= S_IDLE;
            scl_oe_r <= 1'b0;
            sda_oe_r <= 1'b0;
            done_r   <= 1'b0;
            stuck_r  <= 1'b0;
        end

        else begin
            done_r  <= 1'b0;
            stuck_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    scl_oe_r <= 1'b0;
                    sda_oe_r <= 1'b0;
                    if (trigger) state <= S_CHK;
                end

                S_CHK: begin
                    if (sda_in) state <= S_DONE;       // bus đã sạch
                    else begin
                        pulse_cnt <= 4'd9;
                        state     <= S_PLOW;
                    end
                end

                S_PLOW: if (tick_a) begin scl_oe_r <= 1'b1; state <= S_RHI; end   // SCL low

                S_RHI:  if (tick_c) begin scl_oe_r <= 1'b0; state <= S_SMPL; end  // SCL high

                S_SMPL: if (tick_a) begin
                    if (sda_in)
                        state <= S_ST1;                // slave đã nhả -> STOP
                    else if (pulse_cnt == 4'd1)
                        state <= S_FAIL;               // hết 9 xung vẫn stuck
                    else begin
                        pulse_cnt <= pulse_cnt - 4'd1;
                        scl_oe_r  <= 1'b1;             // pull low cho xung kế
                        state     <= S_RHI;
                    end
                end

                S_ST1: if (tick_a) begin scl_oe_r <= 1'b1; sda_oe_r <= 1'b1; state <= S_ST2; end // SCL low, SDA low
                S_ST2: if (tick_c) begin scl_oe_r <= 1'b0;                  state <= S_ST3; end // SCL high
                S_ST3: if (tick_a) begin sda_oe_r <= 1'b0;                  state <= S_DONE; end // SDA high -> STOP

                S_FAIL: begin
                    stuck_r  <= 1'b1;
                    scl_oe_r <= 1'b0;
                    sda_oe_r <= 1'b0;
                    state    <= S_IDLE;
                end

                S_DONE: begin
                    done_r   <= 1'b1;
                    scl_oe_r <= 1'b0;
                    sda_oe_r <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign rec_scl_oe      = scl_oe_r;
    assign rec_sda_oe      = sda_oe_r;
    assign recovery_active = (state != S_IDLE);
    assign done            = done_r;
    assign sda_stuck       = stuck_r;

endmodule
