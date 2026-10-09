`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Bus_Recovery
// Bus_Recovery + Clock_Divider + SCL/SDA_Controller + Input_Filter + stuck-slave.
// Case 1: slave nhả SDA sau 3 xung SCL -> recovery phát STOP, done=1.
// Case 2: slave giữ SDA low mãi -> sau 9 xung -> sda_stuck=1.
// ============================================================================
module tb_I2C_Bus_Recovery;

    reg         clk = 0;
    reg         reset;
    reg         core_en;
    reg         trigger;

    wire        tick_a, tick_b, tick_c, tick_d;
    wire [1:0]  phase;
    wire        rec_scl_oe, rec_sda_oe, recovery_active, done, sda_stuck;
    wire        scl_in, sda_in;
    wire        scl_pad, sda_pad, scl_raw, sda_raw;

    integer errors = 0;
    reg     done_seen, stuck_seen;

    always #5 clk = ~clk;

    // ---- stuck slave ----
    reg      sda_hold;
    integer  rel_after;      // số xung SCL trước khi nhả (999 = không nhả)
    integer  scl_cnt;
    pullup(scl_pad); pullup(sda_pad);
    assign sda_pad = sda_hold ? 1'b0 : 1'bz;
    always @(posedge scl_in) begin
        if (sda_hold) begin
            scl_cnt = scl_cnt + 1;
            if (scl_cnt >= rel_after) sda_hold <= 1'b0;
        end
    end

    // ---- DUT ----
    I2C_Clock_Divider #(.PRESCALE_WIDTH(16)) u_div (
        .clk(clk), .reset(reset), .enable(core_en), .pause(1'b0), .prescale(16'd3),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d));

    I2C_Bus_Recovery u_rec (
        .clk(clk), .reset(reset), .core_en(core_en), .trigger(trigger),
        .tick_a(tick_a), .tick_c(tick_c), .sda_in(sda_in),
        .rec_scl_oe(rec_scl_oe), .rec_sda_oe(rec_sda_oe), .recovery_active(recovery_active),
        .done(done), .sda_stuck(sda_stuck));

    I2C_SCL_Controller u_scl (.bit_scl_oe(1'b0), .rec_scl_oe(rec_scl_oe),
        .recovery_active(recovery_active), .scl_pad(scl_pad), .scl_in_raw(scl_raw));
    I2C_SDA_Controller u_sda (.bit_sda_oe(1'b0), .rec_sda_oe(rec_sda_oe),
        .recovery_active(recovery_active), .sda_pad(sda_pad), .sda_in_raw(sda_raw));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_scl (.clk(clk), .reset(reset), .line_async(scl_raw), .line_clean(scl_in));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_sda (.clk(clk), .reset(reset), .line_async(sda_raw), .line_clean(sda_in));

    always @(posedge clk) begin
        if (done)      done_seen  <= 1'b1;
        if (sda_stuck) stuck_seen <= 1'b1;
    end

    task do_trigger; begin
        @(negedge clk); trigger=1; @(negedge clk); trigger=0;
    end endtask

    initial begin
        reset=0; core_en=0; trigger=0; sda_hold=0; rel_after=3; scl_cnt=0;
        done_seen=0; stuck_seen=0;
        #23 reset=1; @(negedge clk) core_en=1; repeat(4) @(negedge clk);

        // ===== Case 1: SDA stuck, nhả sau 3 xung =====
        sda_hold=1; scl_cnt=0; rel_after=3;
        done_seen=0; stuck_seen=0;
        repeat(4) @(negedge clk);   // để sda_in ổn định = 0 trước khi kích
        do_trigger;
        // chờ recovery xong
        repeat(400) @(posedge clk);
        if (!done_seen)  begin $display("  [ERR] case1: khong co done"); errors=errors+1; end
        if (stuck_seen)  begin $display("  [ERR] case1: bao stuck sai"); errors=errors+1; end
        if (sda_in!==1'b1) begin $display("  [ERR] case1: SDA chua nha (sda_in=%b)", sda_in); errors=errors+1; end
        if (recovery_active!==1'b0) begin $display("  [ERR] case1: recovery chua ve IDLE"); errors=errors+1; end

        repeat(10) @(posedge clk);

        // ===== Case 2: SDA stuck mãi =====
        sda_hold=1; scl_cnt=0; rel_after=999;
        done_seen=0; stuck_seen=0;
        repeat(4) @(negedge clk);   // để sda_in ổn định = 0 trước khi kích
        do_trigger;
        repeat(600) @(posedge clk);
        if (!stuck_seen) begin $display("  [ERR] case2: khong bao sda_stuck"); errors=errors+1; end
        if (done_seen)   begin $display("  [ERR] case2: bao done sai"); errors=errors+1; end
        sda_hold=0;

        if (errors==0) $display("PASS: I2C_Bus_Recovery");
        else           $display("FAIL: I2C_Bus_Recovery (%0d errors)", errors);
        $finish;
    end

    initial begin #1000000; $display("FAIL: I2C_Bus_Recovery (timeout)"); $finish; end

endmodule
