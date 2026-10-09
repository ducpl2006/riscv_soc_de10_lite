`timescale 1ns/1ps

module tb_manager_ram;

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
    // AXI BUS
    // =====================================================

    // WRITE ADDRESS
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;

    // WRITE DATA
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;

    // WRITE RESPONSE
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    // READ ADDRESS
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;

    // READ DATA
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    // =====================================================
    // AXI MANAGER
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

        // WRITE ADDRESS
        .axi_awaddr(axi_awaddr),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),

        // WRITE DATA
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),

        // WRITE RESPONSE
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),

        // READ ADDRESS
        .axi_araddr(axi_araddr),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),

        // READ DATA
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

    // =====================================================
    // AXI RAM SLAVE
    // =====================================================

    AXI_RAM_Slave ram (

        .clk(clk),
        .reset(reset),

        // WRITE ADDRESS
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),

        // WRITE DATA
        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),

        // WRITE RESPONSE
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),

        // READ ADDRESS
        .s_axi_araddr(axi_araddr),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),

        // READ DATA
        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );

    // =====================================================
    // CPU WRITE TASK
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

            $display("[CPU WRITE DONE]");
            $display("ADDR = %h", addr);
            $display("DATA = %h", data);

        end

    endtask

    // =====================================================
    // CPU READ TASK
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

            $display("[CPU READ DONE]");
            $display("ADDR  = %h", addr);
            $display("RDATA = %h", mem_rdata);

        end

    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================

    initial begin

        mem_addr  = 0;
        mem_wdata = 0;
        mem_we    = 0;
        mem_re    = 0;

        // active low reset
        reset = 0;

        repeat(10) @(posedge clk);

        reset = 1;

        repeat(10) @(posedge clk);

        $display("");
        $display("=================================");
        $display("START MANAGER + RAM TEST");
        $display("=================================");

        // =============================================
        // WRITE
        // =============================================

        cpu_write(
            32'h0000_0000,
            32'hDEADBEEF
        );

        // =============================================
        // READ
        // =============================================

        cpu_read(
            32'h0000_0000
        );

        repeat(20) @(posedge clk);

        $display("");
        $display("=================================");
        $display("SIMULATION FINISHED");
        $display("=================================");

        $finish;

    end

    // =====================================================
    // MONITOR
    // =====================================================

    initial begin

        $monitor(
        "TIME=%0t | MEM_READY=%b | AWV=%b AWR=%b | WV=%b WR=%b | BV=%b | ARV=%b ARR=%b | RV=%b",
            $time,

            mem_ready,

            axi_awvalid,
            axi_awready,

            axi_wvalid,
            axi_wready,

            axi_bvalid,

            axi_arvalid,
            axi_arready,

            axi_rvalid
        );

    end

    // =====================================================
    // WAVEFORM
    // =====================================================

endmodule