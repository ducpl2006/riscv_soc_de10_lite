`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Clock_Divider
// Kiểm tra: chuỗi 4 pha A->B->C->D, strobe từng pha, chu kỳ theo prescale,
//           pause (clock stretching) đóng băng, enable=0 giữ pha A.
// ============================================================================
module tb_I2C_Clock_Divider;

    reg         clk = 0;
    reg         reset;
    reg         enable;
    reg         pause;
    reg  [15:0] prescale;

    wire [1:0]  phase;
    wire        tick_a, tick_b, tick_c, tick_d;

    integer     errors = 0;

    I2C_Clock_Divider #(.PRESCALE_WIDTH(16)) dut (
        .clk(clk), .reset(reset),
        .enable(enable), .pause(pause), .prescale(prescale),
        .phase(phase),
        .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d)
    );

    always #5 clk = ~clk;   // 100MHz

    // Đếm số chu kỳ giữa 2 lần đổi pha để kiểm tra period = prescale+1
    // `checking` tắt quanh vùng test pause (freeze làm phép đo bắc cầu sai)
    integer cyc_cnt = 0;
    reg [1:0] phase_prev;
    reg       checking = 0;
    always @(posedge clk) begin
        if (enable && !pause) begin
            cyc_cnt <= cyc_cnt + 1;
            if (phase !== phase_prev) begin
                if (checking && cyc_cnt !== (prescale + 1)) begin
                    $display("  [ERR] period=%0d, expect %0d (t=%0t)", cyc_cnt, prescale+1, $time);
                    errors = errors + 1;
                end
                cyc_cnt <= 1;
            end
        end
        phase_prev <= phase;
    end

    initial begin
        reset    = 0;
        enable   = 0;
        pause    = 0;
        prescale = 16'd3;      // period = 4 clk/pha -> 16 clk/bit
        phase_prev = 0;
        #23 reset = 1;

        // enable=0: phase phải giữ A
        #40;
        if (phase !== 2'd0) begin
            $display("  [ERR] enable=0 nhung phase=%0d (khac A)", phase); errors=errors+1;
        end

        // Bật core
        @(negedge clk); enable = 1;
        @(posedge clk); cyc_cnt = 0; checking = 1;   // bắt đầu đo period

        // Chạy vài bit, quan sát chuỗi pha
        repeat (4*16) @(posedge clk);

        // Test pause: đóng băng ở pha hiện tại
        checking = 0;                                 // ngừng đo quanh pause
        @(negedge clk); pause = 1;
        phase_prev = phase;
        repeat (30) @(posedge clk);
        if (phase !== phase_prev) begin
            $display("  [ERR] pause=1 nhung phase van doi (%0d->%0d)", phase_prev, phase);
            errors = errors + 1;
        end
        @(negedge clk); pause = 0;
        repeat (2*16) @(posedge clk);

        if (errors == 0) $display("PASS: I2C_Clock_Divider");
        else             $display("FAIL: I2C_Clock_Divider (%0d errors)", errors);
        $finish;
    end

    // Kiểm tra strobe khớp pha
    always @(posedge clk) begin
        if (tick_a && phase!==2'd0) begin $display("[ERR] tick_a sai pha=%0d",phase); errors=errors+1; end
        if (tick_b && phase!==2'd1) begin $display("[ERR] tick_b sai pha=%0d",phase); errors=errors+1; end
        if (tick_c && phase!==2'd2) begin $display("[ERR] tick_c sai pha=%0d",phase); errors=errors+1; end
        if (tick_d && phase!==2'd3) begin $display("[ERR] tick_d sai pha=%0d",phase); errors=errors+1; end
    end

endmodule
