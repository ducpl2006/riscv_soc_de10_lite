`timescale 1ns/1ps

// ============================================================================
// Testbench: AXI_TOP
// ----------------------------------------------------------------------------
// + Reset active LOW (match RTL AXI_RAM_Slave / AXI_Interconnect)
// + cpu_write / cpu_read: pulse mem_we / mem_re 1 cycle (giống tb_interconnect_ram đã PASS)
// + Test RAM, GPIO, UART, VGA, invalid address, stress
// ============================================================================

module tb_AXI_TOP;

    // =====================================================
    // CLOCK / RESET
    // =====================================================

    reg clk;
    reg reset;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;      // 100 MHz
    end

    // =====================================================
    // CPU INTERFACE
    // =====================================================

    reg  [31:0] mem_addr;
    reg  [31:0] mem_wdata;
    reg         mem_we;
    reg         mem_re;

    wire [31:0] mem_rdata;
    wire        mem_ready;

    // =====================================================
    // GPIO / UART / VGA
    // =====================================================

    reg  [9:0]  SW;
    reg         UART_RX;

    wire        UART_TX;

    wire [9:0]  LEDR;

    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    wire        VGA_HS, VGA_VS;
    wire [3:0]  VGA_R, VGA_G, VGA_B;

    // =====================================================
    // DUT
    // =====================================================

    AXI_TOP dut (

        .clk        (clk),
        .reset      (reset),

        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_we     (mem_we),
        .mem_re     (mem_re),
        .mem_rdata  (mem_rdata),
        .mem_ready  (mem_ready),

        .SW         (SW),

        .UART_RX    (UART_RX),
        .UART_TX    (UART_TX),

        .LEDR       (LEDR),

        .HEX0       (HEX0),
        .HEX1       (HEX1),
        .HEX2       (HEX2),
        .HEX3       (HEX3),
        .HEX4       (HEX4),
        .HEX5       (HEX5),

        .VGA_HS     (VGA_HS),
        .VGA_VS     (VGA_VS),

        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B)
    );

    // =====================================================
    // TIMEOUT WATCHDOG
    // =====================================================

    initial begin

        #5000000;

        $display("");
        $display("======================================");
        $display("SIMULATION TIMEOUT");
        $display("======================================");

        $finish;

    end

    // =====================================================
    // CPU WRITE TASK
    // Pulse mem_we 1 cycle → tránh re-trigger transaction
    // =====================================================

    task cpu_write;

        input [31:0] addr;
        input [31:0] data;

        begin

            @(posedge clk);

            mem_addr  <= addr;
            mem_wdata <= data;
            mem_we    <= 1'b1;
            mem_re    <= 1'b0;

            @(posedge clk);

            mem_we <= 1'b0;

            wait(mem_ready);

            $display(
                "[WRITE] T=%0t ADDR=%h DATA=%h",
                $time,
                addr,
                data
            );

        end

    endtask

    // =====================================================
    // CPU READ TASK
    // Pulse mem_re 1 cycle → tránh re-trigger transaction
    // =====================================================

    task cpu_read;

        input [31:0] addr;

        begin

            @(posedge clk);

            mem_addr <= addr;
            mem_we   <= 1'b0;
            mem_re   <= 1'b1;

            @(posedge clk);

            mem_re <= 1'b0;

            wait(mem_ready);

            $display(
                "[READ ] T=%0t ADDR=%h DATA=%h",
                $time,
                addr,
                mem_rdata
            );

        end

    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================

    integer i;

    initial begin

        // =============================================
        // INIT
        // =============================================

        mem_addr  = 32'b0;
        mem_wdata = 32'b0;
        mem_we    = 1'b0;
        mem_re    = 1'b0;

        SW        = 10'b0;
        UART_RX   = 1'b1;       // UART idle = HIGH

        // =============================================
        // RESET (active LOW)
        // =============================================

        reset = 1'b0;           // assert

        repeat(10) @(posedge clk);

        reset = 1'b1;           // release

        repeat(10) @(posedge clk);

        $display("");
        $display("======================================");
        $display("START AXI_TOP TEST");
        $display("======================================");

        // =================================================
        // TEST 1 : RAM SINGLE WRITE / READ
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 1 : RAM SINGLE WRITE / READ");
        $display("======================================");

        cpu_write(32'h0000_0000, 32'hDEADBEEF);
        cpu_read (32'h0000_0000);

        // =================================================
        // TEST 2 : RAM MULTI WRITE / READ
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 2 : RAM MULTI WRITE / READ");
        $display("======================================");

        for (i = 0; i < 8; i = i + 1) begin
            cpu_write(
                32'h0000_0100 + (i * 4),
                32'h1000_0000 + i
            );
        end

        for (i = 0; i < 8; i = i + 1) begin
            cpu_read(32'h0000_0100 + (i * 4));
        end

        // =================================================
        // TEST 3 : GPIO READ (SW)
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 3 : GPIO READ SW");
        $display("======================================");

        SW = 10'b1010101010;

        repeat(5) @(posedge clk);

        cpu_read(32'h1000_0000);

        // =================================================
        // TEST 4 : GPIO WRITE (LEDR / HEX)
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 4 : GPIO WRITE LEDR/HEX");
        $display("======================================");

        cpu_write(32'h1000_0004, 32'h0000_03FF);    // LEDR = all on
        cpu_write(32'h1000_0008, 32'h0012_3456);    // HEX data

        repeat(10) @(posedge clk);

        // =================================================
        // TEST 5 : UART WRITE
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 5 : UART WRITE");
        $display("======================================");

        cpu_write(32'h2000_0000, 32'h0000_0041);    // 'A'

        repeat(20) @(posedge clk);

        // =================================================
        // TEST 6 : VGA WRITE
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 6 : VGA WRITE");
        $display("======================================");

        cpu_write(32'h3000_0000, 32'h0000_0041);
        cpu_write(32'h3000_0004, 32'h0000_0042);
        cpu_write(32'h3000_0008, 32'h0000_0043);

        repeat(10) @(posedge clk);

        // =================================================
        // TEST 7 : INVALID ADDRESS WRITE (SLVERR expected)
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 7 : INVALID WRITE");
        $display("======================================");

        cpu_write(32'hF000_0000, 32'h1234_5678);

        repeat(10) @(posedge clk);

        // =================================================
        // TEST 8 : INVALID ADDRESS READ (SLVERR expected)
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 8 : INVALID READ");
        $display("======================================");

        cpu_read(32'hF000_0000);

        repeat(10) @(posedge clk);

        // =================================================
        // TEST 9 : STRESS WRITE/READ ALTERNATE
        // =================================================

        $display("");
        $display("======================================");
        $display("TEST 9 : STRESS TEST");
        $display("======================================");

        for (i = 0; i < 32; i = i + 1) begin

            cpu_write(
                32'h0000_1000 + (i * 4),
                32'hAAAA_0000 + i
            );

            cpu_read(32'h0000_1000 + (i * 4));

        end

        // =================================================
        // FINISH
        // =================================================

        repeat(50) @(posedge clk);

        $display("");
        $display("======================================");
        $display("ALL TESTS FINISHED");
        $display("======================================");

        $finish;

    end

    // =====================================================
    // MONITOR
    // =====================================================

    initial begin
        $monitor(
"T=%0t | RST=%b | READY=%b | WE=%b RE=%b | ADDR=%h | WDATA=%h | RDATA=%h",
            $time,
            reset,
            mem_ready,
            mem_we,
            mem_re,
            mem_addr,
            mem_wdata,
            mem_rdata
        );
    end

endmodule
