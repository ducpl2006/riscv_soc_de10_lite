`timescale 1ns/1ps

module tb_interconnect_ram;

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
    // CPU SIDE
    // =====================================================

    reg  [31:0] mem_addr;
    reg  [31:0] mem_wdata;
    reg         mem_we;
    reg         mem_re;

    wire [31:0] mem_rdata;
    wire        mem_ready;

    // =====================================================
    // AXI SIGNALS
    // =====================================================

    wire [31:0] m_axi_awaddr;
    wire        m_axi_awvalid;
    wire        m_axi_awready;

    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;

    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;

    wire [31:0] m_axi_araddr;
    wire        m_axi_arvalid;
    wire        m_axi_arready;

    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // =====================================================
    // RAM SIDE
    // =====================================================

    wire [31:0] s0_axi_awaddr;
    wire        s0_axi_awvalid;
    wire        s0_axi_awready;

    wire [31:0] s0_axi_wdata;
    wire [3:0]  s0_axi_wstrb;
    wire        s0_axi_wvalid;
    wire        s0_axi_wready;

    wire [1:0]  s0_axi_bresp;
    wire        s0_axi_bvalid;
    wire        s0_axi_bready;

    wire [31:0] s0_axi_araddr;
    wire        s0_axi_arvalid;
    wire        s0_axi_arready;

    wire [31:0] s0_axi_rdata;
    wire [1:0]  s0_axi_rresp;
    wire        s0_axi_rvalid;
    wire        s0_axi_rready;

    // =====================================================
    // MANAGER
    // =====================================================

    AXI_Manager manager (

        .clk(clk),
        .reset(reset),

        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_we(mem_we),
        .mem_re(mem_re),

        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),

        .axi_awaddr(m_axi_awaddr),
        .axi_awvalid(m_axi_awvalid),
        .axi_awready(m_axi_awready),

        .axi_wdata(m_axi_wdata),
        .axi_wstrb(m_axi_wstrb),
        .axi_wvalid(m_axi_wvalid),
        .axi_wready(m_axi_wready),

        .axi_bresp(m_axi_bresp),
        .axi_bvalid(m_axi_bvalid),
        .axi_bready(m_axi_bready),

        .axi_araddr(m_axi_araddr),
        .axi_arvalid(m_axi_arvalid),
        .axi_arready(m_axi_arready),

        .axi_rdata(m_axi_rdata),
        .axi_rresp(m_axi_rresp),
        .axi_rvalid(m_axi_rvalid),
        .axi_rready(m_axi_rready)
    );

    // =====================================================
    // INTERCONNECT
    // =====================================================

    AXI_Interconnect interconnect (

        .clk(clk),
        .reset(reset),

        // MASTER
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),

        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),

        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),

        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),

        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),

        // RAM ONLY
        .s0_axi_awaddr(s0_axi_awaddr),
        .s0_axi_awvalid(s0_axi_awvalid),
        .s0_axi_awready(s0_axi_awready),

        .s0_axi_wdata(s0_axi_wdata),
        .s0_axi_wstrb(s0_axi_wstrb),
        .s0_axi_wvalid(s0_axi_wvalid),
        .s0_axi_wready(s0_axi_wready),

        .s0_axi_bresp(s0_axi_bresp),
        .s0_axi_bvalid(s0_axi_bvalid),
        .s0_axi_bready(s0_axi_bready),

        .s0_axi_araddr(s0_axi_araddr),
        .s0_axi_arvalid(s0_axi_arvalid),
        .s0_axi_arready(s0_axi_arready),

        .s0_axi_rdata(s0_axi_rdata),
        .s0_axi_rresp(s0_axi_rresp),
        .s0_axi_rvalid(s0_axi_rvalid),
        .s0_axi_rready(s0_axi_rready),

        // DUMMY SLAVES
        .s1_axi_awready(1'b0),
        .s1_axi_wready (1'b0),
        .s1_axi_bresp  (2'b00),
        .s1_axi_bvalid (1'b0),
        .s1_axi_arready(1'b0),
        .s1_axi_rdata  (32'b0),
        .s1_axi_rresp  (2'b00),
        .s1_axi_rvalid (1'b0),

        .s2_axi_awready(1'b0),
        .s2_axi_wready (1'b0),
        .s2_axi_bresp  (2'b00),
        .s2_axi_bvalid (1'b0),
        .s2_axi_arready(1'b0),
        .s2_axi_rdata  (32'b0),
        .s2_axi_rresp  (2'b00),
        .s2_axi_rvalid (1'b0),

        .s3_axi_awready(1'b0),
        .s3_axi_wready (1'b0),
        .s3_axi_bresp  (2'b00),
        .s3_axi_bvalid (1'b0),
        .s3_axi_arready(1'b0),
        .s3_axi_rdata  (32'b0),
        .s3_axi_rresp  (2'b00),
        .s3_axi_rvalid (1'b0)
    );

    // =====================================================
    // RAM
    // =====================================================

    AXI_RAM_Slave ram (

        .clk(clk),
        .reset(reset),

        .s_axi_awaddr(s0_axi_awaddr),
        .s_axi_awvalid(s0_axi_awvalid),
        .s_axi_awready(s0_axi_awready),

        .s_axi_wdata(s0_axi_wdata),
        .s_axi_wstrb(s0_axi_wstrb),
        .s_axi_wvalid(s0_axi_wvalid),
        .s_axi_wready(s0_axi_wready),

        .s_axi_bresp(s0_axi_bresp),
        .s_axi_bvalid(s0_axi_bvalid),
        .s_axi_bready(s0_axi_bready),

        .s_axi_araddr(s0_axi_araddr),
        .s_axi_arvalid(s0_axi_arvalid),
        .s_axi_arready(s0_axi_arready),

        .s_axi_rdata(s0_axi_rdata),
        .s_axi_rresp(s0_axi_rresp),
        .s_axi_rvalid(s0_axi_rvalid),
        .s_axi_rready(s0_axi_rready)
    );

    // =====================================================
    // TASKS
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
                "[WRITE] ADDR=%h DATA=%h BRESP=%b",
                addr,
                data,
                m_axi_bresp
            );

        end

    endtask

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
                "[READ ] ADDR=%h DATA=%h RRESP=%b",
                addr,
                mem_rdata,
                m_axi_rresp
            );

        end

    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================

    integer i;

    initial begin

        mem_addr  = 0;
        mem_wdata = 0;

        mem_we    = 0;
        mem_re    = 0;

        reset = 0;

        repeat(10) @(posedge clk);

        reset = 1;

        repeat(10) @(posedge clk);

        $display("");
        $display("======================================");
        $display("START AXI INTERCONNECT STRESS TEST");
        $display("======================================");

        // =================================================
        // TEST 1 : CONTINUOUS WRITES
        // =================================================

        for(i=0; i<8; i=i+1) begin

            cpu_write(
                32'h0000_0000 + (i*4),
                32'h1000_0000 + i
            );

        end

        // =================================================
        // TEST 2 : CONTINUOUS READS
        // =================================================

        for(i=0; i<8; i=i+1) begin

            cpu_read(
                32'h0000_0000 + (i*4)
            );

        end

        // =================================================
        // TEST 3 : WRITE/READ MIX
        // =================================================

        cpu_write(32'h0000_0100, 32'hAAAAAAAA);
        cpu_read (32'h0000_0100);

        cpu_write(32'h0000_0104, 32'h55555555);
        cpu_read (32'h0000_0104);

        // =================================================
        // TEST 4 : INVALID ADDRESSES
        // =================================================

        cpu_write(32'hF000_0000, 32'hDEADBEEF);
        cpu_read (32'hF000_0000);

        cpu_write(32'h8000_0000, 32'hCAFEBABE);
        cpu_read (32'h8000_0000);

        // =================================================
        // TEST 5 : RAPID ACCESS
        // =================================================

        for(i=0; i<16; i=i+1) begin

            cpu_write(
                32'h0000_0200 + (i*4),
                i
            );

            cpu_read(
                32'h0000_0200 + (i*4)
            );

        end

        repeat(50) @(posedge clk);

        $display("");
        $display("======================================");
        $display("STRESS TEST FINISHED");
        $display("======================================");

        $finish;

    end

    // =====================================================
    // MONITOR
    // =====================================================

    initial begin

        $monitor(
"T=%0t | READY=%b | AWV=%b AWR=%b | WV=%b WR=%b | BV=%b BR=%b | S0_BV=%b S0_BR=%b",

$time,

mem_ready,

m_axi_awvalid,
m_axi_awready,

m_axi_wvalid,
m_axi_wready,

m_axi_bvalid,
m_axi_bready,

s0_axi_bvalid,
s0_axi_bready
);

    end

endmodule