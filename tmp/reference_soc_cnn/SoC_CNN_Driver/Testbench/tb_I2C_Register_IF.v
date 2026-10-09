`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Register_IF — drive qua giao diện register (addr/wr_data/write/read),
// slave model 0x50. Kiểm tra VERSION, cấu hình, WRITE + READ transaction qua
// DATA_CMD FIFO và đọc RXDATA.
// ============================================================================
module tb_I2C_Register_IF;

    localparam OFF_CTRL=8'h04, OFF_STATUS=8'h08, OFF_PRESCALE=8'h10,
               OFF_ADDRESS=8'h14, OFF_DATACMD=8'h18, OFF_RXDATA=8'h1C,
               OFF_INTSTAT=8'h24, OFF_VERSION=8'h00;

    reg         clk = 0;
    reg         reset;
    reg  [31:0] addr, wr_data;
    reg         write_en, read_en;
    wire [31:0] rd_data;
    wire        irq;
    wire        scl_pad, sda_pad;

    integer errors = 0;

    always #5 clk = ~clk;

    // ---- slave 0x50 (raw pad) ----
    localparam [6:0] SADDR = 7'h50;
    wire scl_f = scl_pad, sda_f = sda_pad;
    reg  in_txn=0, rd_txn=0, addr_match=0, sl_low=0;
    reg [3:0] fcnt=0, byte_idx=0;
    reg [7:0] recv_sh=0;
    integer   send_ptr=0, cap_ptr=0;
    reg [7:0] send_rom [0:3];
    reg [7:0] captured [0:7];
    initial begin send_rom[0]=8'h11; send_rom[1]=8'h22; send_rom[2]=8'h33; send_rom[3]=8'h44; end

    pullup(scl_pad); pullup(sda_pad);
    assign sda_pad = (in_txn && sl_low) ? 1'b0 : 1'bz;
    wire sending = in_txn && (byte_idx>=1) && rd_txn && addr_match;
    wire [7:0] cur_send = send_rom[send_ptr];

    always @(sda_f) if (scl_f) begin
        if (~sda_f) begin in_txn<=1; fcnt<=0; byte_idx<=0; recv_sh<=0; send_ptr<=0; end
        else        begin in_txn<=0; fcnt<=0; byte_idx<=0; end
    end
    always @(posedge scl_f) if (in_txn && !sending) recv_sh <= {recv_sh[6:0], sda_f};
    always @(negedge scl_f) begin
        if (in_txn) begin
            if (sending) sl_low <= (fcnt<8) ? ~cur_send[7-fcnt] : 1'b0;
            else         sl_low <= (fcnt<8) ? 1'b0 : ((byte_idx==0)?(recv_sh[7:1]==SADDR):1'b1);
            if (fcnt==4'd8) begin
                fcnt<=0; byte_idx<=byte_idx+4'd1;
                if (byte_idx==0) begin addr_match<=(recv_sh[7:1]==SADDR); rd_txn<=recv_sh[0]; end
                else if (sending) send_ptr<=send_ptr+1;
                else begin captured[cap_ptr]<=recv_sh; cap_ptr<=cap_ptr+1; end
            end else fcnt<=fcnt+4'd1;
        end
    end

    // ---- DUT ----
    I2C_Register_IF #(.PRESCALE_WIDTH(16), .SPIKE_LEN(0), .VERSION_ID(32'h0001_0000)) dut (
        .clk(clk), .reset(reset), .addr(addr), .wr_data(wr_data),
        .write_en(write_en), .read_en(read_en), .rd_data(rd_data),
        .irq(irq), .scl_pad(scl_pad), .sda_pad(sda_pad));

    // ---- helpers ----
    task reg_write(input [7:0] o, input [31:0] d); begin
        @(negedge clk); addr={24'd0,o}; wr_data=d; write_en=1;
        @(negedge clk); write_en=0;
    end endtask
    task reg_read(input [7:0] o, output [31:0] d); begin
        @(negedge clk); addr={24'd0,o}; read_en=1;
        #1 d=rd_data;
        @(negedge clk); read_en=0;
    end endtask

    reg [31:0] rv; integer guard;
    task wait_idle; begin
        rv=0; guard=0;
        while (!(rv[7] && rv[5]) && guard<20000) begin reg_read(OFF_STATUS,rv); guard=guard+1; end
    end endtask

    reg [31:0] d;
    initial begin
        reset=0; addr=0; wr_data=0; write_en=0; read_en=0;
        #23 reset=1; repeat(2) @(negedge clk);

        // VERSION
        reg_read(OFF_VERSION,d);
        if (d!==32'h0001_0000) begin $display("  [ERR] VERSION=%h expect 00010000",d); errors=errors+1; end

        // cấu hình + enable
        reg_write(OFF_PRESCALE, 32'd5);
        reg_write(OFF_ADDRESS,  32'h050);
        reg_write(OFF_CTRL,     32'h001);   // EN

        // WRITE transaction
        reg_write(OFF_DATACMD, {20'd0, 1'b0,1'b0,1'b1,1'b0,8'hA5});
        reg_write(OFF_DATACMD, {20'd0, 1'b0,1'b1,1'b0,1'b0,8'h3C});
        wait_idle;
        if (captured[0]!==8'hA5) begin $display("  [ERR] slave recv[0]=%h expect A5",captured[0]); errors=errors+1; end
        if (captured[1]!==8'h3C) begin $display("  [ERR] slave recv[1]=%h expect 3C",captured[1]); errors=errors+1; end

        // READ transaction
        reg_write(OFF_DATACMD, {20'd0, 1'b0,1'b0,1'b1,1'b1,8'h00});
        reg_write(OFF_DATACMD, {20'd0, 1'b1,1'b1,1'b0,1'b1,8'h00});
        wait_idle;
        reg_read(OFF_RXDATA,d);
        if (d[7:0]!==8'h11) begin $display("  [ERR] RXDATA[0]=%h expect 11",d[7:0]); errors=errors+1; end
        reg_read(OFF_RXDATA,d);
        if (d[7:0]!==8'h22) begin $display("  [ERR] RXDATA[1]=%h expect 22",d[7:0]); errors=errors+1; end

        // INT_STATUS có TX_DONE/RX_DONE/STOP
        reg_read(OFF_INTSTAT,d);
        if (!d[7]) begin $display("  [ERR] INT STOP_DET khong set (int=%h)",d); errors=errors+1; end

        if (errors==0) $display("PASS: I2C_Register_IF");
        else           $display("FAIL: I2C_Register_IF (%0d errors)", errors);
        $finish;
    end

    initial begin #3000000; $display("FAIL: I2C_Register_IF (timeout)"); $finish; end

endmodule
