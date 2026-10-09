`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench tự kiểm tra cho I2C master byte-oriented.
 *
 * Phạm vi:
 * - MMIO DATA/CMD/STATUS/DIVIDER và báo lỗi địa chỉ.
 * - START, phát 8 bit MSB-first, lấy mẫu ACK, STOP, done sticky/clear.
 * - Đọc 8 bit, phát NACK cuối byte và trả dữ liệu qua thanh ghi DATA.
 * - Ghi CMD mới khi busy phải tạo wait-state, không làm hỏng lệnh đang chạy.
 *
 * Slave tối giản điều khiển SDA theo trạng thái bit của DUT. Việc quan sát START,
 * STOP và thứ tự bit vẫn thực hiện ở mức chân open-drain, không sửa state DUT.
 */
module tb_rv32_i2c_master;

    localparam [7:0] SLAVE_BYTE = 8'hA6;

    reg clk;
    reg rst;
    reg req;
    reg we;
    reg [11:0] addr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire [31:0] rdata;
    wire ready;
    wire err;
    wire scl_drive_low;
    wire sda_drive_low;
    wire busy;
    reg slave_sda_low;

    wire scl = scl_drive_low ? 1'b0 : 1'b1;
    wire sda = (sda_drive_low || slave_sda_low) ? 1'b0 : 1'b1;

    integer checks;
    integer timeout;
    integer rise_count;
    reg [7:0] captured_write;
    reg saw_start;
    reg saw_stop;
    reg old_sda;
    reg old_scl;

    soc_i2c_master #(.CLOCK_HZ(100), .I2C_HZ(10)) dut (
        .clk_i(clk), .rst_i(rst), .req_i(req), .we_i(we),
        .addr_i(addr), .wdata_i(wdata), .wstrb_i(wstrb),
        .rdata_o(rdata), .ready_o(ready), .err_o(err),
        .scl_i(scl), .sda_i(sda),
        .scl_drive_low_o(scl_drive_low),
        .sda_drive_low_o(sda_drive_low), .busy_o(busy)
    );

    always #5 clk = ~clk;

    // Mô hình slave: ACK cho write; cấp từng bit cho read.
    always @* begin
        slave_sda_low = 1'b0;
        if (busy && !dut.command_read_q &&
            ((dut.state_q == 4'd5) || (dut.state_q == 4'd6)))
            slave_sda_low = 1'b1;
        else if (busy && dut.command_read_q &&
                 ((dut.state_q == 4'd3) || (dut.state_q == 4'd4)))
            slave_sda_low = !SLAVE_BYTE[dut.bit_index_q];
    end

    // Monitor độc lập các chuyển mức bus nhìn thấy ở chân.
    always @(posedge clk) begin
        old_sda <= sda;
        old_scl <= scl;
        if (old_sda && !sda && scl)
            saw_start <= 1'b1;
        if (!old_sda && sda && scl)
            saw_stop <= 1'b1;
        if (!old_scl && scl && busy && !dut.command_read_q && rise_count < 8) begin
            captured_write <= {captured_write[6:0], sda};
            rise_count <= rise_count + 1;
        end
    end

    task mmio_write;
        input [11:0] register_address;
        input [31:0] value;
        begin
            @(negedge clk);
            req = 1'b1; we = 1'b1; addr = register_address;
            wdata = value; wstrb = 4'b0001;
            while (!ready) @(negedge clk);
            @(negedge clk);
            req = 1'b0; we = 1'b0;
        end
    endtask

    task mmio_read;
        input [11:0] register_address;
        output [31:0] value;
        begin
            @(negedge clk);
            req = 1'b1; we = 1'b0; addr = register_address;
            while (!ready) @(negedge clk);
            value = rdata;
            @(negedge clk);
            req = 1'b0;
        end
    endtask

    task wait_done;
        begin
            timeout = 0;
            while (busy && timeout < 300) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 300)
                $fatal(1, "I2C timeout");
        end
    endtask

    reg [31:0] value_read;
    initial begin
        clk = 0; rst = 1; req = 0; we = 0; addr = 0;
        wdata = 0; wstrb = 0; checks = 0; rise_count = 0;
        captured_write = 0; saw_start = 0; saw_stop = 0;
        old_sda = 1; old_scl = 1;
        repeat (3) @(posedge clk);
        rst = 0;

        mmio_read(4'hC, value_read);
        if (value_read !== 32'd5) $fatal(1, "Sai HALF_DIV");
        checks = checks + 1;

        // DATA=0xA5; CMD execute+start+stop.
        mmio_write(4'h0, 32'hA5);
        mmio_write(4'h4, 32'h83);

        // CMD trong khi busy phải giữ ready=0.
        @(negedge clk);
        req = 1; we = 1; addr = 4'h4; wdata = 32'h80; wstrb = 1;
        if (ready !== 1'b0) $fatal(1, "CMD busy khong tao wait-state");
        checks = checks + 1;
        req = 0; we = 0;

        wait_done();
        if (!saw_start || !saw_stop || captured_write !== 8'hA5)
            $fatal(1, "Sai waveform write: start=%b stop=%b data=%02x",
                   saw_start, saw_stop, captured_write);
        checks = checks + 3;
        mmio_read(4'h8, value_read);
        if (value_read[2:0] !== 3'b010)
            $fatal(1, "Sai STATUS sau write: %08x", value_read);
        checks = checks + 1;

        // Clear done, rồi đọc một byte và phát NACK+STOP.
        mmio_write(4'h4, 32'h10);
        mmio_read(4'h8, value_read);
        if (value_read[1] !== 1'b0) $fatal(1, "CLEAR_DONE that bai");
        checks = checks + 1;
        saw_start = 0; saw_stop = 0;
        mmio_write(4'h4, 32'h8F);
        wait_done();
        mmio_read(4'h0, value_read);
        if (value_read[7:0] !== SLAVE_BYTE)
            $fatal(1, "Sai du lieu read: %02x", value_read[7:0]);
        if (!saw_start || !saw_stop)
            $fatal(1, "Read thieu START/STOP");
        checks = checks + 3;

        // Truy cập địa chỉ không ánh xạ phải báo err tức thời.
        @(negedge clk);
        req = 1; we = 0; addr = 4'h2;
        #1;
        if (!err || !ready) $fatal(1, "Dia chi MMIO loi phai tra ready+err");
        checks = checks + 1;
        req = 0;

        $display("PASS tb_rv32_i2c_master: %0d checks", checks);
        $finish;
    end

endmodule

`default_nettype wire
