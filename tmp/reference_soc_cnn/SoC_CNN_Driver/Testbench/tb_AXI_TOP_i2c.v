`timescale 1ns/1ps
// ============================================================================
// tb_AXI_TOP_i2c — verify đường CPU → AXI_Manager → AXI_Interconnect →
// AXI_to_APB4_Bridge → APB4_Interconnect → APB4_I2C_Slave (bước 15).
// Chỉ kiểm tra ĐỊNH TUYẾN tới I2C ở mức toàn SoC (đọc VERSION, RW PRESCALE).
// Không test lại giao thức I2C (đã verify riêng).
// ============================================================================
module tb_AXI_TOP_i2c;

    reg          clk = 0;
    reg          reset;
    reg  [31:0]  mem_addr, mem_wdata;
    reg  [3:0]   mem_wstrb;
    reg          mem_we, mem_re;
    wire [31:0]  mem_rdata;
    wire         mem_ready;

    reg  [9:0]   SW = 10'h0;
    reg          UART_RX = 1'b1;
    wire         UART_TX;
    wire [9:0]   LEDR;
    wire [6:0]   HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;
    wire         VGA_HS, VGA_VS;
    wire [3:0]   VGA_R, VGA_G, VGA_B;
    wire         I2C_SCL, I2C_SDA;
    wire         i2c_irq;

    integer errors = 0;

    always #5 clk = ~clk;
    pullup(I2C_SCL); pullup(I2C_SDA);

    AXI_TOP dut (
        .clk(clk), .reset(reset),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .SW(SW), .UART_RX(UART_RX), .UART_TX(UART_TX), .LEDR(LEDR),
        .HEX0(HEX0),.HEX1(HEX1),.HEX2(HEX2),.HEX3(HEX3),.HEX4(HEX4),.HEX5(HEX5),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .I2C_SCL(I2C_SCL), .I2C_SDA(I2C_SDA), .i2c_irq(i2c_irq));

    task cpu_write(input [31:0] a, input [31:0] d); begin
        @(negedge clk); mem_addr=a; mem_wdata=d; mem_wstrb=4'hF; mem_we=1;
        wait (mem_ready);
        @(negedge clk); mem_we=0;
    end endtask

    task cpu_read(input [31:0] a, output [31:0] d); begin
        @(negedge clk); mem_addr=a; mem_re=1;
        wait (mem_ready);
        d = mem_rdata;
        @(negedge clk); mem_re=0;
    end endtask

    reg [31:0] d;
    initial begin
        reset=0; mem_addr=0; mem_wdata=0; mem_wstrb=0; mem_we=0; mem_re=0;
        #23 reset=1; repeat(2) @(negedge clk);

        // I2C VERSION qua toàn SoC
        cpu_read(32'h4000_0000, d);
        if (d!==32'h0001_0000) begin $display("  [ERR] I2C VERSION=%h expect 00010000",d); errors=errors+1; end

        // I2C PRESCALE RW
        cpu_write(32'h4000_0010, 32'h0000_0007);
        cpu_read (32'h4000_0010, d);
        if (d[15:0]!==16'h0007) begin $display("  [ERR] I2C PRESCALE=%h expect 7",d); errors=errors+1; end

        // I2C ADDRESS RW
        cpu_write(32'h4000_0014, 32'h0000_0050);
        cpu_read (32'h4000_0014, d);
        if (d[9:0]!==10'h050) begin $display("  [ERR] I2C ADDRESS=%h expect 050",d); errors=errors+1; end

        // Sanity: GPIO vẫn định tuyến đúng (write/read LEDR)
        cpu_write(32'h1000_0000, 32'h0000_02AA);
        cpu_read (32'h1000_0000, d);
        if (d[9:0]!==10'h2AA) begin $display("  [ERR] GPIO LEDR=%h expect 2AA",d); errors=errors+1; end

        if (errors==0) $display("PASS: AXI_TOP i2c routing");
        else           $display("FAIL: AXI_TOP i2c routing (%0d errors)", errors);
        $finish;
    end

    initial begin #500000; $display("FAIL: AXI_TOP i2c (timeout)"); $finish; end

endmodule
