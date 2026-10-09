`default_nettype none
`timescale 1ns/1ps

// ============================================================================
// Testbench   : tb_uart_rx
// Chuc nang   : Kiem chung tu dong UART Receiver.
//
// Testbench dong vai mot thiet bi UART ben ngoai:
//   - Tao START bit.
//   - Gui D0 den D7.
//   - Tao STOP bit.
//   - Tao false start.
//   - Tao framing error.
//   - Kiem tra ready/valid va overrun.
// ============================================================================
module tb_uart_rx;

    localparam integer CLOCK_FREQ = 50_000_000;
    localparam integer BAUD_RATE  = 115_200;
    localparam integer OVERSAMPLE = 16;

    localparam integer CLK_PERIOD_NS = 20;

    localparam integer CLKS_PER_BIT =
        CLOCK_FREQ / BAUD_RATE;

    reg clk;
    reg rst_n;

    // Tin hieu UART do testbench dieu khien.
    reg uart_rx_i;

    wire [7:0] rx_data;
    wire       rx_valid;
    reg        rx_ready;

    wire framing_error;
    wire overrun_error;

    integer error_count;
    integer test_count;
    integer break_event_count;

    reg break_overrun_seen;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    uart_rx #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx_i     (uart_rx_i),

        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .rx_ready      (rx_ready),

        .framing_error (framing_error),
        .overrun_error (overrun_error)
    );

    // ------------------------------------------------------------------------
    // Tao clock 50 MHz
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Bao loi
    // ------------------------------------------------------------------------
    task report_error;
        input [8*100-1:0] message;

        begin
            error_count = error_count + 1;

            $display(
                "[%0t] ERROR: %0s",
                $time,
                message
            );
        end
    endtask

    // ------------------------------------------------------------------------
    // Gui mot bit UART
    //
    // Moi bit duoc giu trong CLKS_PER_BIT chu ky clock he thong.
    // Tin hieu thay doi tai canh xuong de tranh race condition voi DUT.
    // ------------------------------------------------------------------------
    task drive_uart_bit;
        input bit_value;

        begin
            @(negedge clk);
            uart_rx_i = bit_value;

            repeat (CLKS_PER_BIT) begin
                @(posedge clk);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Gui mot frame UART 8N1
    //
    // stop_value = 1: frame hop le.
    // stop_value = 0: tao framing error.
    // ------------------------------------------------------------------------
    task send_uart_frame;
        input [7:0] value;
        input       stop_value;

        integer bit_index;

        begin
            // START bit
            drive_uart_bit(1'b0);

            // DATA bits: LSB truoc
            for (
                bit_index = 0;
                bit_index < 8;
                bit_index = bit_index + 1
            ) begin
                drive_uart_bit(value[bit_index]);
            end

            // STOP bit
            drive_uart_bit(stop_value);
        end
    endtask

    // ------------------------------------------------------------------------
    // Kiem tra byte dang nam tren giao tiep RX
    // ------------------------------------------------------------------------
    task check_received_byte;
        input [7:0] expected_data;
        input       expected_frame_error;

        begin
            // wait khac voi @(posedge rx_valid):
            // Neu rx_valid da bang 1, wait se tiep tuc ngay.
            wait (rx_valid === 1'b1);

            if (rx_data !== expected_data) begin
                $display(
                    "[%0t] ERROR: expected data=0x%02h, actual=0x%02h",
                    $time,
                    expected_data,
                    rx_data
                );

                error_count = error_count + 1;
            end

            if (framing_error !== expected_frame_error) begin
                $display(
                    "[%0t] ERROR: expected framing_error=%b, actual=%b",
                    $time,
                    expected_frame_error,
                    framing_error
                );

                error_count = error_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Tao mot handshake de application doc byte
    // ------------------------------------------------------------------------
    task consume_received_byte;
        begin
            @(negedge clk);
            rx_ready = 1'b1;

            // Handshake xay ra tai canh len.
            @(posedge clk);

            @(negedge clk);
            rx_ready = 1'b0;

            if (rx_valid !== 1'b0) begin
                report_error(
                    "rx_valid khong duoc xoa sau handshake"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Chay test nhan mot frame hop le
    // ------------------------------------------------------------------------
    task run_normal_test;
        input [7:0] expected_data;

        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Receive 0x%02h",
                $time,
                test_count,
                expected_data
            );

            rx_ready = 1'b0;

            fork
                begin
                    send_uart_frame(
                        expected_data,
                        1'b1
                    );
                end

                begin
                    check_received_byte(
                        expected_data,
                        1'b0
                    );
                end
            join

            // Frame hop le ket thuc bang muc 1.
            uart_rx_i = 1'b1;

            // Khi rx_ready = 0, RX phai giu du lieu.
            repeat (20) begin
                @(posedge clk);

                if (rx_valid !== 1'b1) begin
                    report_error(
                        "rx_valid khong duoc giu khi rx_ready = 0"
                    );
                end

                if (rx_data !== expected_data) begin
                    report_error(
                        "rx_data thay doi khi chua co handshake"
                    );
                end
            end

            consume_received_byte();
        end
    endtask

    // ------------------------------------------------------------------------
    // Monitor mot rx_valid event khi rx_ready = 1
    // ------------------------------------------------------------------------
    task expect_rx_event;
        input [7:0] expected_data;

        begin
            // Dam bao khong nham voi event truoc.
            wait (rx_valid === 1'b0);
            wait (rx_valid === 1'b1);

            if (rx_data !== expected_data) begin
                $display(
                    "[%0t] ERROR: expected event data=0x%02h, actual=0x%02h",
                    $time,
                    expected_data,
                    rx_data
                );

                error_count = error_count + 1;
            end

            if (framing_error !== 1'b0) begin
                report_error(
                    "Frame hop le nhung framing_error bang 1"
                );
            end

            // Cho rx_valid duoc xoa truoc khi doi event tiep theo.
            @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Assertion don gian cho giao tiep dau ra
    //
    // Khi rx_valid = 1 va rx_ready = 0, du lieu phai duoc giu nguyen.
    // ------------------------------------------------------------------------
    reg [7:0] held_rx_data;
    reg       held_frame_error;
    reg       holding_output;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            held_rx_data      <= 8'h00;
            held_frame_error  <= 1'b0;
            holding_output    <= 1'b0;
        end else begin
            if (rx_valid && !rx_ready) begin
                if (holding_output) begin
                    if (rx_data !== held_rx_data) begin
                        report_error(
                            "rx_data khong on dinh khi bi backpressure"
                        );
                    end

                    if (framing_error !== held_frame_error) begin
                        report_error(
                            "framing_error thay doi khi bi backpressure"
                        );
                    end
                end else begin
                    held_rx_data     <= rx_data;
                    held_frame_error <= framing_error;
                    holding_output   <= 1'b1;
                end
            end else begin
                holding_output <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 12);

        rst_n         = 1'b0;
        uart_rx_i     = 1'b1;
        rx_ready      = 1'b0;
        error_count   = 0;
        test_count    = 0;
        break_event_count = 0;
        break_overrun_seen = 1'b0;

`ifdef DUMP_VCD
        $dumpfile("tb_uart_rx.vcd");
        $dumpvars;
`endif

        // ================================================================
        // RESET
        // ================================================================
        repeat (5) begin
            @(posedge clk);
        end

        if (rx_valid !== 1'b0) begin
            report_error(
                "rx_valid phai bang 0 trong reset"
            );
        end

        @(negedge clk);
        rst_n = 1'b1;

        // Cho synchronizer on dinh.
        repeat (5) begin
            @(posedge clk);
        end

        // ================================================================
        // TEST 1-3: CAC FRAME HOP LE
        // ================================================================
        run_normal_test(8'hA5);
        run_normal_test(8'h00);
        run_normal_test(8'hFF);

        // ================================================================
        // TEST 4: FALSE START
        // ================================================================
        test_count = test_count + 1;

        $display(
            "[%0t] TEST %0d: False start",
            $time,
            test_count
        );

        // Keo RX xuong thap trong thoi gian nho hon nua bit.
        @(negedge clk);
        uart_rx_i = 1'b0;

        repeat (CLKS_PER_BIT / 4) begin
            @(posedge clk);
        end

        @(negedge clk);
        uart_rx_i = 1'b1;

        // Cho du thoi gian de bao dam RX da loai false start.
        repeat (CLKS_PER_BIT * 2) begin
            @(posedge clk);
        end

        if (rx_valid !== 1'b0) begin
            report_error(
                "False start tao ra mot byte khong hop le"
            );
        end

        // ================================================================
        // TEST 5: FRAMING ERROR
        // ================================================================
        test_count = test_count + 1;

        $display(
            "[%0t] TEST %0d: Framing error",
            $time,
            test_count
        );

        rx_ready = 1'b0;

        fork
            begin
                // STOP bit co tinh bang 0.
                send_uart_frame(
                    8'h3C,
                    1'b0
                );

                // Dua duong truyen tro lai IDLE sau bad STOP bit.
                @(negedge clk);
                uart_rx_i = 1'b1;
            end

            begin
                check_received_byte(
                    8'h3C,
                    1'b1
                );
            end
        join

        consume_received_byte();

        // Giu MARK du mot bit de RX thoat ST_WAIT_IDLE va tai dong bo pha.
        repeat (CLKS_PER_BIT) begin
            @(posedge clk);
        end

        // ================================================================
        // TEST 6: SUSTAINED BREAK CHI TAO MOT FRAME LOI
        // ================================================================
        test_count = test_count + 1;

        $display(
            "[%0t] TEST %0d: Sustained BREAK",
            $time,
            test_count
        );

        // Cho phep frame loi duoc consume de moi rx_valid pulse tuong ung
        // voi dung mot event. Giu RX thap lau hon hai frame day du.
        rx_ready           = 1'b1;
        break_event_count  = 0;
        break_overrun_seen = 1'b0;

        @(negedge clk);
        uart_rx_i = 1'b0;

        repeat (CLKS_PER_BIT * 22) begin
            @(negedge clk);

            if (rx_valid === 1'b1) begin
                break_event_count = break_event_count + 1;

                if (rx_data !== 8'h00) begin
                    report_error(
                        "BREAK phai tao byte 0x00"
                    );
                end

                if (framing_error !== 1'b1) begin
                    report_error(
                        "BREAK phai tao framing_error"
                    );
                end
            end

            if (overrun_error === 1'b1) begin
                break_overrun_seen = 1'b1;
            end
        end

        if (break_event_count != 1) begin
            $display(
                "[%0t] ERROR: BREAK tao %0d event, expected 1",
                $time,
                break_event_count
            );

            error_count = error_count + 1;
        end

        if (break_overrun_seen !== 1'b0) begin
            report_error(
                "BREAK tao overrun_error khong mong doi"
            );
        end

        @(negedge clk);
        uart_rx_i = 1'b1;
        rx_ready  = 1'b0;

        // ================================================================
        // TEST 7: PHUC HOI SAU BREAK
        // ================================================================
        // Giu MARK mot bit day du de RX re-arm truoc frame tiep theo.
        repeat (CLKS_PER_BIT) begin
            @(posedge clk);
        end

        run_normal_test(8'h5A);

        // ================================================================
        // TEST 8: RECEIVE OVERRUN
        // ================================================================
        test_count = test_count + 1;

        $display(
            "[%0t] TEST %0d: Receive overrun",
            $time,
            test_count
        );

        rx_ready = 1'b0;

        // Nhan byte dau tien nhung khong consume.
        fork
            send_uart_frame(8'h11, 1'b1);
            check_received_byte(8'h11, 1'b0);
        join

        uart_rx_i = 1'b1;

        // Gui byte thu hai khi byte dau van dang cho.
        fork
            begin
                send_uart_frame(8'h22, 1'b1);
                uart_rx_i = 1'b1;
            end

            begin
                wait (overrun_error === 1'b1);

                // Byte cu phai duoc bao toan.
                if (rx_data !== 8'h11) begin
                    report_error(
                        "Byte cu bi ghi de khi overrun"
                    );
                end

                if (rx_valid !== 1'b1) begin
                    report_error(
                        "rx_valid bi xoa khi overrun"
                    );
                end
            end
        join

        consume_received_byte();

        // ================================================================
        // TEST 9: HAI FRAME LIEN TIEP
        // ================================================================
        test_count = test_count + 1;

        $display(
            "[%0t] TEST %0d: Back-to-back frames",
            $time,
            test_count
        );

        @(negedge clk);
        rx_ready = 1'b1;

        fork
            begin
                send_uart_frame(8'h12, 1'b1);
                send_uart_frame(8'h34, 1'b1);
                uart_rx_i = 1'b1;
            end

            begin
                expect_rx_event(8'h12);
                expect_rx_event(8'h34);
            end
        join

        @(negedge clk);
        rx_ready = 1'b0;

        // ================================================================
        // KET LUAN
        // ================================================================
        if (error_count == 0) begin
            $display("============================================");
            $display("TEST_RESULT: PASS: tb_uart_rx");
            $display("Executed %0d test cases", test_count);
            $display("============================================");
        end else begin
            $display("============================================");
            $display(
                "TEST_RESULT: FAIL: tb_uart_rx (%0d errors)",
                error_count
            );
            $display("============================================");
        end

        $finish;
    end

    // ------------------------------------------------------------------------
    // Watchdog timeout
    // ------------------------------------------------------------------------
    initial begin
        #10_000_000;

        $display("============================================");
        $display("TEST_RESULT: FAIL: tb_uart_rx (watchdog timeout)");
        $display("============================================");

        $finish;
    end

endmodule

`default_nettype wire
