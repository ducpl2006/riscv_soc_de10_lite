`timescale 1ns/1ps
// ============================================================================
// tb_CORE_i2c — full-chip: CPU chạy firmware.hex, i2c_boot_test() ghi 2 byte
// (0xA5, 0x3C) tới slave 0x50 qua CPU→AXI→APB→I2C. Slave hành vi bắt byte và
// kiểm chứng. Chứng minh toàn tuyến firmware-driven I2C hoạt động (bước 16).
// ============================================================================
module tb_CORE_i2c;

    reg          clk = 0;
    reg          reset;               // active-low (design dùng !reset)
    reg  [9:0]   SW = 10'h000;
    reg          GPIO_0 = 1'b1;       // UART RX idle
    wire         GPIO_1;              // UART TX
    wire [9:0]   LEDR;
    wire [6:0]   HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;
    wire         VGA_HS, VGA_VS;
    wire [3:0]   VGA_R, VGA_G, VGA_B;
    wire         I2C_SCL, I2C_SDA;

    integer errors = 0;

    always #10 clk = ~clk;            // 50 MHz

    pullup(I2C_SCL); pullup(I2C_SDA);

    CORE dut (
        .clk(clk), .reset(reset),
        .SW(SW), .GPIO_0(GPIO_0),
        .LEDR(LEDR),
        .HEX0(HEX0),.HEX1(HEX1),.HEX2(HEX2),.HEX3(HEX3),.HEX4(HEX4),.HEX5(HEX5),
        .GPIO_1(GPIO_1),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .I2C_SCL(I2C_SCL), .I2C_SDA(I2C_SDA));

    // ---- Behavioral I2C slave @ 0x50 (raw pad, address-aware, ACK) ----
    localparam [6:0] SADDR = 7'h50;
    wire scl_f = I2C_SCL, sda_f = I2C_SDA;
    reg  in_txn=0, addr_match=0, sl_low=0;
    reg [3:0] fcnt=0, byte_idx=0;
    reg [7:0] recv_sh=0;
    integer   cap_ptr=0;
    reg [7:0] captured [0:7];

    assign I2C_SDA = (in_txn && sl_low) ? 1'b0 : 1'bz;

    always @(sda_f) if (scl_f) begin
        if (~sda_f) begin in_txn<=1; fcnt<=0; byte_idx<=0; recv_sh<=0; end
        else        begin in_txn<=0; fcnt<=0; byte_idx<=0; end
    end
    always @(posedge scl_f) if (in_txn) recv_sh <= {recv_sh[6:0], sda_f};
    always @(negedge scl_f) begin
        if (in_txn) begin
            sl_low <= (fcnt<8) ? 1'b0 : ((byte_idx==0)?(recv_sh[7:1]==SADDR):1'b1);
            if (fcnt==4'd8) begin
                fcnt<=0; byte_idx<=byte_idx+4'd1;
                if (byte_idx==0) addr_match<=(recv_sh[7:1]==SADDR);
                else begin captured[cap_ptr]<=recv_sh; cap_ptr<=cap_ptr+1; end
            end else fcnt<=fcnt+4'd1;
        end
    end

    // ---- stimulus ----
    initial begin
        reset = 1'b0;                 // assert
        repeat(5) @(negedge clk);
        reset = 1'b1;                 // release -> CPU boots

        // chờ CPU chạy tới i2c_boot_test và slave nhận đủ 2 byte data
        // (byte_idx: 0=address, 1=data0, 2=data1). cap_ptr đếm data đã bắt.
        begin : wait_bytes
            integer g;
            for (g=0; g<2000000; g=g+1) begin
                @(posedge clk);
                if (cap_ptr >= 2) disable wait_bytes;
            end
        end

        if (cap_ptr < 2) begin
            $display("  [ERR] slave chi bat duoc %0d byte (mong 2)", cap_ptr);
            errors = errors + 1;
        end else begin
            if (!addr_match) begin $display("  [ERR] address khong match 0x50"); errors=errors+1; end
            if (captured[0]!==8'hA5) begin $display("  [ERR] byte0=%h expect A5",captured[0]); errors=errors+1; end
            if (captured[1]!==8'h3C) begin $display("  [ERR] byte1=%h expect 3C",captured[1]); errors=errors+1; end
        end

        if (errors==0) $display("PASS: CORE i2c firmware (slave got A5,3C @0x50)");
        else           $display("FAIL: CORE i2c firmware (%0d errors)", errors);
        $finish;
    end

    initial begin #40000000; $display("FAIL: CORE i2c firmware (timeout, cap=%0d)", cap_ptr); $finish; end

endmodule
