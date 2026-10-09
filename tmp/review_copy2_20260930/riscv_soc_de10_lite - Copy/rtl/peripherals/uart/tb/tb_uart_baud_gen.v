`timescale 1ns/1ps

// ============================================================================
// Testbench   : tb_uart_baud_gen
// Chuc nang   : Kiem chung tu dong module uart_baud_gen.
//
// Phuong phap:
//   - Tao clock.
//   - Dieu khien reset, enable va restart.
//   - Dem so chu ky clock.
//   - So sanh tick voi ket qua mong doi.
//   - Tu dong bao PASS hoac FAIL.
// Yeu cau:
//   - Reset dua counter ve 0 va ep tick ve 0.
//   - Khi enable = 0, khong co tick.
//   - Hai tick lien tiep cach nhau CLOCK_FREQ / BAUD_RATE clock.
//   - restart bat dau lai mot chu ky dem.
//   - Cau hinh divider bang 1 tao clock-enable o moi canh len, nhung tick
//     van phai bang 0 trong reset hoac khi restart duoc assert.

// Luu y:
//   Testbench khong duoc tong hop thanh phan cung.
// ============================================================================

module tb_uart_baud_gen;

    // ------------------------------------------------------------------------
    // Cau hinh mo phong
    // ------------------------------------------------------------------------
    localparam integer CLOCK_FREQ       = 1_000_000;
    localparam integer BAUD_RATE        = 100_000;

    localparam integer EXPECTED_CYCLES = CLOCK_FREQ / BAUD_RATE;

    // Clock 1 MHz, nhat quan voi CLOCK_FREQ cua DUT.
    localparam integer CLK_PERIOD_NS = 1_000;

    reg  clk;
    reg  rst_n;
    reg  enable;
    reg  restart;
    wire tick;

    reg  enable_div1;
    reg  restart_div1;
    wire tick_div1;

    integer error_count;

     // ------------------------------------------------------------------------
    // DUT: Design Under Test
    //
    // DUT la module dang duoc kiem chung.
    // ------------------------------------------------------------------------

    uart_baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .restart(restart),
        .tick(tick)
    );

    // Bien the divider = 1 de kiem tra bien CLKS_PER_TICK == 1.
    uart_baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(CLOCK_FREQ)
    ) dut_div1 (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable_div1),
        .restart(restart_div1),
        .tick(tick_div1)
    );

    // ------------------------------------------------------------------------
    // Tao clock co chu ky CLK_PERIOD_NS.
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Task: report_error
    //
    // Task la thu tuc trong testbench, dung de gom cac thao tac lap lai.
    // Moi khi phat hien sai, tang error_count va in thong bao.
    // ------------------------------------------------------------------------
    task report_error;
        input [8*80-1:0] message;

        begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %0s", $time, message);
        end
    endtask

    // ------------------------------------------------------------------------
    // Task: expect_tick_after
    //
    // Kiem tra rang:
    //   - Trong expected_cycles - 1 clock dau, tick phai bang 0.
    //   - Tai clock thu expected_cycles, tick phai bang 1.
    //
    // Testbench doc tick tai canh len cua clk, cung thoi diem ma FSM UART
    // sau nay se su dung tick.
    // ------------------------------------------------------------------------
    task expect_tick_after;
        input integer expected_cycles;
        integer cycle_index;

        begin
            for (
                cycle_index = 1;
                cycle_index <= expected_cycles;
                cycle_index = cycle_index + 1
            ) begin
                @(posedge clk);

                if (cycle_index < expected_cycles) begin
                    if (tick !== 1'b0) begin
                        $display(
                            "[%0t] ERROR: tick den som tai cycle %0d",
                            $time,
                            cycle_index
                        );

                        error_count = error_count + 1;
                    end
                end else begin
                    if (tick !== 1'b1) begin
                        $display(
                            "[%0t] ERROR: tick khong xuat hien tai cycle %0d",
                            $time,
                            cycle_index
                        );

                        error_count = error_count + 1;
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 12);

        rst_n        = 1'b0;
        enable       = 1'b0;
        restart      = 1'b0;
        enable_div1  = 1'b1;
        restart_div1 = 1'b0;
        error_count  = 0;

        // ================================================================
        // TEST 1: Reset
        // ================================================================
        $display("TEST 1: Kiem tra reset");

        repeat (4) begin
            @(posedge clk);

            if (tick !== 1'b0) begin
                report_error("tick phai bang 0 trong khi reset");
            end

            if (tick_div1 !== 1'b0) begin
                report_error("tick divider=1 phai bang 0 trong reset");
            end
        end

        // Nha reset tai canh xuong de tranh race condition voi DUT.
        @(negedge clk);
        rst_n = 1'b1;

        // ================================================================
        // TEST 2: Divider bang 1 va reset gating
        // ================================================================
        $display("TEST 2: Kiem tra divider bang 1");

        repeat (3) begin
            @(posedge clk);

            if (tick_div1 !== 1'b1) begin
                report_error("divider=1 phai tao tick tai moi clock");
            end
        end

        @(negedge clk);
        restart_div1 = 1'b1;
        #1;

        if (tick_div1 !== 1'b0) begin
            report_error("restart phai ep tick divider=1 ve 0");
        end

        @(posedge clk);
        @(negedge clk);
        restart_div1 = 1'b0;
        #1;

        if (tick_div1 !== 1'b1) begin
            report_error("tick divider=1 khong tro lai sau restart");
        end

        enable_div1 = 1'b0;

        // ================================================================
        // TEST 3: Disable
        // ================================================================
        $display("TEST 3: Kiem tra enable = 0");

        repeat (15) begin
            @(posedge clk);

            if (tick !== 1'b0) begin
                report_error("tick xuat hien khi enable = 0");
            end
        end

        // ================================================================
        // TEST 4: Tick dau tien
        // ================================================================
        $display("TEST 4: Kiem tra tick dau tien");

        @(negedge clk);
        enable = 1'b1;

        expect_tick_after(EXPECTED_CYCLES);

        // ================================================================
        // TEST 5: Hai tick lien tiep
        // ================================================================
        $display("TEST 5: Kiem tra chu ky tick lien tiep");

        expect_tick_after(EXPECTED_CYCLES);

        // ================================================================
        // TEST 6: Restart giua chu ky dem
        // ================================================================
        $display("TEST 6: Kiem tra restart");

        // Cho counter dem mot phan chu ky.
        repeat (4) begin
            @(posedge clk);
        end

        // Dua restart len tai canh xuong.
        @(negedge clk);
        restart = 1'b1;

        // DUT nhan restart tai canh len tiep theo.
        @(posedge clk);

        // Ha restart tai canh xuong.
        @(negedge clk);
        restart = 1'b0;

        // Sau restart, phai cho du EXPECTED_CYCLES clock moi co tick.
        expect_tick_after(EXPECTED_CYCLES);

        // ================================================================
        // TEST 7: Disable giua chu ky
        // ================================================================
        $display("TEST 7: Kiem tra disable giua chu ky");

        repeat (3) begin
            @(posedge clk);
        end

        @(negedge clk);
        enable = 1'b0;

        repeat (15) begin
            @(posedge clk);

            if (tick !== 1'b0) begin
                report_error("tick xuat hien sau khi disable");
            end
        end

        // ================================================================
        // TEST 8: Enable lai
        // ================================================================
        $display("TEST 8: Kiem tra enable lai");

        @(negedge clk);
        enable = 1'b1;

        // Vi disable dua counter ve 0, chu ky moi phai du EXPECTED_CYCLES clock.
        expect_tick_after(EXPECTED_CYCLES);

        // ================================================================
        // TEST 9: Tick chi keo dai mot clock
        // ================================================================
        $display("TEST 9: Kiem tra do rong tick");

        // Tai day tick dang bang 1 tai canh clock vua kiem tra.
        // Canh clock tiep theo tick phai tro ve 0.
        @(posedge clk);

        if (tick !== 1'b0) begin
            report_error("tick keo dai qua mot chu ky clock");
        end

        // ================================================================
        // Ket luan
        // ================================================================
        if (error_count == 0) begin
            $display("============================================");
            $display("PASS: uart_baud_gen hoat dong dung");
            $display("TEST_RESULT: PASS: tb_uart_baud_gen");
            $display("============================================");
        end else begin
            $display("============================================");
            $display(
                "FAIL: uart_baud_gen co %0d loi",
                error_count
            );
            $display("TEST_RESULT: FAIL: tb_uart_baud_gen");
            $display("============================================");
        end

        $finish;
    end

    // Watchdog de moi ket qua timeout deu co marker may-readable.
    initial begin
        #200_000;
        $display("============================================");
        $display("FAIL: Simulation timeout");
        $display("TEST_RESULT: FAIL: tb_uart_baud_gen (timeout)");
        $display("============================================");
        $finish;
    end

endmodule
