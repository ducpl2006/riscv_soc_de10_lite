`timescale 1ns/1ps
// ============================================================================
// tb_APB4_TOP — verify ROUTING sau khi gắn I2C vào APB4_Interconnect + APB4_TOP.
// Không test lại chức năng nội bộ từng slave (đã verify riêng). Chỉ kiểm tra
// địa chỉ được định tuyến đúng slave và return-path MUX chọn đúng:
//   - 0x1000_0000 GPIO : write LEDR + read-back, read SW
//   - 0x4000_0000 I2C  : read VERSION = 0x0001_0000
//   - 0x5000_0000 miss : PREADY=1 + PSLVERR=1
// ============================================================================
module tb_APB4_TOP;

    reg          clk = 0;
    reg          reset;

    reg  [31:0]  PADDR;
    reg          PSEL, PENABLE, PWRITE;
    reg  [31:0]  PWDATA;
    reg  [3:0]   PSTRB;
    reg  [2:0]   PPROT;
    wire [31:0]  PRDATA;
    wire         PREADY, PSLVERR;

    reg  [9:0]   SW;
    wire [9:0]   LEDR;
    wire [6:0]   HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;
    reg          UART_RX = 1'b1;
    wire         UART_TX;
    wire         I2C_SCL, I2C_SDA;
    wire         i2c_irq;

    integer errors = 0;

    always #5 clk = ~clk;

    // pull-up cho I2C open-drain (không có slave, chỉ cần đọc VERSION)
    pullup(I2C_SCL); pullup(I2C_SDA);

    APB4_TOP dut (
        .clk(clk), .reset(reset),
        .PADDR(PADDR), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PPROT(PPROT),
        .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
        .SW(SW), .LEDR(LEDR),
        .HEX0(HEX0),.HEX1(HEX1),.HEX2(HEX2),.HEX3(HEX3),.HEX4(HEX4),.HEX5(HEX5),
        .UART_RX(UART_RX), .UART_TX(UART_TX),
        .I2C_SCL(I2C_SCL), .I2C_SDA(I2C_SDA), .i2c_irq(i2c_irq));

    task apb_write(input [31:0] a, input [31:0] d); begin
        @(negedge clk); PADDR=a; PWDATA=d; PWRITE=1; PSTRB=4'hF; PSEL=1; PENABLE=0;
        @(negedge clk); PENABLE=1;
        wait (PREADY);
        @(negedge clk); PSEL=0; PENABLE=0; PWRITE=0;
    end endtask

    task apb_read(input [31:0] a, output [31:0] d, output err); begin
        @(negedge clk); PADDR=a; PWRITE=0; PSEL=1; PENABLE=0;
        @(negedge clk); PENABLE=1;
        wait (PREADY);
        #1;
        d   = PRDATA;
        err = PSLVERR;
        @(negedge clk); PSEL=0; PENABLE=0;
    end endtask

    reg [31:0] d; reg err;
    initial begin
        reset=0; PADDR=0; PSEL=0; PENABLE=0; PWRITE=0; PWDATA=0; PSTRB=4'hF; PPROT=0; SW=10'h155;
        #23 reset=1; repeat(2) @(negedge clk);

        // ---- GPIO routing: write LEDR, read back ----
        apb_write(32'h1000_0000, 32'h0000_02AA);
        apb_read (32'h1000_0000, d, err);
        if (d[9:0]!==10'h2AA || err) begin $display("  [ERR] GPIO LEDR rb=%h err=%b",d,err); errors=errors+1; end

        // ---- GPIO SW read ----
        apb_read (32'h1000_000C, d, err);
        if (d[9:0]!==10'h155 || err) begin $display("  [ERR] GPIO SW=%h err=%b",d,err); errors=errors+1; end

        // ---- I2C routing: VERSION ----
        apb_read (32'h4000_0000, d, err);
        if (d!==32'h0001_0000 || err) begin $display("  [ERR] I2C VERSION=%h err=%b",d,err); errors=errors+1; end

        // ---- I2C RW reg (PRESCALE) qua top ----
        apb_write(32'h4000_0010, 32'h0000_0007);
        apb_read (32'h4000_0010, d, err);
        if (d[15:0]!==16'h0007 || err) begin $display("  [ERR] I2C PRESCALE=%h err=%b",d,err); errors=errors+1; end

        // ---- address miss ----
        apb_read (32'h5000_0000, d, err);
        if (!err) begin $display("  [ERR] miss khong bao PSLVERR"); errors=errors+1; end

        if (errors==0) $display("PASS: APB4_TOP routing");
        else           $display("FAIL: APB4_TOP routing (%0d errors)", errors);
        $finish;
    end

    initial begin #200000; $display("FAIL: APB4_TOP (timeout)"); $finish; end

endmodule
