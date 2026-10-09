`timescale 1ns/1ps

module tb_AXI_RAM_Slave;

    // =====================================================
    // PARAMETERS
    // =====================================================

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    // =====================================================
    // CLOCK / RESET
    // =====================================================

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =====================================================
    // AXI WRITE ADDRESS CHANNEL
    // =====================================================

    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    // =====================================================
    // AXI WRITE DATA CHANNEL
    // =====================================================

    reg  [DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                     s_axi_wvalid;
    wire                    s_axi_wready;

    // =====================================================
    // AXI WRITE RESPONSE CHANNEL
    // =====================================================

    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // =====================================================
    // AXI READ ADDRESS CHANNEL
    // =====================================================

    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    // =====================================================
    // AXI READ DATA CHANNEL
    // =====================================================

    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // =====================================================
    // DUT
    // =====================================================

    AXI_RAM_Slave dut (

        .clk(clk),
        .reset(reset),

        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );

    // =====================================================
    // AXI WRITE TASK
    // =====================================================

    task axi_write;

        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;

        begin

            @(posedge clk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wstrb   <= strb;
            s_axi_wvalid  <= 1'b1;

            // wait handshake
            wait(s_axi_awready && s_axi_wready);

            @(posedge clk);

            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // wait response
            wait(s_axi_bvalid);

            $display("[WRITE OK]");
            $display("ADDR = %h", addr);
            $display("DATA = %h", data);
            $display("STRB = %b", strb);
            $display("BRESP = %b", s_axi_bresp);

            @(posedge clk);

        end

    endtask

    // =====================================================
    // AXI READ TASK
    // =====================================================

    task axi_read;

        input [31:0] addr;

        begin

            @(posedge clk);

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;

            wait(s_axi_arready);

            @(posedge clk);

            s_axi_arvalid <= 1'b0;

            wait(s_axi_rvalid);

            $display("[READ OK]");
            $display("ADDR  = %h", addr);
            $display("RDATA = %h", s_axi_rdata);
            $display("RRESP = %b", s_axi_rresp);

            @(posedge clk);

        end

    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================

    initial begin

        // init
        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;

        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;

        s_axi_bready  = 1;

        s_axi_araddr  = 0;
        s_axi_arvalid = 0;

        s_axi_rready  = 1;

        // active-low reset
        reset = 0;

        repeat(10) @(posedge clk);

        reset = 1;

        repeat(10) @(posedge clk);

        $display("");
        $display("==================================");
        $display("START AXI RAM SLAVE TEST");
        $display("==================================");

        // =================================================
        // TEST 1 : FULL WORD WRITE
        // =================================================

        axi_write(
            32'h0000_0000,
            32'hDEADBEEF,
            4'b1111
        );

        // =================================================
        // TEST 2 : READ BACK
        // =================================================

        axi_read(
            32'h0000_0000
        );

        // =================================================
        // TEST 3 : PARTIAL WRITE
        // =================================================

        axi_write(
            32'h0000_0000,
            32'hAAAA5555,
            4'b0011
        );

        // =================================================
        // TEST 4 : READ AFTER PARTIAL WRITE
        // =================================================

        axi_read(
            32'h0000_0000
        );

        // =================================================
        // TEST 5 : INVALID ADDRESS
        // =================================================

        axi_write(
            32'h1000_0000,
            32'h12345678,
            4'b1111
        );

        axi_read(
            32'h1000_0000
        );

        repeat(20) @(posedge clk);

        $display("");
        $display("==================================");
        $display("SIMULATION FINISHED");
        $display("==================================");

        $finish;

    end

    // =====================================================
    // MONITOR
    // =====================================================

    initial begin

        $monitor(
            "TIME=%0t | WR_STATE=%0d RD_STATE=%0d | AWV=%b AWR=%b | WV=%b WR=%b | BV=%b | ARV=%b ARR=%b | RV=%b",
            $time,
            dut.wr_state,
            dut.rd_state,
            s_axi_awvalid,
            s_axi_awready,
            s_axi_wvalid,
            s_axi_wready,
            s_axi_bvalid,
            s_axi_arvalid,
            s_axi_arready,
            s_axi_rvalid
        );

    end


endmodule