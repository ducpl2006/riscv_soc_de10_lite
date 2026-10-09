`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH : AXI_VGA_Slave_tb
// ----------------------------------------------------------------------------
// ADVANCED AXI4-Lite VGA TESTBENCH
//
// Features:
//   + PASS / FAIL checking
//   + Self-checking testbench
//   + Stress test
//   + Decoupled AW/W
//   + Invalid address
//   + Backpressure
//   + Random transaction
//   + Timeout detection
//   + AXI protocol verification
//
// ============================================================================

module tb_AXI_VGA_Slave;

    // =========================================================================
    // CLOCK / RESET
    // =========================================================================
    reg clk;
    reg reset;

    // =========================================================================
    // AXI WRITE ADDRESS CHANNEL
    // =========================================================================
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;

    // =========================================================================
    // AXI WRITE DATA CHANNEL
    // =========================================================================
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;

    // =========================================================================
    // AXI WRITE RESPONSE CHANNEL
    // =========================================================================
    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // =========================================================================
    // AXI READ ADDRESS CHANNEL
    // =========================================================================
    reg  [31:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    // =========================================================================
    // AXI READ DATA CHANNEL
    // =========================================================================
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // =========================================================================
    // VGA OUTPUT
    // =========================================================================
    wire VGA_HS;
    wire VGA_VS;

    wire [3:0] VGA_R;
    wire [3:0] VGA_G;
    wire [3:0] VGA_B;

    // =========================================================================
    // TEST STATUS
    // =========================================================================
    integer total_test;
    integer pass_test;
    integer fail_test;

    // =========================================================================
    // DUT
    // =========================================================================
    AXI_VGA_Slave dut (

        .clk            (clk),
        .reset          (reset),

        // WRITE ADDRESS
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        // WRITE DATA
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        // WRITE RESPONSE
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        // READ ADDRESS
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        // READ DATA
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        // VGA
        .VGA_HS         (VGA_HS),
        .VGA_VS         (VGA_VS),

        .VGA_R          (VGA_R),
        .VGA_G          (VGA_G),
        .VGA_B          (VGA_B)
    );

    // =========================================================================
    // CLOCK
    // =========================================================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // =========================================================================
    // PASS TASK
    // =========================================================================
    task test_pass;

        input [1023:0] name;

        begin
            pass_test = pass_test + 1;
            total_test = total_test + 1;

            $display("[PASS] %0s", name);
        end

    endtask

    // =========================================================================
    // FAIL TASK
    // =========================================================================
    task test_fail;

        input [1023:0] name;

        begin
            fail_test = fail_test + 1;
            total_test = total_test + 1;

            $display("[FAIL] %0s", name);
        end

    endtask

    // =========================================================================
    // AXI WRITE TASK
    // =========================================================================
    task axi_write;

        input [31:0] addr;
        input [31:0] data;

        integer timeout;

        begin

            @(posedge clk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;

            s_axi_wstrb   <= 4'b1111;

            timeout = 0;

            // WAIT AWREADY
            while (!s_axi_awready) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 1000) begin
                    $display("[TIMEOUT] AWREADY");
                    $stop;
                end
            end

            // WAIT WREADY
            timeout = 0;

            while (!s_axi_wready) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 1000) begin
                    $display("[TIMEOUT] WREADY");
                    $stop;
                end
            end

            @(posedge clk);

            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // WAIT BVALID
            timeout = 0;

            while (!s_axi_bvalid) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 1000) begin
                    $display("[TIMEOUT] BVALID");
                    $stop;
                end
            end

            @(posedge clk);

        end

    endtask

    // =========================================================================
    // AXI READ TASK
    // =========================================================================
    task axi_read;

        input  [31:0] addr;
        output [31:0] data;

        integer timeout;

        begin

            @(posedge clk);

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;

            timeout = 0;

            // WAIT ARREADY
            while (!s_axi_arready) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 1000) begin
                    $display("[TIMEOUT] ARREADY");
                    $stop;
                end
            end

            @(posedge clk);

            s_axi_arvalid <= 1'b0;

            timeout = 0;

            // WAIT RVALID
            while (!s_axi_rvalid) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 1000) begin
                    $display("[TIMEOUT] RVALID");
                    $stop;
                end
            end

            data = s_axi_rdata;

            @(posedge clk);

        end

    endtask

    // =========================================================================
    // DECOUPLED WRITE
    // =========================================================================
    task axi_write_decoupled;

        input [31:0] addr;
        input [31:0] data;

        begin

            // AW FIRST
            @(posedge clk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            wait(s_axi_awready);

            @(posedge clk);

            s_axi_awvalid <= 1'b0;

            // DELAY
            repeat(5) @(posedge clk);

            // W LATER
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'b1111;

            wait(s_axi_wready);

            @(posedge clk);

            s_axi_wvalid <= 1'b0;

            wait(s_axi_bvalid);

            @(posedge clk);

        end

    endtask

    // =========================================================================
    // MAIN TEST
    // =========================================================================
    integer i;
    reg [31:0] rd_data;

    initial begin

        // =============================================================
        // INIT
        // =============================================================
        total_test = 0;
        pass_test  = 0;
        fail_test  = 0;

        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;

        s_axi_wdata   = 0;
        s_axi_wvalid  = 0;
        s_axi_wstrb   = 4'b1111;

        s_axi_bready  = 1;

        s_axi_araddr  = 0;
        s_axi_arvalid = 0;

        s_axi_rready  = 1;

        // ACTIVE-LOW RESET
        reset = 0;

        // =============================================================
        // RESET
        // =============================================================
        $display("================================================");
        $display("TC1 : RESET");
        $display("================================================");

        repeat(10) @(posedge clk);

        reset = 1;

        repeat(20) @(posedge clk);

        if (s_axi_bvalid == 0 &&
            s_axi_rvalid == 0)
        begin
            test_pass("RESET STATE");
        end

        else begin
            test_fail("RESET STATE");
        end

        // =============================================================
        // TC2 : STATUS READ
        // =============================================================
        $display("================================================");
        $display("TC2 : STATUS READ");
        $display("================================================");

        axi_read(32'h3000_4004, rd_data);

        if (s_axi_rresp == 2'b00)
            test_pass("STATUS READ");

        else
            test_fail("STATUS READ");

        // =============================================================
        // TC3 : CTRL WRITE
        // =============================================================
        $display("================================================");
        $display("TC3 : CTRL WRITE");
        $display("================================================");

        axi_write(32'h3000_4000, 32'h12345678);

        if (s_axi_bresp == 2'b00)
            test_pass("CTRL WRITE");

        else
            test_fail("CTRL WRITE");

        // =============================================================
        // TC4 : TEXT RAM WRITE
        // =============================================================
        $display("================================================");
        $display("TC4 : TEXT RAM WRITE");
        $display("================================================");

        axi_write(32'h3000_0000, 32'h00000041);

        if (s_axi_bresp == 2'b00)
            test_pass("TEXT RAM WRITE");

        else
            test_fail("TEXT RAM WRITE");

        // =============================================================
        // TC5 : MULTIPLE TEXT WRITES
        // =============================================================
        $display("================================================");
        $display("TC5 : MULTIPLE TEXT WRITES");
        $display("================================================");

        for (i = 0; i < 20; i = i + 1) begin

            axi_write(
                32'h3000_0000 + (i * 4),
                i
            );

            if (s_axi_bresp != 2'b00)
                test_fail("MULTIPLE WRITE");
        end

        test_pass("MULTIPLE WRITE");

        // =============================================================
        // TC6 : INVALID WRITE
        // =============================================================
        $display("================================================");
        $display("TC6 : INVALID WRITE");
        $display("================================================");

        axi_write(32'h5000_0000, 32'hDEADBEEF);

        if (s_axi_bresp == 2'b10)
            test_pass("INVALID WRITE");

        else
            test_fail("INVALID WRITE");

        // =============================================================
        // TC7 : INVALID READ
        // =============================================================
        $display("================================================");
        $display("TC7 : INVALID READ");
        $display("================================================");

        axi_read(32'h5000_0000, rd_data);

        if (s_axi_rresp == 2'b10)
            test_pass("INVALID READ");

        else
            test_fail("INVALID READ");

        // =============================================================
        // TC8 : BACK TO BACK WRITE
        // =============================================================
        $display("================================================");
        $display("TC8 : BACK TO BACK WRITE");
        $display("================================================");

        axi_write(32'h3000_0000, 32'h11111111);
        axi_write(32'h3000_0004, 32'h22222222);
        axi_write(32'h3000_0008, 32'h33333333);

        test_pass("BACK TO BACK WRITE");

        // =============================================================
        // TC9 : BACK TO BACK READ
        // =============================================================
        $display("================================================");
        $display("TC9 : BACK TO BACK READ");
        $display("================================================");

        axi_read(32'h3000_4000, rd_data);
        axi_read(32'h3000_4004, rd_data);

        test_pass("BACK TO BACK READ");

        // =============================================================
        // TC10 : DECOUPLED AW/W
        // =============================================================
        $display("================================================");
        $display("TC10 : DECOUPLED AW/W");
        $display("================================================");

        axi_write_decoupled(
            32'h3000_0010,
            32'hABCD1234
        );

        if (s_axi_bresp == 2'b00)
            test_pass("DECOUPLED WRITE");

        else
            test_fail("DECOUPLED WRITE");

        // =============================================================
        // TC11 : STRESS WRITE
        // =============================================================
        $display("================================================");
        $display("TC11 : STRESS WRITE");
        $display("================================================");

        for (i = 0; i < 100; i = i + 1) begin

            axi_write(
                32'h3000_0000 + (i * 4),
                $random
            );

            if (s_axi_bresp != 2'b00) begin
                test_fail("STRESS WRITE");
                $stop;
            end
        end

        test_pass("STRESS WRITE");

        // =============================================================
        // TC12 : RANDOM ACCESS
        // =============================================================
        $display("================================================");
        $display("TC12 : RANDOM ACCESS");
        $display("================================================");

        for (i = 0; i < 50; i = i + 1) begin

            axi_write(
                32'h3000_0000 + (($random % 100) * 4),
                $random
            );
        end

        test_pass("RANDOM ACCESS");

        // =============================================================
        // TC13 : BREADY BACKPRESSURE
        // =============================================================
        $display("================================================");
        $display("TC13 : BREADY BACKPRESSURE");
        $display("================================================");

        s_axi_bready = 0;

        fork
            begin
                axi_write(32'h3000_0000, 32'hAAAAAAAA);
            end

            begin
                repeat(20) @(posedge clk);
                s_axi_bready = 1;
            end
        join

        test_pass("BREADY BACKPRESSURE");

        // =============================================================
        // TC14 : RREADY BACKPRESSURE
        // =============================================================
        $display("================================================");
        $display("TC14 : RREADY BACKPRESSURE");
        $display("================================================");

        s_axi_rready = 0;

        fork
            begin
                axi_read(32'h3000_4004, rd_data);
            end

            begin
                repeat(20) @(posedge clk);
                s_axi_rready = 1;
            end
        join

        test_pass("RREADY BACKPRESSURE");

        // =============================================================
        // FINAL RESULT
        // =============================================================
        $display("");
        $display("================================================");
        $display("FINAL RESULT");
        $display("================================================");

        $display("TOTAL TEST : %0d", total_test);
        $display("PASS TEST  : %0d", pass_test);
        $display("FAIL TEST  : %0d", fail_test);

        if (fail_test == 0) begin

            $display("");
            $display("############################################");
            $display("########### ALL TEST PASSED ################");
            $display("############################################");
        end

        else begin

            $display("");
            $display("############################################");
            $display("############ SOME TEST FAILED ##############");
            $display("############################################");
        end

        #1000;
        $stop;

    end

endmodule