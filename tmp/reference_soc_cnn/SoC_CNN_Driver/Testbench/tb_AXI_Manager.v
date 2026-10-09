`timescale 1ns/1ps

module tb_AXI_Manager;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    // =========================================================
    // CLOCK / RESET
    // =========================================================
    reg clk;
    reg reset;

    always #10 clk = ~clk;

    // =========================================================
    // CPU INTERFACE
    // =========================================================
    reg  [ADDR_WIDTH-1:0] mem_addr;
    reg  [DATA_WIDTH-1:0] mem_wdata;
    reg                   mem_we;
    reg                   mem_re;

    wire [DATA_WIDTH-1:0] mem_rdata;
    wire                  mem_ready;

    // =========================================================
    // AXI WRITE ADDRESS CHANNEL
    // =========================================================
    wire [ADDR_WIDTH-1:0] axi_awaddr;
    wire                  axi_awvalid;
    reg                   axi_awready;

    // =========================================================
    // AXI WRITE DATA CHANNEL
    // =========================================================
    wire [DATA_WIDTH-1:0]   axi_wdata;
    wire [DATA_WIDTH/8-1:0] axi_wstrb;
    wire                    axi_wvalid;
    reg                     axi_wready;

    // =========================================================
    // AXI WRITE RESPONSE CHANNEL
    // =========================================================
    reg  [1:0] axi_bresp;
    reg        axi_bvalid;
    wire       axi_bready;

    // =========================================================
    // AXI READ ADDRESS CHANNEL
    // =========================================================
    wire [ADDR_WIDTH-1:0] axi_araddr;
    wire                  axi_arvalid;
    reg                   axi_arready;

    // =========================================================
    // AXI READ DATA CHANNEL
    // =========================================================
    reg  [DATA_WIDTH-1:0] axi_rdata;
    reg  [1:0]            axi_rresp;
    reg                   axi_rvalid;
    wire                  axi_rready;

    // =========================================================
    // DUT
    // =========================================================
    AXI_Manager dut (
        .clk(clk),
        .reset(reset),

        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_we(mem_we),
        .mem_re(mem_re),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),

        .axi_awaddr(axi_awaddr),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),

        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),

        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),

        .axi_araddr(axi_araddr),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),

        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

    // =========================================================
    // SIMPLE MEMORY MODEL
    // Giả lập RAM
    // + Giả lập một phần tử lưu trữ trong AXI Slave 
    // =========================================================
    reg [31:0] memory [0:255];

    // Thanh ghi giả lập để lưu địa chỉ giả lập
    reg [31:0] saved_awaddr;

    reg [31:0] saved_araddr;

    // =========================================================
    // TIMEOUT PROTECTION
    // + Timeout khi bị kẹt trong loop
    // =========================================================
    initial begin
        #5000;
        $display("TIMEOUT ERROR");
        $finish;
    end

    // =========================================================
    // CPU WRITE TASK
    // + Giả lập hoạt động ghi của CPU vào AXI
    // =========================================================
    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);

            mem_addr  <= addr;
            mem_wdata <= data;
            mem_we    <= 1;
            mem_re    <= 0;

            @(posedge clk);
            mem_we <= 0;

            wait(mem_ready == 1);       // Cờ báo hoàn thành quá trình ghi

            @(posedge clk);

            $display("[WRITE PASS] ADDR=%h DATA=%h TIME=%0t",
                      addr, data, $time);
        end
    endtask

    // =========================================================
    // CPU READ TASK
    // =========================================================
    task cpu_read;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(posedge clk);

            mem_addr <= addr;
            mem_re   <= 1;
            mem_we   <= 0;

            @(posedge clk);
            mem_re <= 0;

            wait(mem_ready == 1);       // Cờ báo hoàn thành quá trình đọc

            @(posedge clk);

            if (mem_rdata == expected)
                $display("[READ PASS] ADDR=%h DATA=%h TIME=%0t",
                          addr, mem_rdata, $time);
            else begin
                $display("[READ FAIL]");
                $display("EXPECTED = %h", expected);
                $display("GOT      = %h", mem_rdata);
            end
        end
    endtask

    // =========================================================
    // AXI SLAVE TASKS
    // Giả lập một AXI_Slave (Slave chấp nhận và tạo handshake)
    // =========================================================

    // ---------------- AW HANDSHAKE ----------------
    task axi_aw_handshake;
        input integer delay_cycle;      // Giả lập số cycle delay
        /*
            Giả lập AXI Slave nhận addr từ Master
            + Slave nhận được addr khi mà valid và ready cùng bằng 1
        */
        begin
            wait(axi_awvalid);
            repeat(delay_cycle) @(posedge clk);

            axi_awready <= 1;

            @(posedge clk);

            if (axi_awvalid && axi_awready)
                saved_awaddr <= axi_awaddr;

            axi_awready <= 0;
        end
    endtask

    // ---------------- W HANDSHAKE ----------------
    task axi_w_handshake;
        input integer delay_cycle;
        /*
            Giả lập AXI Slave nhận write data từ Master và ghi vào RAM
            + Đợi Master gửi write data
            + Delay vài cycle
            + accept data
            + ghi data vào memory
        */
        begin
            wait(axi_wvalid);
            /*
                + delay vài cycle để chờ Slave phản hồi lại Master
                + Slave phản hồi lại ready cho Master

                => Khi valid và ready cùng bằng 1 --> Slave ghi data vào RAM
            */
            repeat(delay_cycle) @(posedge clk);

            axi_wready <= 1;

            @(posedge clk)

            // WRITE MEMORY
            if (axi_wvalid && axi_wready)
                memory[saved_awaddr[9:2]] <= axi_wdata;

            // Sau khi ghỉ vào RAM xong thì ready về 0 --> xong transtion
            axi_wready <= 0;
        end
    endtask

    // ---------------- B RESPONSE ----------------
    task axi_b_response;
        input integer delay_cycle;
        begin
            repeat(delay_cycle) @(posedge clk);

            axi_bvalid <= 1;
            axi_bresp  <= 2'b00;

            wait(axi_bready);

            @(posedge clk);

            axi_bvalid <= 0;
        end
    endtask

    // ---------------- AR HANDSHAKE ----------------
    task axi_ar_handshake;
        input integer delay_cycle;
        begin
            wait(axi_arvalid);
            repeat(delay_cycle) @(posedge clk);

            axi_arready <= 1;

            @(posedge clk);

            if (axi_arvalid && axi_arready)
                saved_araddr <= axi_araddr;

            axi_arready <= 0;
        end
    endtask

    // ---------------- R RESPONSE ----------------
    task axi_r_response;
        input integer delay_cycle;
        begin
            wait(axi_arvalid);
            repeat(delay_cycle) @(posedge clk);

            axi_rdata  <= memory[saved_araddr[9:2]];
            axi_rresp  <= 2'b00;
            axi_rvalid <= 1;

            wait(axi_rready);

            @(posedge clk);

            axi_rvalid <= 0;
        end
    endtask

    // =========================================================
    // MAIN TEST
    // =========================================================
    initial begin

        // -----------------------------------------------------
        // INIT
        // -----------------------------------------------------
        clk = 0;
        reset = 0;

        mem_addr  = 0;
        mem_wdata = 0;
        mem_we    = 0;
        mem_re    = 0;

        axi_awready = 0;
        axi_wready  = 0;

        axi_bvalid  = 0;
        axi_bresp   = 0;

        axi_arready = 0;

        axi_rvalid  = 0;
        axi_rdata   = 0;
        axi_rresp   = 0;

        // -----------------------------------------------------
        // RESET
        // -----------------------------------------------------
        #20;
        reset = 1;

        // =====================================================
        // TC01 : BASIC WRITE
        // =====================================================
        $display("\n=================================");
        $display("TC01 : BASIC WRITE");
        $display("=================================");

        fork
            cpu_write(32'h00000004, 32'hDEADBEEF);

            axi_aw_handshake(1);
            axi_w_handshake(1);
            axi_b_response(2);
        join

        #20;

        // =====================================================
        // TC02 : BASIC READ
        // =====================================================
        $display("\n=================================");
        $display("TC02 : BASIC READ");
        $display("=================================");

        fork
            cpu_read(32'h00000004, 32'hDEADBEEF);

            axi_ar_handshake(1);
            axi_r_response(3);
        join

        #20;

        // =====================================================
        // TC03 : AW BEFORE W
        // =====================================================
        $display("\n=================================");
        $display("TC03 : AW BEFORE W");
        $display("=================================");

        fork
            cpu_write(32'h00000008, 32'h12345678);

            axi_aw_handshake(1);
            axi_w_handshake(5);
            axi_b_response(7);
        join

        #20;

        // =====================================================
        // TC04 : W BEFORE AW
        // =====================================================
        // $display("\n=================================");
        // $display("TC04 : W BEFORE AW");
        // $display("=================================");

        // fork
        //     cpu_write(32'h0000000C, 32'hCAFEBABE);

        //     axi_w_handshake(1);
        //     axi_aw_handshake(4);
        //     axi_b_response(6);
        // join

        // #20;

        // =====================================================
        // TC05 : AW/W SAME CYCLE
        // =====================================================
        $display("\n=================================");
        $display("TC05 : AW/W SAME CYCLE");
        $display("=================================");

        fork
            cpu_write(32'h00000010, 32'hAAAAAAAA);

            axi_aw_handshake(2);
            axi_w_handshake(2);
            axi_b_response(4);
        join

        #20;

        // =====================================================
        // TC06 : DELAYED BVALID
        // =====================================================
        $display("\n=================================");
        $display("TC06 : DELAYED BVALID");
        $display("=================================");

        fork
            cpu_write(32'h00000014, 32'h55555555);

            axi_aw_handshake(1);
            axi_w_handshake(2);
            axi_b_response(10);
        join

        #20;

        // =====================================================
        // TC07 : DELAYED RVALID
        // =====================================================
        $display("\n=================================");
        $display("TC07 : DELAYED RVALID");
        $display("=================================");

        fork
            cpu_read(32'h00000014, 32'h55555555);

            axi_ar_handshake(1);
            axi_r_response(10);
        join

        #20;

        // =====================================================
        // FINISH
        // =====================================================
        $display("\n=================================");
        $display("ALL TEST DONE");
        $display("=================================");

        #50;
        $finish;
    end

endmodule