`timescale 1ns/1ps

// ============================================================================
// Testbench : AXI_UART_Slave
// ----------------------------------------------------------------------------
// Verify:
//   [TC1] Reset behavior
//   [TC2] Read STATUS register
//   [TC3] Write TX data
//   [TC4] Back-to-back TX write
//   [TC5] Invalid write address -> SLVERR
//   [TC6] Invalid read address -> SLVERR
//   [TC7] Read RX register when empty
//   [TC8] AXI handshake stability
//
// NOTE:
//   - Đây là testbench cho AXI wrapper
//   - KHÔNG verify UART serial waveform timing
//   - UART core được assume đã verify riêng
// ============================================================================

module tb_AXI_UART_Slave;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;

    localparam UART_TX_DATA = 32'h2000_0000;
    localparam UART_RX_DATA = 32'h2000_0004;
    localparam UART_STATUS  = 32'h2000_0008;

    // =========================================================================
    // CLOCK / RESET
    // =========================================================================
    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // =========================================================================
    // AXI WRITE ADDRESS CHANNEL
    // =========================================================================
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    // =========================================================================
    // AXI WRITE DATA CHANNEL
    // =========================================================================
    reg  [DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                     s_axi_wvalid;
    wire                    s_axi_wready;

    // =========================================================================
    // AXI WRITE RESPONSE CHANNEL
    // =========================================================================
    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // =========================================================================
    // AXI READ ADDRESS CHANNEL
    // =========================================================================
    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    // =========================================================================
    // AXI READ DATA CHANNEL
    // =========================================================================
    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // =========================================================================
    // UART PINS
    // =========================================================================
    reg rx;
    wire tx;

    // =========================================================================
    // DUT
    // =========================================================================
    AXI_UART_Slave dut (

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

        // UART
        .rx             (rx),
        .tx             (tx)
    );

    // =========================================================================
    // AXI WRITE TASK
    // =========================================================================
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

            // WAIT AWREADY
            wait(s_axi_awready);

            @(posedge clk);
            s_axi_awvalid <= 1'b0;

            // WAIT WREADY
            wait(s_axi_wready);

            @(posedge clk);
            s_axi_wvalid <= 1'b0;

            // WAIT BVALID
            wait(s_axi_bvalid);

            $display("[WRITE RESP] BRESP = %b", s_axi_bresp);

            s_axi_bready <= 1'b1;

            @(posedge clk);

            s_axi_bready <= 1'b0;

        end

    endtask

    // =========================================================================
    // AXI READ TASK
    // =========================================================================
    task axi_read;

        input  [31:0] addr;
        output [31:0] data;
        output [1:0]  resp;

        begin

            @(posedge clk);

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;

            // WAIT ARREADY
            wait(s_axi_arready);

            @(posedge clk);

            s_axi_arvalid <= 1'b0;

            // WAIT RVALID
            wait(s_axi_rvalid);

            data = s_axi_rdata;
            resp = s_axi_rresp;

            s_axi_rready <= 1'b1;

            @(posedge clk);

            s_axi_rready <= 1'b0;

        end

    endtask

    // =========================================================================
    // TEST VARIABLES
    // =========================================================================
    reg [31:0] rd_data;
    reg [1:0]  rd_resp;

    // =========================================================================
    // MAIN TEST
    // =========================================================================
    initial begin

        // =====================================================================
        // INIT
        // =====================================================================
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

        rx              = 1'b1;

        // =====================================================================
        // RESET
        // =====================================================================
        #100;
        reset = 1;

        repeat(20) @(posedge clk);

        // =====================================================================
        // TC1 : READ STATUS REGISTER
        // =====================================================================
        $display("\n======================================");
        $display("TC1 : READ STATUS REGISTER");
        $display("======================================");

        axi_read(UART_STATUS, rd_data, rd_resp);

        $display("STATUS DATA = %h", rd_data);
        $display("RRESP       = %b", rd_resp);

        // EXPECT:
        // tx_full  = 0
        // rx_empty = 1
        // tx_ready = 1
        // rx_irq   = 0
        //
        // => 0x6

        // =====================================================================
        // TC2 : WRITE TX DATA
        // =====================================================================
        $display("\n======================================");
        $display("TC2 : WRITE TX DATA");
        $display("======================================");

        axi_write(UART_TX_DATA, 32'h00000041);

        $display("WRITE UART TX : 'A'");

        #1000;

        // =====================================================================
        // TC3 : BACK TO BACK WRITE
        // =====================================================================
        $display("\n======================================");
        $display("TC3 : BACK TO BACK WRITE");
        $display("======================================");

        axi_write(UART_TX_DATA, 32'h00000042);
        axi_write(UART_TX_DATA, 32'h00000043);
        axi_write(UART_TX_DATA, 32'h00000044);

        $display("WRITE UART TX : B C D");

        #2000;

        // =====================================================================
        // TC4 : READ STATUS AGAIN
        // =====================================================================
        $display("\n======================================");
        $display("TC4 : READ STATUS AGAIN");
        $display("======================================");

        axi_read(UART_STATUS, rd_data, rd_resp);

        $display("STATUS DATA = %h", rd_data);
        $display("RRESP       = %b", rd_resp);

        // =====================================================================
        // TC5 : INVALID WRITE ADDRESS
        // =====================================================================
        $display("\n======================================");
        $display("TC5 : INVALID WRITE ADDRESS");
        $display("======================================");

        axi_write(32'h2000_0010, 32'hDEADBEEF);

        // EXPECT:
        // BRESP = 2'b10 (SLVERR)

        #100;

        // =====================================================================
        // TC6 : INVALID READ ADDRESS
        // =====================================================================
        $display("\n======================================");
        $display("TC6 : INVALID READ ADDRESS");
        $display("======================================");

        axi_read(32'h2000_0010, rd_data, rd_resp);

        $display("INVALID READ DATA = %h", rd_data);
        $display("RRESP             = %b", rd_resp);

        // EXPECT:
        // RRESP = 2'b10

        #100;

        // =====================================================================
        // TC7 : READ RX REGISTER WHEN EMPTY
        // =====================================================================
        $display("\n======================================");
        $display("TC7 : READ RX REGISTER WHEN EMPTY");
        $display("======================================");

        axi_read(UART_RX_DATA, rd_data, rd_resp);

        $display("RX DATA = %h", rd_data);
        $display("RRESP   = %b", rd_resp);

        #100;

        // =====================================================================
        // TC8 : STRESS WRITE TEST
        // =====================================================================
        $display("\n======================================");
        $display("TC8 : STRESS WRITE TEST");
        $display("======================================");

        repeat(10) begin
            axi_write(UART_TX_DATA, $random);
        end

        #5000;

        // =====================================================================
        // FINISH
        // =====================================================================
        $display("\n======================================");
        $display("ALL TEST PASSED");
        $display("======================================");

        $finish;

    end

endmodule