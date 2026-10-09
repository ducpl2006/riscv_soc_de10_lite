`timescale 1ns/1ps
`default_nettype none

// Target model uses only SCL/SDA edges, never the master's FSM or bit counter.
module tb_rv32_i2c_transactions #(
    parameter integer HALF_DIV = 5,
    // Mặc định mô phỏng hai tầng FF đầu vào giống lớp board DE10-Lite.
    parameter integer SYNC_INPUTS = 1
);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, req = 0, we = 0;
    reg [11:0] addr=0;
    reg [3:0] strb=0;
    reg [31:0] data = 0;
    wire [31:0] rdata;
    wire ready, err, busy, scl_low, sda_low;
    reg target_scl_low = 0, target_sda_low = 0;
    wire scl = !(scl_low || target_scl_low);
    wire sda = !(sda_low || target_sda_low);
    reg [1:0] pins_meta = 2'b11, pins_sync = 2'b11;
    always @(posedge clk) begin
        if (rst) begin pins_meta <= 2'b11; pins_sync <= 2'b11; end
        else begin pins_meta <= {scl, sda}; pins_sync <= pins_meta; end
    end
    integer starts = 0, stops = 0;
    time high_start;
    reg check_high = 0;

    soc_i2c_master #(.CLOCK_HZ(HALF_DIV*20), .I2C_HZ(10)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we), .addr_i(addr),
        .wdata_i(data), .wstrb_i(strb), .rdata_o(rdata), .ready_o(ready),
        .err_o(err), .scl_i(SYNC_INPUTS ? pins_sync[1] : scl),
        .sda_i(SYNC_INPUTS ? pins_sync[0] : sda), .scl_drive_low_o(scl_low),
        .sda_drive_low_o(sda_low), .busy_o(busy));

    always @(negedge sda) if (scl && !rst) starts = starts + 1;
    always @(posedge sda) if (scl && !rst) stops = stops + 1;
    always @(posedge scl) begin high_start = $time; check_high = !rst; end
    always @(negedge scl)
        if (check_high && !rst && $time - high_start < HALF_DIV*10)
            $fatal(1, "I2C high phase shortened after stretching: %0t", $time - high_start);

    task write_reg;
        input [11:0] offset;
        input [31:0] value;
        begin
            @(negedge clk); req = 1; we = 1; addr = offset; data = value; strb = 1;
            #1;
            while (!ready) begin @(negedge clk); #1; end
            if (err) $fatal(1, "I2C MMIO write error");
            @(negedge clk); req = 0; we = 0;
        end
    endtask

    task wait_complete;
        begin
            wait (!busy);
            @(negedge clk); req = 1; we = 0; addr = 8; #1;
            if (!ready || err || !rdata[1]) $fatal(1, "I2C completion/status");
            @(negedge clk); req = 0;
        end
    endtask

    task wait_start;
        begin : wait_start_loop
            forever begin
                @(negedge sda);
                if (scl) disable wait_start_loop;
            end
        end
    endtask

    task stretch;
        begin
            target_scl_low = 1;
            repeat (17) @(negedge clk);
            if (!busy) $fatal(1, "I2C completed while SCL stretched");
            target_scl_low = 0;
        end
    endtask

    task receive_byte;
        input has_start;
        input [7:0] expected;
        input nack;
        input integer stretch_phase; // 1=data, 2=ACK, 3=STOP
        integer bit_number;
        reg [7:0] received;
        begin
            if (has_start) begin wait_start(); @(negedge scl); end
            else wait (busy);
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                if (stretch_phase == 1 && bit_number == 4) stretch();
                @(posedge scl); received[bit_number] = sda;
                @(negedge scl);
            end
            target_sda_low = !nack;
            if (stretch_phase == 2) stretch();
            @(posedge scl);
            @(negedge scl); target_sda_low = 0;
            if (received !== expected) $fatal(1, "I2C sent %h expected %h", received, expected);
            if (stretch_phase == 3) stretch();
        end
    endtask

    task transmit_byte;
        input has_start;
        input [7:0] value;
        input expected_nack;
        integer bit_number;
        begin
            if (has_start) begin wait_start(); @(negedge scl); end
            else wait (busy);
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                target_sda_low = !value[bit_number];
                @(posedge scl);
                @(negedge scl);
            end
            target_sda_low = 0;
            stretch();
            @(posedge scl);
            if (sda !== expected_nack) $fatal(1, "I2C controller ACK/NACK");
            @(negedge scl);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst = 0;
        // Write address + register pointer without STOP, then repeated START/read.
        write_reg(0, 32'h80);
        fork
            receive_byte(1, 8'h80, 0, 1);
            write_reg(4, 32'h81);
        join
        wait_complete();
        repeat (15) @(negedge clk);
        if (scl || !sda || stops != 0) $fatal(1, "I2C did not retain bus between bytes");
        write_reg(0, 32'h02);
        fork
            receive_byte(0, 8'h02, 0, 2);
            write_reg(4, 32'h80);
        join
        wait_complete();
        write_reg(0, 32'h81);
        fork
            receive_byte(1, 8'h81, 0, 0);
            write_reg(4, 32'h81);
        join
        wait_complete();
        fork
            transmit_byte(0, 8'hA6, 0);
            write_reg(4, 32'h84);
        join
        wait_complete();
        req = 1; addr = 0; #1;
        if (rdata !== 32'hA6) $fatal(1, "I2C first RX byte");
        req = 0;
        fork
            transmit_byte(0, 8'h39, 1);
            write_reg(4, 32'h8E);
        join
        wait_complete();
        req = 1; addr = 0; #1;
        if (rdata !== 32'h39 || starts != 2 || stops != 1 || !scl || !sda)
            $fatal(1, "I2C combined transaction: starts=%0d stops=%0d data=%h", starts, stops, rdata);
        req = 0;
        // Stretch STOP and return target NACK to software.
        write_reg(0, 32'h55);
        fork
            receive_byte(1, 8'h55, 1, 3);
            write_reg(4, 32'h83);
        join
        wait_complete();
        req = 1; addr = 8; #1;
        if (rdata[2:0] !== 3'b110) $fatal(1, "I2C NACK status");
        req = 0;
        // START cannot occur while a target holds SCL low. Reset releases bus.
        target_scl_low = 1;
        write_reg(4, 32'h83);
        repeat (20) @(negedge clk);
        if (!busy || sda_low) $fatal(1, "I2C START ignored stretched SCL");
        req = 1; we = 1; addr = 0; strb = 1; #1;
        if (ready || err) $fatal(1, "I2C DATA write must wait while busy");
        addr = 8; #1;
        if (!ready || !err) $fatal(1, "I2C error while busy must terminate");
        rst = 1;
        @(negedge clk); target_scl_low = 0; #1;
        if (busy || scl_low || sda_low || ready || err) $fatal(1, "I2C reset abort");
        $display("PASS tb_rv32_i2c_transactions: pin-level multi-byte/repeated START, ACK/NACK, stretching, reset");
        $finish;
    end
    initial begin #100000; $fatal(1, "I2C transaction timeout"); end
endmodule

`default_nettype wire
