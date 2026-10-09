`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Testbench   : tb_uart_loopback_top
// Chuc nang   : Kiem chung tich hop UART RX -> UART TX.
//
// Testbench dong vai thiet bi UART ben ngoai:
//   - Gui frame vao GPIO_UART_RX.
//   - Quan sat frame tren GPIO_UART_TX.
//   - So sanh du lieu gui vao va du lieu nhan lai.
// ============================================================================
module tb_uart_loopback_top;

    localparam integer CLOCK_FREQ = 50_000_000;
    localparam integer BAUD_RATE  = 115_200;
    localparam integer OVERSAMPLE = 16;

    localparam integer CLK_PERIOD_NS = 20;

    localparam integer CLKS_PER_BIT =
        CLOCK_FREQ / BAUD_RATE;

    reg CLOCK_50;
    reg [1:0] KEY;

    reg  GPIO_UART_RX;
    wire GPIO_UART_TX;

    wire [9:0] LEDR;

    integer error_count;
    integer test_count;
    integer tx_falling_edge_count;
    integer edge_count_before_test;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    uart_loopback_top #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) dut (
        .CLOCK_50     (CLOCK_50),
        .KEY          (KEY),
        .GPIO_UART_RX (GPIO_UART_RX),
        .GPIO_UART_TX (GPIO_UART_TX),
        .LEDR         (LEDR)
    );

    // ------------------------------------------------------------------------
    // Tao clock 50 MHz
    // ------------------------------------------------------------------------
    initial begin
        CLOCK_50 = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        CLOCK_50 = ~CLOCK_50;
    end

    // ------------------------------------------------------------------------
    // Dem so canh xuong tren TX.
    //
    // Counter nay duoc dung de kiem tra frame loi co bi echo hay khong.
    // ------------------------------------------------------------------------
    always @(negedge GPIO_UART_TX) begin
        tx_falling_edge_count =
            tx_falling_edge_count + 1;
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
    // Testbench dieu khien mot UART bit vao RX.
    // ------------------------------------------------------------------------
    task drive_rx_bit;
        input bit_value;

        begin
            // Thay doi du lieu tai canh xuong.
            @(negedge CLOCK_50);
            GPIO_UART_RX = bit_value;

            // Giu bit trong dung mot chu ky baud.
            repeat (CLKS_PER_BIT) begin
                @(posedge CLOCK_50);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Gui mot frame vao UART RX cua DUT.
    //
    // stop_value = 1: frame hop le.
    // stop_value = 0: framing error.
    // ------------------------------------------------------------------------
    task send_rx_frame;
        input [7:0] value;
        input       stop_value;

        integer bit_index;

        begin
            // START bit
            drive_rx_bit(1'b0);

            // D0 den D7
            for (
                bit_index = 0;
                bit_index < 8;
                bit_index = bit_index + 1
            ) begin
                drive_rx_bit(value[bit_index]);
            end

            // STOP bit
            drive_rx_bit(stop_value);
        end
    endtask

    // ------------------------------------------------------------------------
    // Giam sat mot frame do UART TX phat ra.
    //
    // Monitor chi quan sat GPIO_UART_TX, khong doc data_reg noi bo.
    // ------------------------------------------------------------------------
    task check_tx_frame;
        input [7:0] expected_data;

        integer bit_index;

        begin
            // Cho canh xuong cua START bit.
            @(negedge GPIO_UART_TX);

            // Lay mau giua START bit.
            repeat (CLKS_PER_BIT / 2) begin
                @(posedge CLOCK_50);
            end

            if (GPIO_UART_TX !== 1'b0) begin
                report_error(
                    "TX START bit khong bang 0"
                );
            end

            // Lay mau giua tung data bit.
            for (
                bit_index = 0;
                bit_index < 8;
                bit_index = bit_index + 1
            ) begin
                repeat (CLKS_PER_BIT) begin
                    @(posedge CLOCK_50);
                end

                if (
                    GPIO_UART_TX !==
                    expected_data[bit_index]
                ) begin
                    $display(
                        "[%0t] ERROR: TX D%0d expected=%b actual=%b",
                        $time,
                        bit_index,
                        expected_data[bit_index],
                        GPIO_UART_TX
                    );

                    error_count = error_count + 1;
                end
            end

            // Lay mau giua STOP bit.
            repeat (CLKS_PER_BIT) begin
                @(posedge CLOCK_50);
            end

            if (GPIO_UART_TX !== 1'b1) begin
                report_error(
                    "TX STOP bit khong bang 1"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Chay mot test loopback
    // ------------------------------------------------------------------------
    task run_loopback_test;
        input [7:0] test_data;

        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Loopback 0x%02h",
                $time,
                test_count,
                test_data
            );

            // Driver RX va monitor TX hoat dong dong thoi.
            fork
                begin
                    send_rx_frame(
                        test_data,
                        1'b1
                    );

                    // Bao dam RX tro ve muc IDLE.
                    @(negedge CLOCK_50);
                    GPIO_UART_RX = 1'b1;
                end

                begin
                    check_tx_frame(test_data);
                end
            join

            // Cho TX ket thuc toan bo STOP bit.
            wait (LEDR[0] === 1'b0);

            repeat (5) begin
                @(posedge CLOCK_50);
            end

            if (GPIO_UART_TX !== 1'b1) begin
                report_error(
                    "TX khong tro ve IDLE sau loopback"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Test hai frame den lien tiep
    // ------------------------------------------------------------------------
    task run_back_to_back_test;
        input [7:0] first_data;
        input [7:0] second_data;

        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Back-to-back 0x%02h, 0x%02h",
                $time,
                test_count,
                first_data,
                second_data
            );

            fork
                begin
                    // Sau STOP cua frame dau, frame tiep theo bat dau.
                    send_rx_frame(
                        first_data,
                        1'b1
                    );

                    send_rx_frame(
                        second_data,
                        1'b1
                    );

                    @(negedge CLOCK_50);
                    GPIO_UART_RX = 1'b1;
                end

                begin
                    check_tx_frame(first_data);
                    check_tx_frame(second_data);
                end
            join

            wait (LEDR[0] === 1'b0);

            repeat (5) begin
                @(posedge CLOCK_50);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Test frame co STOP bit sai
    // ------------------------------------------------------------------------
    task run_bad_frame_test;
        input [7:0] test_data;

        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Bad STOP for 0x%02h",
                $time,
                test_count,
                test_data
            );

            // Luu tong so canh xuong tren TX truoc khi gui frame loi.
            edge_count_before_test =
                tx_falling_edge_count;

            send_rx_frame(
                test_data,
                1'b0
            );

            // Dua RX tro lai trang thai IDLE.
            @(negedge CLOCK_50);
            GPIO_UART_RX = 1'b1;

            // Cho du thoi gian de DUT co the echo neu logic bi sai.
            repeat (CLKS_PER_BIT * 12) begin
                @(posedge CLOCK_50);
            end

            // TX khong duoc tao frame moi.
            if (
                tx_falling_edge_count !=
                edge_count_before_test
            ) begin
                report_error(
                    "Frame co framing error van bi echo"
                );
            end

            // LEDR[2] la sticky framing-error flag.
            if (LEDR[2] !== 1'b1) begin
                report_error(
                    "Sticky framing-error LED khong duoc set"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 12);

        KEY                   = 2'b11;
        GPIO_UART_RX          = 1'b1;
        error_count           = 0;
        test_count            = 0;
        tx_falling_edge_count = 0;
        edge_count_before_test = 0;

`ifdef DUMP_VCD
        $dumpfile("tb_uart_loopback_top.vcd");
        $dumpvars(0, tb_uart_loopback_top);
