`timescale 1ns/1ps

// ============================================================================
// Testbench   : tb_uart_tx
// Chuc nang   : Kiem chung tu dong UART Transmitter.
//
// Noi dung kiem tra:
//   - Ready/valid handshake.
//   - START bit.
//   - Thu tu truyen D0 den D7.
//   - STOP bit.
//   - TX co chot du lieu dau vao hay khong.
//   - tx_busy, tx_ready va tx_done.
//   - Reset bat dong bo khi dang truyen.
// ============================================================================
module tb_uart_tx;

    // ------------------------------------------------------------------------
    // Cau hinh giong project tren DE10-Lite
    // ------------------------------------------------------------------------
    localparam integer CLOCK_FREQ = 50_000_000;
    localparam integer BAUD_RATE  = 115_200;

    localparam integer CLK_PERIOD_NS = 20;

    localparam integer CLKS_PER_BIT =
        CLOCK_FREQ / BAUD_RATE;

    reg clk;
    reg rst_n;

    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;

    wire uart_tx_o;
    wire tx_busy;
    wire tx_done;

    integer error_count;
    integer test_count;

    // ------------------------------------------------------------------------
    // DUT: Design Under Test
    // ------------------------------------------------------------------------
    uart_tx #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),

        .tx_data   (tx_data),
        .tx_valid  (tx_valid),
        .tx_ready  (tx_ready),

        .uart_tx_o (uart_tx_o),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    // ------------------------------------------------------------------------
    // Tao clock 50 MHz
    //
    // Chu ky:
    //   T = 1 / 50 MHz = 20 ns
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Task: report_error
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
    // Task: drive_byte
    //
    // Dong vai tro khoi producer dua mot byte vao UART TX.
    //
    // Quy tac ready/valid:
    //   - Cho tx_ready.
    //   - Dat tx_data va tx_valid tai canh xuong.
    //   - DUT chap nhan du lieu tai canh len tiep theo.
    //   - Sau handshake, producer duoc phep thay doi tx_data.
    // ------------------------------------------------------------------------
    task drive_byte;
        input [7:0] value;

        begin
            // Thay doi stimulus tai canh xuong de tranh race condition.
            @(negedge clk);

            while (tx_ready !== 1'b1) begin
                @(negedge clk);
            end

            tx_data  = value;
            tx_valid = 1'b1;

            // Handshake xay ra tai canh len tiep theo.
            @(posedge clk);

            // Cho den canh xuong roi ha valid.
            @(negedge clk);
            tx_valid = 1'b0;

            // Co tinh thay doi tx_data sau handshake.
            // Neu DUT khong chot du lieu, frame se bi sai.
            tx_data = ~value;
        end
    endtask

    // ------------------------------------------------------------------------
    // Task: check_uart_frame
    //
    // Dong vai tro UART receiver don gian trong testbench.
    // Task chi quan sat chan uart_tx_o, khong doc thanh ghi noi bo cua DUT.
    // ------------------------------------------------------------------------
    task check_uart_frame;
        input [7:0] expected_data;

        integer bit_index;

        begin
            // Cho canh xuong bat dau START bit.
            @(negedge uart_tx_o);

            // ------------------------------------------------------------
            // Kiem tra START bit tai diem giua
            // ------------------------------------------------------------
            repeat (CLKS_PER_BIT / 2) begin
                @(posedge clk);
            end

            if (uart_tx_o !== 1'b0) begin
                report_error(
                    "START bit khong bang 0 tai diem lay mau"
                );
            end

            // ------------------------------------------------------------
            // Kiem tra 8 data bit, LSB truoc
            // ------------------------------------------------------------
            for (
                bit_index = 0;
                bit_index < 8;
                bit_index = bit_index + 1
            ) begin
                repeat (CLKS_PER_BIT) begin
                    @(posedge clk);
                end

                if (uart_tx_o !== expected_data[bit_index]) begin
                    $display(
                        "[%0t] ERROR: D%0d expected=%b actual=%b",
                        $time,
                        bit_index,
                        expected_data[bit_index],
                        uart_tx_o
                    );

                    error_count = error_count + 1;
                end
            end

            // ------------------------------------------------------------
            // Kiem tra STOP bit
            // ------------------------------------------------------------
            repeat (CLKS_PER_BIT) begin
                @(posedge clk);
            end

            if (uart_tx_o !== 1'b1) begin
                report_error(
                    "STOP bit khong bang 1 tai diem lay mau"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Task: run_tx_test
    //
    // Chay day du mot test case cho mot byte.
    // Driver va monitor phai hoat dong dong thoi, nen su dung fork/join.
    // ------------------------------------------------------------------------
    task run_tx_test;
        input [7:0] test_data;

        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Gui byte 0x%02h",
                $time,
                test_count,
                test_data
            );

            // Truoc khi gui, UART phai dang ranh.
            if (tx_ready !== 1'b1) begin
                report_error(
                    "tx_ready phai bang 1 truoc khi gui"
                );
            end

            if (tx_busy !== 1'b0) begin
                report_error(
                    "tx_busy phai bang 0 truoc khi gui"
                );
            end

            if (uart_tx_o !== 1'b1) begin
                report_error(
                    "uart_tx_o phai bang 1 khi IDLE"
                );
            end

            // Driver va monitor chay song song.
            fork
                drive_byte(test_data);
                check_uart_frame(test_data);
            join

            // Monitor ket thuc tai giua STOP bit.
            // Cho DUT truyen het nua STOP bit con lai.
            @(posedge tx_done);

            // Lay mau tai canh xuong de cac NBA va continuous assignment
            // lien quan den state/tx_done da on dinh, tranh delta-cycle race.
            @(negedge clk);

            // Khi tx_done xuat hien, UART phai quay ve IDLE.
            if (tx_ready !== 1'b1) begin
                report_error(
                    "tx_ready khong bang 1 sau khi truyen xong"
                );
            end

            if (tx_busy !== 1'b0) begin
                report_error(
                    "tx_busy khong bang 0 sau khi truyen xong"
                );
            end

            if (uart_tx_o !== 1'b1) begin
                report_error(
                    "uart_tx_o khong bang 1 sau khi truyen xong"
                );
            end

            // Kiem tra tx_done chi keo dai mot chu ky clock.
            if (tx_done !== 1'b1) begin
                report_error(
                    "tx_done khong duy tri trong du mot chu ky clock"
                );
            end

            @(negedge clk);

            if (tx_done !== 1'b0) begin
                report_error(
                    "tx_done keo dai qua mot chu ky clock"
                );
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Task: run_reset_mid_frame_test
    //
    // Assert reset sau START bit de xac nhan frame dang do bi huy ngay, UART
    // tro ve muc nghi va khong phat tx_done gia.
    // ------------------------------------------------------------------------
    task run_reset_mid_frame_test;
        begin
            test_count = test_count + 1;

            $display(
                "[%0t] TEST %0d: Reset giua frame",
                $time,
                test_count
            );

            drive_byte(8'h96);

            // Di qua het START bit va vao dau data bit D0.
            repeat (CLKS_PER_BIT + 20) begin
                @(posedge clk);
            end

            @(negedge clk);
            rst_n = 1'b0;
            #1;

            if (uart_tx_o !== 1'b1) begin
                report_error("reset giua frame khong dua TX ve muc nghi");
            end

            if (tx_ready !== 1'b0) begin
                report_error("tx_ready phai bang 0 trong reset");
            end

            if (tx_busy !== 1'b0) begin
                report_error("tx_busy phai bang 0 trong reset");
            end

            if (tx_done !== 1'b0) begin
                report_error("reset giua frame khong duoc tao tx_done");
            end

            repeat (3) begin
                @(posedge clk);
            end

            @(negedge clk);
            rst_n = 1'b1;
            #1;

            if (uart_tx_o !== 1'b1) begin
                report_error("uart_tx_o khong o muc nghi sau reset");
            end

            if (tx_ready !== 1'b1) begin
                report_error("tx_ready khong tro lai sau reset");
            end

            if (tx_busy !== 1'b0) begin
                report_error("tx_busy khong ve 0 sau reset");
            end

            if (tx_done !== 1'b0) begin
                report_error("tx_done bi assert sau reset");
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Assertion don gian:
    // tx_ready va tx_busy khong duoc cung bang 1.
    //
    // Assertion la dieu kien phai luon dung trong suot mo phong.
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (
                (tx_ready === 1'b1) &&
                (tx_busy  === 1'b1)
            ) begin
                report_error(
                    "tx_ready va tx_busy cung bang 1"
                );
            end
        end
    end

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 12);

        rst_n       = 1'b0;
        tx_data     = 8'h00;
        tx_valid    = 1'b0;
        error_count = 0;
        test_count  = 0;


        // ================================================================
        // RESET
        // ================================================================
        repeat (5) begin
            @(posedge clk);
        end

        // Trong reset, TX phai o muc nghi.
        if (uart_tx_o !== 1'b1) begin
            report_error(
                "uart_tx_o khong bang 1 trong reset"
            );
        end

        if (tx_ready !== 1'b0) begin
            report_error("tx_ready phai bang 0 trong reset");
        end

        if (tx_busy !== 1'b0) begin
            report_error("tx_busy phai bang 0 trong reset");
        end

        if (tx_done !== 1'b0) begin
            report_error("tx_done phai bang 0 trong reset");
        end

        // Nha reset tai canh xuong.
        @(negedge clk);
        rst_n = 1'b1;

        repeat (2) begin
            @(posedge clk);
        end

        // ================================================================
        // CAC TEST CASE
        // ================================================================

        // Mau du lieu co nhieu chuyen muc.
        run_tx_test(8'hA5);

        // Tat ca data bit bang 0.
        run_tx_test(8'h00);

        // Tat ca data bit bang 1.
        run_tx_test(8'hFF);

        // Mau du lieu khac.
        run_tx_test(8'h3C);

        // Reset bat dong bo phai huy frame dang truyen mot cach xac dinh.
        run_reset_mid_frame_test;

        // ================================================================
        // KET LUAN
        // ================================================================
        if (error_count == 0) begin
            $display("============================================");
            $display(
                "PASS: UART TX vuot qua %0d test case",
                test_count
            );
            $display("TEST_RESULT: PASS: tb_uart_tx");
            $display("============================================");
        end else begin
            $display("============================================");
            $display(
                "FAIL: UART TX co %0d loi",
                error_count
            );
            $display("TEST_RESULT: FAIL: tb_uart_tx");
            $display("============================================");
        end

        $finish;
    end

    // ------------------------------------------------------------------------
    // Watchdog timeout
    //
    // Neu DUT bi ket va testbench cho vo han, watchdog se dung mo phong.
    // ------------------------------------------------------------------------
    initial begin
        #2_000_000;

        $display("============================================");
        $display("FAIL: Simulation timeout");
        $display("TEST_RESULT: FAIL: tb_uart_tx (timeout)");
        $display("============================================");

        $finish;
    end

endmodule
