`timescale 1ns/1ps

module tb_AXI_GPIO_Slave;

    // ==================================================
    // PARAMETERS
    // ==================================================
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;

    // ==================================================
    // CLOCK / RESET
    // ==================================================
    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==================================================
    // AXI WRITE ADDRESS CHANNEL
    // ==================================================
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    // ==================================================
    // AXI WRITE DATA CHANNEL
    // ==================================================
    reg  [DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                     s_axi_wvalid;
    wire                    s_axi_wready;

    // ==================================================
    // AXI WRITE RESPONSE CHANNEL
    // ==================================================
    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // ==================================================
    // AXI READ ADDRESS CHANNEL
    // ==================================================
    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    // ==================================================
    // AXI READ DATA CHANNEL
    // ==================================================
    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // ==================================================
    // FPGA I/O
    // ==================================================
    reg  [9:0] SW;

    wire [9:0] LEDR;

    wire [6:0] HEX0;
    wire [6:0] HEX1;
    wire [6:0] HEX2;
    wire [6:0] HEX3;
    wire [6:0] HEX4;
    wire [6:0] HEX5;

    // ==================================================
    // DUT
    // ==================================================
    AXI_GPIO_Slave dut (

        .clk            (clk),
        .reset          (reset),

        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .SW             (SW),

        .LEDR           (LEDR),

        .HEX0           (HEX0),
        .HEX1           (HEX1),
        .HEX2           (HEX2),
        .HEX3           (HEX3),
        .HEX4           (HEX4),
        .HEX5           (HEX5)
    );

    // ==================================================
    // AXI WRITE TASK
    // ==================================================
    task axi_write;

        input [31:0] addr;
        input [31:0] data;

        begin

            @(posedge clk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'b1111;
            s_axi_wvalid  <= 1'b1;

            // WAIT AW
            wait(s_axi_awready);

            @(posedge clk);
            s_axi_awvalid <= 1'b0;

            // WAIT W
            wait(s_axi_wready);

            @(posedge clk);
            s_axi_wvalid <= 1'b0;

            // WAIT B
            wait(s_axi_bvalid);

            s_axi_bready <= 1'b1;

            @(posedge clk);

            s_axi_bready <= 1'b0;

        end

    endtask

    // ==================================================
    // AXI READ TASK
    // ==================================================
    task axi_read;

        input  [31:0] addr;
        output [31:0] data;

        begin

            @(posedge clk);

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;

            wait(s_axi_arready);

            @(posedge clk);

            s_axi_arvalid <= 1'b0;

            wait(s_axi_rvalid);

            data = s_axi_rdata;

            s_axi_rready <= 1'b1;

            @(posedge clk);

            s_axi_rready <= 1'b0;

        end

    endtask

    // ==================================================
    // TEST
    // ==================================================
    reg [31:0] rd_data;

    initial begin

        // ==============================================
        // INIT
        // ==============================================
        reset           = 0;

        s_axi_awaddr    = 0;
        s_axi_awvalid   = 0;

        s_axi_wdata     = 0;
        s_axi_wstrb     = 0;
        s_axi_wvalid    = 0;

        s_axi_bready    = 0;

        s_axi_araddr    = 0;
        s_axi_arvalid   = 0;

        s_axi_rready    = 0;

        SW              = 10'b1010101010;

        // ==============================================
        // RESET
        // ==============================================
        #50;
        reset = 1;

        #20;

        // ==============================================
        // TC1 : WRITE LEDR
        // ==============================================
        $display("======================================");
        $display("TC1 : WRITE LEDR");
        $display("======================================");

        axi_write(32'h1000_0000, 32'h0000_0155);

        #20;

        if (LEDR == 10'h155)
            $display("PASS : LEDR = %h", LEDR);
        else
            $display("FAIL : LEDR = %h", LEDR);

        // ==============================================
        // TC2 : READ LEDR
        // ==============================================
        $display("======================================");
        $display("TC2 : READ LEDR");
        $display("======================================");

        axi_read(32'h1000_0000, rd_data);

        if (rd_data[9:0] == 10'h155)
            $display("PASS : READ LEDR = %h", rd_data);
        else
            $display("FAIL : READ LEDR = %h", rd_data);

        // ==============================================
        // TC3 : READ SWITCH
        // ==============================================
        $display("======================================");
        $display("TC3 : READ SWITCH");
        $display("======================================");

        axi_read(32'h1000_000C, rd_data);

        if (rd_data[9:0] == SW)
            $display("PASS : READ SW = %h", rd_data);
        else
            $display("FAIL : READ SW = %h", rd_data);

        // ==============================================
        // TC4 : WRITE HEX
        // ==============================================
        $display("======================================");
        $display("TC4 : WRITE HEX");
        $display("======================================");

        axi_write(32'h1000_0004, 32'h00ABCDEF);

        #50;

        $display("HEX WRITE DONE");

        // ==============================================
        // TC5 : BACK TO BACK WRITE
        // ==============================================
        $display("======================================");
        $display("TC5 : BACK TO BACK WRITE");
        $display("======================================");

        axi_write(32'h1000_0000, 32'h000000AA);
        axi_write(32'h1000_0000, 32'h00000155);

        #20;

        if (LEDR == 10'h155)
            $display("PASS : BACK TO BACK");
        else
            $display("FAIL : BACK TO BACK");

        // ==============================================
        // FINISH
        // ==============================================
        #100;

        $display("======================================");
        $display("ALL TEST DONE");
        $display("======================================");

        $finish;

    end

endmodule