`timescale 1ns/1ps
`default_nettype none

module tb_rv32_i2c_recovery #(
    parameter integer HALF_DIV = 5,
    parameter integer SYNC_INPUTS = 1
);
    localparam integer WATCHDOG = 48;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, req=0, we=0;
    reg [11:0] addr=0;
    reg [3:0] strb=1;
    reg [31:0] data=0;
    wire [31:0] rdata;
    wire ready, err, busy, scl_low, sda_low;
    reg target_scl_low=0, target_sda_low=0;
    wire scl=!(scl_low || target_scl_low);
    wire sda=!(sda_low || target_sda_low);
    reg [1:0] scl_sync=3, sda_sync=3;
    integer cycles, pulses=0, release_after=0;
    reg monitor=0;
    reg [31:0] status;
    always @(posedge clk) begin
        scl_sync <= {scl_sync[0], scl};
        sda_sync <= {sda_sync[0], sda};
    end
    // Target chỉ nhả SDA sau số cạnh SCL thật đã chọn, không xem state DUT.
    always @(posedge scl) if (monitor) begin
        pulses=pulses+1;
        if (release_after != 0 && pulses == release_after) target_sda_low=0;
    end

    soc_i2c_master #(.CLOCK_HZ(HALF_DIV*20), .I2C_HZ(10), .TIMEOUT_CYCLES(WATCHDOG)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we), .addr_i(addr),
        .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata), .ready_o(ready), .err_o(err),
        .scl_i(SYNC_INPUTS ? scl_sync[1] : scl), .sda_i(SYNC_INPUTS ? sda_sync[1] : sda),
        .scl_drive_low_o(scl_low), .sda_drive_low_o(sda_low), .busy_o(busy));

    task write_reg;
        input [11:0] offset;
        input [31:0] value;
        input [3:0] mask;
        begin
            @(negedge clk); req=1; we=1; addr=offset; data=value; strb=mask;
            #1;
            while (!ready) begin @(negedge clk); #1; end
            if (err) $fatal(1, "I2C unexpected write error");
            @(negedge clk); req=0; we=0;
        end
    endtask
    task read_status;
        begin
            @(negedge clk); req=1; we=0; addr=8; #1;
            if (!ready || err) $fatal(1, "I2C status must not wait");
            status=rdata;
            @(negedge clk); req=0;
        end
    endtask
    task wait_idle;
        begin
            cycles=0;
            while (busy && cycles<1000) begin @(negedge clk); cycles=cycles+1; end
            if (busy) $fatal(1, "I2C failed to finish within bounded time");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst=0;
        write_reg(0, 32'h5A, 1);
        target_scl_low=1;
        write_reg(4, 32'h83, 1);
        // DATA pending phải hoàn tất bằng fault khi lệnh cũ timeout; không ghi muộn.
        @(negedge clk); req=1; we=1; addr=0; data=32'hA5; strb=1;
        #1;
        if (ready) $fatal(1, "I2C pending DATA did not wait");
        cycles=0;
        while (!ready && cycles<WATCHDOG+10) begin @(negedge clk); #1; cycles=cycles+1; end
        if (!ready || !err) $fatal(1, "I2C timeout must fault pending write");
        @(negedge clk); req=0; we=0;
        if (dut.tx_data_q !== 8'h5A || busy || scl_low || sda_low)
            $fatal(1, "I2C timeout must abort and preserve unaccepted DATA");
        read_status();
        if (status[4:0] !== 5'b01110) $fatal(1, "I2C timeout status %h", status);
        write_reg(4, 32'h40, 0);
        write_reg(4, 32'h40, 14);
        read_status();
        if (!status[3]) $fatal(1, "I2C wrong strobes cleared timeout");
        write_reg(4, 32'h50, 1);
        read_status();
        if (status !== 0) $fatal(1, "I2C clear errors/done");

        // Chờ SDA trước START cũng có deadline; CMD pending không được chạy muộn.
        target_scl_low=0; target_sda_low=1;
        repeat (4) @(negedge clk);
        write_reg(4, 32'h83, 1);
        @(negedge clk); req=1; we=1; addr=4; data=32'h83; strb=1;
        #1; cycles=0;
        while (!ready && cycles<WATCHDOG+10) begin @(negedge clk); #1; cycles=cycles+1; end
        if (!ready || !err) $fatal(1, "I2C SDA timeout must fault pending CMD");
        @(negedge clk); req=0; we=0;
        repeat (4) @(negedge clk);
        if (busy || scl_low || sda_low) $fatal(1, "I2C faulted CMD executed late");
        read_status();
        if (status[4:0] !== 5'b01110) $fatal(1, "I2C SDA timeout flags");

        // RECOVER trong khi SCL kẹt phải lỗi, không báo đã khôi phục bus.
        target_scl_low=1; target_sda_low=0;
        write_reg(4, 32'h20, 1);
        wait_idle(); read_status();
        if (status[4:0] !== 5'b11110 || scl_low || sda_low)
            $fatal(1, "I2C stuck SCL recovery falsely succeeded: %h", status);
        target_scl_low=0; target_sda_low=1;
        repeat (4) @(negedge clk);
        monitor=1; pulses=0; release_after=3;
        write_reg(4, 32'h60, 1); // clear lỗi + recovery
        wait_idle(); monitor=0; read_status();
        if (status !== 2 || !scl || !sda || pulses != 4)
            $fatal(1, "I2C recovery release after 3 pulses + STOP: status=%h pulses=%0d", status, pulses);

        // Không nhả SDA: dừng sau đúng 9 xung, hai output được nhả.
        target_sda_low=1; monitor=1; pulses=0; release_after=0;
        write_reg(4, 32'h60, 1);
        wait_idle(); monitor=0; read_status();
        if (pulses != 9 || status[4:0] !== 5'b10110 || scl_low || sda_low)
            $fatal(1, "I2C permanent SDA recovery: status=%h pulses=%0d", status, pulses);

        // Lệnh START chờ SDA có thể bị RECOVER thay thế ngay, không đợi timeout.
        write_reg(4, 32'hC1, 1);
        if (!busy) $fatal(1, "I2C START did not begin");
        monitor=1; pulses=0; release_after=2;
        write_reg(4, 32'h60, 1);
        wait_idle(); monitor=0; read_status();
        if (status !== 2 || pulses != 3) $fatal(1, "I2C recovery preemption");

        // Stretch ngắn hợp lệ; tổng thời gian byte lớn hơn WATCHDOG không được timeout.
        target_scl_low=1;
        write_reg(4, 32'hCF, 1); // clear errors + read/start/nack/stop
        repeat (12) @(negedge clk); target_scl_low=0;
        wait_idle(); read_status();
        if (status !== 2) $fatal(1, "I2C false timeout on legal stretch: %h", status);
        // Không STOP: khoảng phần mềm giữ SCL thấp không phải clock stretching.
        write_reg(4, 32'h8C, 1);
        wait_idle(); repeat (WATCHDOG+10) @(negedge clk); read_status();
        if (status !== 2 || !scl_low) $fatal(1, "I2C false timeout between bytes");
        write_reg(4, 32'h20, 1);
        @(negedge clk); rst=1; req=1; we=1; #1;
        if (ready || err) $fatal(1, "I2C reset handshake");
        @(negedge clk); req=0; rst=0;
        if (busy || scl_low || sda_low) $fatal(1, "I2C reset during recovery");
        read_status();
        if (status !== 0) $fatal(1, "I2C reset flags");
        $display("PASS tb_rv32_i2c_recovery: timeout, fault pending write, 9-pulse limit, SCL check, strobes, reset");
        $finish;
    end
    initial begin #200000; $fatal(1, "I2C recovery test timeout"); end
endmodule
`default_nettype wire
