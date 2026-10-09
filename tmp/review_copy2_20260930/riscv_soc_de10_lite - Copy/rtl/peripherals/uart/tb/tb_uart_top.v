`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Testbench   : tb_uart_top
// Chức năng   : Kiểm tra tích hợp core UART tái sử dụng và hai FIFO.
//
// Tham số clock/baud tạo đúng 16 clock cho mỗi bit UART để mô phỏng nhanh nhưng
// vẫn giữ đúng trình tự ready/valid thực tế.
// ============================================================================
module tb_uart_top;

    localparam integer CLOCK_FREQ    = 50_000_000;
    localparam integer BAUD_RATE     = 3_125_000;
    localparam integer OVERSAMPLE    = 4;
    localparam integer FIFO_DEPTH    = 4;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer CLKS_PER_BIT  = CLOCK_FREQ / BAUD_RATE;

    reg clk;
    reg rst_n;

    reg        uart_rx_i;
    wire       uart_tx_o;

    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;

    wire [7:0] rx_data;
    wire       rx_valid;
    reg        rx_ready;
    wire       rx_framing_error;

    wire tx_busy;
    wire tx_done;
    wire rx_overrun_error;

    integer error_count;
    integer tx_done_count;

    uart_top #(
        .CLOCK_FREQ    (CLOCK_FREQ),
        .BAUD_RATE     (BAUD_RATE),
        .OVERSAMPLE    (OVERSAMPLE),
        .TX_FIFO_DEPTH (FIFO_DEPTH),
        .RX_FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .uart_rx_i        (uart_rx_i),
        .uart_tx_o        (uart_tx_o),
        .tx_data          (tx_data),
        .tx_valid         (tx_valid),
        .tx_ready         (tx_ready),
        .rx_data          (rx_data),
        .rx_valid         (rx_valid),
        .rx_ready         (rx_ready),
        .rx_framing_error (rx_framing_error),
        .tx_busy          (tx_busy),
        .tx_done          (tx_done),
        .rx_overrun_error (rx_overrun_error)
    );

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2) begin
        clk = ~clk;
    end

    always @(posedge tx_done) begin
        tx_done_count = tx_done_count + 1;
    end

    task report_error;
        input [8*120-1:0] message;
        begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %0s", $time, message);
        end
    endtask

    task enqueue_tx_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            tx_data  = value;
            tx_valid = 1'b1;

            while (tx_ready !== 1'b1) begin
                @(negedge clk);
            end

            @(posedge clk);
            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    task check_tx_frame;
        input [7:0] expected_data;
        integer bit_index;
        begin
            @(negedge uart_tx_o);

            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx_o !== 1'b0) begin
                report_error("TX start bit is not low at its midpoint");
            end

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                if (uart_tx_o !== expected_data[bit_index]) begin
                    $display(
                        "[%0t] ERROR: TX D%0d expected=%b actual=%b",
                        $time,
                        bit_index,
                        expected_data[bit_index],
                        uart_tx_o
                    );
                    error_count = error_count + 1;
                end
            end

            repeat (CLKS_PER_BIT) @(posedge clk);
            if (uart_tx_o !== 1'b1) begin
                report_error("TX stop bit is not high at its midpoint");
            end
        end
    endtask

    task drive_rx_bit;
        input bit_value;
        begin
            @(negedge clk);
            uart_rx_i = bit_value;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task send_rx_frame;
        input [7:0] value;
        input       stop_value;
        integer bit_index;
        begin
            drive_rx_bit(1'b0);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                drive_rx_bit(value[bit_index]);
            end
            drive_rx_bit(stop_value);
        end
    endtask

    task pop_rx_byte;
        input [7:0] expected_data;
        input       expected_framing_error;
        begin
            wait (rx_valid === 1'b1);

            if (rx_data !== expected_data) begin
                $display(
                    "[%0t] ERROR: RX expected=0x%02h actual=0x%02h",
                    $time,
                    expected_data,
                    rx_data
                );
                error_count = error_count + 1;
            end

            if (rx_framing_error !== expected_framing_error) begin
                $display(
                    "[%0t] ERROR: RX framing expected=%b actual=%b",
                    $time,
                    expected_framing_error,
                    rx_framing_error
                );
                error_count = error_count + 1;
            end

            @(negedge clk);
            rx_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rx_ready = 1'b0;
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 12);

        rst_n         = 1'b0;
        uart_rx_i     = 1'b1;
        tx_data       = 8'h00;
        tx_valid      = 1'b0;
        rx_ready      = 1'b0;
        error_count   = 0;
        tx_done_count = 0;

`ifdef DUMP_VCD
        $dumpfile("tb_uart_top.vcd");
        $dumpvars(0, tb_uart_top);
`endif

        repeat (4) @(posedge clk);

        if (tx_ready !== 1'b0) begin
            report_error("tx_ready must be low while reset is asserted");
        end
        if (rx_valid !== 1'b0) begin
            report_error("rx_valid must be low while reset is asserted");
        end
        if (uart_tx_o !== 1'b1) begin
            report_error("uart_tx_o must be high while reset is asserted");
        end

        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // Xếp hàng ba byte trước khi frame đầu kết thúc. Bộ giám sát nối tiếp
        // kiểm tra độc lập thứ tự FIFO và bộ phát.
        fork
            begin
                enqueue_tx_byte(8'hA5);
                enqueue_tx_byte(8'h00);
                enqueue_tx_byte(8'h3C);
            end
            begin
                check_tx_frame(8'hA5);
                check_tx_frame(8'h00);
                check_tx_frame(8'h3C);
            end
        join

        wait (tx_busy === 1'b0);
        @(negedge clk);
        if (tx_done_count != 3) begin
            $display(
                "[%0t] ERROR: expected 3 tx_done pulses, actual=%0d",
                $time,
                tx_done_count
            );
            error_count = error_count + 1;
        end

        // Nhận ba frame khi phía ứng dụng tạo áp lực ngược. Cả ba phải được xếp
        // hàng và giữ đúng thứ tự khi ứng dụng đọc ra.
        rx_ready = 1'b0;
        send_rx_frame(8'h12, 1'b1);
        send_rx_frame(8'h34, 1'b1);
        send_rx_frame(8'h56, 1'b1);
        @(negedge clk);
        uart_rx_i = 1'b1;

        pop_rx_byte(8'h12, 1'b0);
        pop_rx_byte(8'h34, 1'b0);
        pop_rx_byte(8'h56, 1'b0);

        // Thông tin framing phải luôn đi cùng đúng byte tương ứng.
        send_rx_frame(8'hC3, 1'b0);
        @(negedge clk);
        uart_rx_i = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
        pop_rx_byte(8'hC3, 1'b1);

        if (rx_overrun_error !== 1'b0) begin
            report_error("Unexpected receive overrun in buffered tests");
        end

        if (error_count == 0) begin
            $display("TEST_RESULT: PASS: tb_uart_top");
        end else begin
            $display(
                "TEST_RESULT: FAIL: tb_uart_top (%0d errors)",
                error_count
            );
        end

        $finish;
    end

    initial begin
        #2_000_000;
        $display("TEST_RESULT: FAIL: tb_uart_top (timeout)");
        $finish;
    end

endmodule

`default_nettype wire
