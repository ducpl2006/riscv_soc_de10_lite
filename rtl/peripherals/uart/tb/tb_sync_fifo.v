`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Testbench   : tb_sync_fifo
// Chức năng   : Tự kiểm tra FIFO đồng bộ dùng giao thức ready/valid.
//
// Chủ ý đặt DEPTH=3 để kiểm tra FIFO có độ sâu không phải lũy thừa của hai và
// xác nhận con trỏ quay vòng tường minh.
// ============================================================================
module tb_sync_fifo;

    localparam integer DATA_WIDTH = 8;
    localparam integer DEPTH      = 3;
    localparam integer CLK_PERIOD = 10;

    reg                   clk;
    reg                   rst_n;
    reg  [DATA_WIDTH-1:0] write_data;
    reg                   write_valid;
    wire                  write_ready;
    wire [DATA_WIDTH-1:0] read_data;
    wire                  read_valid;
    reg                   read_ready;
    wire                  full;
    wire                  empty;

    // Instance thứ hai có một phần tử để kiểm tra trực tiếp DEPTH nhỏ nhất hợp
    // lệ mà không làm giảm phạm vi test quay vòng của DEPTH=3 phía trên.
    reg  [DATA_WIDTH-1:0] one_write_data;
    reg                   one_write_valid;
    wire                  one_write_ready;
    wire [DATA_WIDTH-1:0] one_read_data;
    wire                  one_read_valid;
    reg                   one_read_ready;
    wire                  one_full;
    wire                  one_empty;

    integer error_count;
    integer test_count;

    // Hàng đợi tham chiếu dùng bởi bộ giám sát giao thức.
    reg [DATA_WIDTH-1:0] reference_memory [0:DEPTH-1];
    integer reference_write_pointer;
    integer reference_read_pointer;
    integer reference_occupancy;

    reg [DATA_WIDTH-1:0] stalled_data;
    reg                  was_stalled;

    integer loop_index;

    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .write_data  (write_data),
        .write_valid (write_valid),
        .write_ready (write_ready),
        .read_data   (read_data),
        .read_valid  (read_valid),
        .read_ready  (read_ready),
        .full        (full),
        .empty       (empty)
    );

    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (1)
    ) dut_depth_one (
        .clk         (clk),
        .rst_n       (rst_n),
        .write_data  (one_write_data),
        .write_valid (one_write_valid),
        .write_ready (one_write_ready),
        .read_data   (one_read_data),
        .read_valid  (one_read_valid),
        .read_ready  (one_read_ready),
        .full        (one_full),
        .empty       (one_empty)
    );

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD / 2) begin
        clk = ~clk;
    end

    task report_error;
        input [8*160-1:0] message;
        begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %0s", $time, message);
        end
    endtask

    task check_level;
        input integer expected_occupancy;
        begin
            if (empty !== (expected_occupancy == 0)) begin
                report_error("empty does not match expected occupancy");
            end

            if (full !== (expected_occupancy == DEPTH)) begin
                report_error("full does not match expected occupancy");
            end

            if (rst_n) begin
                if (write_ready !== (expected_occupancy < DEPTH)) begin
                    report_error("write_ready does not match expected occupancy");
                end

                if (read_valid !== (expected_occupancy > 0)) begin
                    report_error("read_valid does not match expected occupancy");
                end
            end
        end
    endtask

    // Hoàn thành một giao dịch ghi ready/valid. Stimulus chỉ đổi tại cạnh xuống,
    // cách xa cạnh lấy mẫu của DUT.
    task write_word;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            write_data  = value;
            write_valid = 1'b1;

            while (write_ready !== 1'b1) begin
                @(negedge clk);
            end

            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
        end
    endtask

    // Hoàn thành một giao dịch đọc ready/valid. Việc so sánh dữ liệu được thực
    // hiện tập trung bởi bộ giám sát hàng đợi tham chiếu bên dưới.
    task read_word;
        begin
            @(negedge clk);
            read_ready = 1'b1;

            while (read_valid !== 1'b1) begin
                @(negedge clk);
            end

            @(posedge clk);
            @(negedge clk);
            read_ready = 1'b0;
        end
    endtask

    task simultaneous_write_read;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            write_data  = value;
            write_valid = 1'b1;
            read_ready  = 1'b1;

            if (write_ready !== 1'b1) begin
                report_error("simultaneous test expected write_ready high");
            end

            if (read_valid !== 1'b1) begin
                report_error("simultaneous test expected read_valid high");
            end

            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            read_ready  = 1'b0;
        end
    endtask

    task write_one_word;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            one_write_data  = value;
            one_write_valid = 1'b1;

            while (one_write_ready !== 1'b1) begin
                @(negedge clk);
            end

            @(posedge clk);
            @(negedge clk);
            one_write_valid = 1'b0;
        end
    endtask

    task read_one_word;
        input [DATA_WIDTH-1:0] expected_value;
        begin
            @(negedge clk);
            one_read_ready = 1'b1;

            while (one_read_valid !== 1'b1) begin
                @(negedge clk);
            end

            if (one_read_data !== expected_value) begin
                report_error("DEPTH=1 returned data out of order");
            end

            @(posedge clk);
            @(negedge clk);
            one_read_ready = 1'b0;
        end
    endtask

    // Scoreboard mức giao dịch độc lập, lấy mẫu cùng giá trị ready/valid mà DUT
    // nhìn thấy tại mỗi cạnh lên.
    always @(posedge clk) begin
        if (!rst_n) begin
            reference_write_pointer = 0;
            reference_read_pointer  = 0;
            reference_occupancy     = 0;
        end else begin
            if (read_valid && read_ready) begin
                if (reference_occupancy <= 0) begin
                    report_error("DUT accepted a read while reference FIFO was empty");
                end else if (
                    read_data !== reference_memory[reference_read_pointer]
                ) begin
                    $display(
                        "[%0t] ERROR: FIFO ordering expected=0x%02h actual=0x%02h",
                        $time,
                        reference_memory[reference_read_pointer],
                        read_data
                    );
                    error_count = error_count + 1;
                end

                if (reference_read_pointer == DEPTH - 1) begin
                    reference_read_pointer = 0;
                end else begin
                    reference_read_pointer = reference_read_pointer + 1;
                end
            end

            if (write_valid && write_ready) begin
                if (reference_occupancy >= DEPTH) begin
                    report_error("DUT accepted a write while reference FIFO was full");
                end

                reference_memory[reference_write_pointer] = write_data;

                if (reference_write_pointer == DEPTH - 1) begin
                    reference_write_pointer = 0;
                end else begin
                    reference_write_pointer = reference_write_pointer + 1;
                end
            end

            case ({write_valid && write_ready, read_valid && read_ready})
                2'b10: reference_occupancy = reference_occupancy + 1;
                2'b01: reference_occupancy = reference_occupancy - 1;
                default: reference_occupancy = reference_occupancy;
            endcase

            if (
                (reference_occupancy < 0) ||
                (reference_occupancy > DEPTH)
            ) begin
                report_error("reference occupancy moved outside legal range");
            end
        end
    end

    // Ready/valid yêu cầu phần tử cũ nhất ổn định trong toàn bộ thời gian phía
    // đọc tạo áp lực ngược.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stalled_data <= {DATA_WIDTH{1'b0}};
            was_stalled  <= 1'b0;
        end else begin
            if (was_stalled) begin
                if (read_valid !== 1'b1) begin
                    report_error("read_valid dropped while the output was stalled");
                end

                if (read_data !== stalled_data) begin
                    report_error("read_data changed while the output was stalled");
                end
            end

            was_stalled <= read_valid && !read_ready;

            if (read_valid && !read_ready) begin
                stalled_data <= read_data;
            end
        end
    end

    initial begin
        $timeformat(-9, 0, " ns", 12);

        rst_n       = 1'b0;
        write_data  = {DATA_WIDTH{1'b0}};
        write_valid = 1'b1;
        read_ready  = 1'b1;
        one_write_data  = {DATA_WIDTH{1'b0}};
        one_write_valid = 1'b1;
        one_read_ready  = 1'b1;
        error_count = 0;
        test_count  = 0;

        // --------------------------------------------------------------------
        // TEST 1: reset và khóa bắt tay trong reset.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: reset and interface gating", test_count);

        #1;
        if (write_ready !== 1'b0) begin
            report_error("write_ready must be low during reset");
        end

        if (read_valid !== 1'b0) begin
            report_error("read_valid must be low during reset");
        end

        if (one_write_ready !== 1'b0 || one_read_valid !== 1'b0) begin
            report_error("DEPTH=1 ready/valid outputs were not gated by reset");
        end

        if (full !== 1'b0 || empty !== 1'b1) begin
            report_error("full/empty state is incorrect during reset");
        end

        repeat (3) begin
            @(posedge clk);
        end

        @(negedge clk);
        write_valid = 1'b0;
        read_ready  = 1'b0;
        one_write_valid = 1'b0;
        one_read_ready  = 1'b0;
        rst_n       = 1'b1;

        #1;
        check_level(0);

        // --------------------------------------------------------------------
        // TEST 2: thứ tự dữ liệu cơ bản.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: FIFO ordering", test_count);

        write_word(8'h11);
        write_word(8'h22);
        write_word(8'h33);
        check_level(3);

        read_word();
        read_word();
        read_word();
        check_level(0);

        // --------------------------------------------------------------------
        // TEST 3: báo đầy và áp lực ngược phía ghi.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: full and write backpressure", test_count);

        write_word(8'hA1);
        write_word(8'hA2);
        write_word(8'hA3);
        check_level(3);

        @(negedge clk);
        write_data  = 8'hA4;
        write_valid = 1'b1;

        repeat (3) begin
            @(posedge clk);
            if (write_ready !== 1'b0) begin
                report_error("write_ready asserted while FIFO was full");
            end
        end

        @(negedge clk);
        write_valid = 1'b0;
        check_level(3);

        read_word();
        write_word(8'hA4);
        read_word();
        read_word();
        read_word();
        check_level(0);

        // --------------------------------------------------------------------
        // TEST 4: đầu ra nhìn trước ổn định khi bị áp lực ngược.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: stable show-ahead data while stalled", test_count);

        write_word(8'h41);
        write_word(8'h42);

        if (read_data !== 8'h41) begin
            report_error("show-ahead output did not present the oldest word");
        end

        repeat (3) begin
            @(posedge clk);
        end

        // Ghi phía sau phần tử đầu không được làm đổi đầu ra đang bị giữ.
        write_word(8'h43);

        if (read_data !== 8'h41) begin
            report_error("write behind head changed stalled read_data");
        end

        read_word();
        read_word();
        read_word();
        check_level(0);

        // --------------------------------------------------------------------
        // TEST 5: ghi/đọc đồng thời giữ nguyên mức chứa và thứ tự.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: simultaneous write and read", test_count);

        write_word(8'h51);
        write_word(8'h52);
        check_level(2);

        simultaneous_write_read(8'h53);
        check_level(2);
        simultaneous_write_read(8'h54);
        check_level(2);

        read_word();
        read_word();
        check_level(0);

        // --------------------------------------------------------------------
        // TEST 6: quay vòng nhiều lần với DEPTH=3 không phải lũy thừa của hai.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: DEPTH=3 pointer wraparound", test_count);

        for (loop_index = 0; loop_index < 4; loop_index = loop_index + 1) begin
            write_word(8'h80 + (loop_index * 3));
            write_word(8'h81 + (loop_index * 3));
            write_word(8'h82 + (loop_index * 3));
            check_level(3);

            read_word();
            read_word();
            read_word();
            check_level(0);
        end

        // --------------------------------------------------------------------
        // TEST 7: DEPTH=1 nhỏ nhất hợp lệ.
        // --------------------------------------------------------------------
        test_count = test_count + 1;
        $display("TEST %0d: DEPTH=1 operation", test_count);

        if (
            one_empty !== 1'b1 ||
            one_full !== 1'b0 ||
            one_write_ready !== 1'b1 ||
            one_read_valid !== 1'b0
        ) begin
            report_error("DEPTH=1 did not start empty and writable");
        end

        write_one_word(8'hD1);

        if (
            one_empty !== 1'b0 ||
            one_full !== 1'b1 ||
            one_write_ready !== 1'b0 ||
            one_read_valid !== 1'b1 ||
            one_read_data !== 8'hD1
        ) begin
            report_error("DEPTH=1 did not become full after one write");
        end

        // Giao dịch ghi bị từ chối không được ghi đè phần tử duy nhất đang lưu.
        @(negedge clk);
        one_write_data  = 8'hEE;
        one_write_valid = 1'b1;

        repeat (2) begin
            @(posedge clk);

            if (one_write_ready !== 1'b0) begin
                report_error("DEPTH=1 accepted a write while full");
            end

            if (one_read_data !== 8'hD1) begin
                report_error("DEPTH=1 full backpressure corrupted stored data");
            end
        end

        @(negedge clk);
        one_write_valid = 1'b0;

        read_one_word(8'hD1);

        if (one_empty !== 1'b1 || one_read_valid !== 1'b0) begin
            report_error("DEPTH=1 did not become empty after its read");
        end

        // Dùng lại địa chỉ duy nhất để kiểm tra đường quay vòng con trỏ DEPTH=1.
        write_one_word(8'hD2);
        read_one_word(8'hD2);
        write_one_word(8'hD3);
        read_one_word(8'hD3);

        // Chờ các phép gán không chặn và bộ giám sát cuối cùng ổn định.
        @(posedge clk);
        @(negedge clk);

        if (reference_occupancy !== 0) begin
            report_error("reference FIFO was not empty at end of test");
        end

        if (error_count == 0) begin
            $display(
                "TEST_RESULT: PASS: tb_sync_fifo (tests=%0d depth=%0d)",
                test_count,
                DEPTH
            );
        end else begin
            $display(
                "TEST_RESULT: FAIL: tb_sync_fifo (errors=%0d tests=%0d depth=%0d)",
                error_count,
                test_count,
                DEPTH
            );
        end

        $finish;
    end

    initial begin
        #1_000_000;
        $display("TEST_RESULT: FAIL: tb_sync_fifo (timeout)");
        $finish;
    end

endmodule

`default_nettype wire