`endif

        // ================================================================
        // TEST RESET
        // ================================================================
        $display(
            "[%0t] TEST: Reset",
            $time
        );

        // KEY[0] active-low.
        @(negedge CLOCK_50);
        KEY[0] = 1'b0;

        repeat (5) begin
            @(posedge CLOCK_50);
        end

        if (GPIO_UART_TX !== 1'b1) begin
            report_error(
                "UART TX khong bang 1 trong reset"
            );
        end

        if (LEDR !== 10'b0000000000) begin
            report_error(
                "LEDR khong duoc xoa trong reset"
            );
        end

        // Nha reset.
        @(negedge CLOCK_50);
        KEY[0] = 1'b1;

        // Cho reset synchronizer nha reset.
        repeat (5) begin
            @(posedge CLOCK_50);
        end

        // ================================================================
        // TEST LOOPBACK
        // ================================================================
        run_loopback_test(8'hA5);
        run_loopback_test(8'h00);
        run_loopback_test(8'hFF);

        // ASCII 'A'
        run_loopback_test(8'h41);

        // ASCII 'U'
        run_loopback_test(8'h55);

        // ================================================================
        // TEST BACK-TO-BACK
        // ================================================================
        run_back_to_back_test(
            8'h12,
            8'h34
        );

        // ================================================================
        // TEST FRAME LOI
        //
        // Test nay duoc dat cuoi vi LEDR[2] la sticky flag va chi duoc xoa
        // bang reset.
        // ================================================================
        run_bad_frame_test(8'h3C);

        // ================================================================
        // KET LUAN
        // ================================================================
        if (error_count == 0) begin
            $display("============================================");
            $display(
                "PASS: UART loopback vuot qua %0d test case",
                test_count
            );
            $display("TEST_RESULT: PASS: tb_uart_loopback_top");
            $display("============================================");
        end else begin
            $display("============================================");
            $display(
                "FAIL: UART loopback co %0d loi",
                error_count
            );
            $display(
                "TEST_RESULT: FAIL: tb_uart_loopback_top (%0d errors)",
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
        #20_000_000;

        $display("============================================");
        $display("FAIL: UART loopback simulation timeout");
        $display("TEST_RESULT: FAIL: tb_uart_loopback_top (timeout)");
        $display("============================================");

        $finish;
    end

endmodule

`default_nettype wire
