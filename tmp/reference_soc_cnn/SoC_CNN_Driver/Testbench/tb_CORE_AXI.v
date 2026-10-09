`timescale 1ns / 1ps

module tb_CORE_AXI;

    // =========================================================
    // CLOCK / RESET
    // =========================================================
    reg clk;
    reg reset;

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;     // 50MHz
    end

    initial begin
        reset = 1'b0;

        #100;
        reset = 1'b1;
    end

    // =========================================================
    // INPUTS
    // =========================================================
    reg [9:0] SW;
    reg GPIO_0;

    // =========================================================
    // OUTPUTS
    // =========================================================
    wire [9:0] LEDR;

    wire [6:0] HEX0;
    wire [6:0] HEX1;
    wire [6:0] HEX2;
    wire [6:0] HEX3;
    wire [6:0] HEX4;
    wire [6:0] HEX5;

    wire GPIO_1;

    wire VGA_HS;
    wire VGA_VS;

    wire [3:0] VGA_R;
    wire [3:0] VGA_G;
    wire [3:0] VGA_B;

    // =========================================================
    // DUT
    // =========================================================
    CORE_AXI dut (

        .clk        (clk),
        .reset      (reset),

        .SW         (SW),
        .GPIO_0     (GPIO_0),

        .LEDR       (LEDR),

        .HEX0       (HEX0),
        .HEX1       (HEX1),
        .HEX2       (HEX2),
        .HEX3       (HEX3),
        .HEX4       (HEX4),
        .HEX5       (HEX5),

        .GPIO_1     (GPIO_1),

        .VGA_HS     (VGA_HS),
        .VGA_VS     (VGA_VS),

        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B)
    );

    // =========================================================
    // TEST SEQUENCE
    // =========================================================
    initial begin

        // Default input
        SW      = 10'b0000000000;
        GPIO_0  = 1'b1;

        // Wait reset release
        @(posedge reset);

        $display("");
        $display("========================================");
        $display("START CORE_AXI TEST");
        $display("========================================");
        $display("");

        // =====================================================
        // SWITCH TEST
        // =====================================================
        #2000;
        SW = 10'b1010101010;

        #2000;
        SW = 10'b0101010101;

        #2000;
        SW = 10'b1111111111;

        #2000;
        SW = 10'b0000000000;

        // =====================================================
        // UART RX SIMULATION (OPTIONAL)
        // =====================================================
        // Fake UART idle
        GPIO_0 = 1'b1;

        // =====================================================
        // RUN SYSTEM
        // =====================================================
        #1000000;

        $display("");
        $display("========================================");
        $display("END SIMULATION");
        $display("========================================");
        $display("");

        $stop;
    end

    // =========================================================
    // AXI MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (dut.we || dut.re) begin

            $display(
                "[AXI] T=%0t | ADDR=%h | WDATA=%h | WE=%b | RE=%b | READY=%b",
                $time,
                dut.addr,
                dut.wdata,
                dut.we,
                dut.re,
                dut.ready
            );
        end
    end

    // =========================================================
    // CPU PIPELINE MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (reset) begin

            $display(
                "[CPU] T=%0t | PC=%h | INSTR=%h",
                $time,
                dut.cpu.fetch.pcF,
                dut.cpu.fetch.instrF
            );
        end
    end

    // =========================================================
    // GPIO MONITOR
    // =========================================================
    always @(LEDR) begin

        $display(
            "[GPIO] T=%0t | LEDR = %b",
            $time,
            LEDR
        );
    end

    // =========================================================
    // VGA WRITE MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (dut.we && (dut.addr >= 32'h30000000)
                    && (dut.addr <  32'h30010000)) begin

            $display(
                "[VGA] T=%0t | ADDR=%h | DATA=%h",
                $time,
                dut.addr,
                dut.wdata
            );
        end
    end

    // =========================================================
    // GPIO WRITE MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (dut.we && (dut.addr >= 32'h10000000)
                    && (dut.addr <  32'h10000100)) begin

            $display(
                "[GPIO WRITE] T=%0t | ADDR=%h | DATA=%h",
                $time,
                dut.addr,
                dut.wdata
            );
        end
    end

    // =========================================================
    // UART WRITE MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (dut.we && (dut.addr >= 32'h20000000)
                    && (dut.addr <  32'h20000100)) begin

            $display(
                "[UART WRITE] T=%0t | ADDR=%h | DATA=%h",
                $time,
                dut.addr,
                dut.wdata
            );
        end
    end

    // =========================================================
    // STALL MONITOR
    // =========================================================
    always @(posedge clk) begin

        if (dut.cpu.StallF ||
            dut.cpu.StallD ||
            dut.cpu.StallE ||
            dut.cpu.StallM) begin

            $display(
                "[STALL] T=%0t | F=%b D=%b E=%b M=%b",
                $time,
                dut.cpu.StallF,
                dut.cpu.StallD,
                dut.cpu.StallE,
                dut.cpu.StallM
            );
        end
    end

    // =========================================================
    // TIMEOUT PROTECTION
    // =========================================================
    initial begin

        #5000000;

        $display("");
        $display("========================================");
        $display("TIMEOUT");
        $display("========================================");
        $display("");

        $stop;
    end



endmodule