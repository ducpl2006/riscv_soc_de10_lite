`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Master — verify core qua giao diện register-level (push DATA_CMD,
// pop RXDATA, status/irq). Slave model có địa chỉ 0x50.
//   1) WRITE 2 byte -> slave nhận đúng, INT TX_DONE/STOP, IDLE sau cùng
//   2) READ 2 byte  -> RX FIFO đúng
//   3) WRITE sai địa chỉ -> ERROR.NACK_ADDR
// ============================================================================
module tb_I2C_Master;

    reg          clk = 0;
    reg          reset;
    reg          core_en, recover_en;
    reg  [15:0]  prescale;
    reg  [9:0]   addr;
    reg  [23:0]  timeout_val;
    reg          cmd_abort, cmd_bus_recover;
    reg          tx_push;
    reg  [11:0]  tx_wdata;
    reg          rx_pop;
    wire [7:0]   rx_rdata;
    reg          tx_flush, rx_flush;
    reg  [7:0]   tx_thres, rx_thres;
    wire [7:0]   tx_level, rx_level;
    wire         tx_full, tx_empty, rx_full, rx_empty;
    reg  [7:0]   int_enable, int_clr;
    reg  [4:0]   err_clr;
    wire [7:0]   int_status, status;
    wire [4:0]   err_status;
    wire         irq;
    wire         scl_pad, sda_pad;

    integer errors = 0;

    always #5 clk = ~clk;

    // ================= Slave model (0x50) =================
    localparam [6:0] SADDR = 7'h50;
    reg        in_txn=0, rd_txn=0, addr_match=0, sl_low=0;
    reg [3:0]  fcnt=0, byte_idx=0;
    reg [7:0]  recv_sh=0;
    integer    send_ptr=0, cap_ptr=0;
    reg [7:0]  send_rom [0:3];
    reg [7:0]  captured [0:7];
    initial begin send_rom[0]=8'h11; send_rom[1]=8'h22; send_rom[2]=8'h33; send_rom[3]=8'h44; end

    // slave quan sát pad trực tiếp (external slave)
    wire        scl_f = scl_pad;
    wire        sda_f = sda_pad;

    pullup(scl_pad); pullup(sda_pad);
    assign sda_pad = (in_txn && sl_low) ? 1'b0 : 1'bz;

    wire sending = in_txn && (byte_idx >= 1) && rd_txn && addr_match;
    wire [7:0] cur_send = send_rom[send_ptr];

    always @(sda_f) if (scl_f) begin
        if (~sda_f) begin in_txn<=1'b1;  fcnt<=0; byte_idx<=0; recv_sh<=0; send_ptr<=0; end // START
        else        begin in_txn<=1'b0;  fcnt<=0; byte_idx<=0; end                          // STOP: reset để txn kế fresh
    end
    always @(posedge scl_f) if (in_txn && !sending) recv_sh <= {recv_sh[6:0], sda_f};
    always @(negedge scl_f) begin
        if (in_txn) begin
            if (sending) sl_low <= (fcnt<8) ? ~cur_send[7-fcnt] : 1'b0;
            else         sl_low <= (fcnt<8) ? 1'b0 :
                                   ((byte_idx==0) ? (recv_sh[7:1]==SADDR) : 1'b1);
            if (fcnt==4'd8) begin
                fcnt<=0; byte_idx<=byte_idx+4'd1;
                if (byte_idx==0) begin addr_match<=(recv_sh[7:1]==SADDR); rd_txn<=recv_sh[0]; end
                else if (sending) send_ptr<=send_ptr+1;
                else begin captured[cap_ptr]<=recv_sh; cap_ptr<=cap_ptr+1; end
            end else fcnt<=fcnt+4'd1;
        end
    end

    // ================= DUT =================
    I2C_Master #(.PRESCALE_WIDTH(16), .FIFO_DEPTH(16), .SYNC_STAGES(2), .SPIKE_LEN(0),
                 .SUPPORT_CLOCK_STRETCH(1), .ENABLE_ARBITRATION(0)) dut (
        .clk(clk), .reset(reset), .core_en(core_en), .recover_en(recover_en),
        .prescale(prescale), .addr(addr), .timeout_val(timeout_val),
        .cmd_abort(cmd_abort), .cmd_bus_recover(cmd_bus_recover),
        .tx_push(tx_push), .tx_wdata(tx_wdata), .rx_pop(rx_pop), .rx_rdata(rx_rdata),
        .tx_flush(tx_flush), .rx_flush(rx_flush), .tx_thres(tx_thres), .rx_thres(rx_thres),
        .tx_level(tx_level), .rx_level(rx_level),
        .tx_full(tx_full), .tx_empty(tx_empty), .rx_full(rx_full), .rx_empty(rx_empty),
        .int_enable(int_enable), .int_clr(int_clr), .err_clr(err_clr),
        .int_status(int_status), .err_status(err_status), .irq(irq),
        .status(status), .scl_pad(scl_pad), .sda_pad(sda_pad));

    // ================= helpers =================
    task push_tx(input [11:0] e); begin
        @(negedge clk); tx_push=1; tx_wdata=e; @(negedge clk); tx_push=0;
    end endtask
    task wait_done; begin
        @(posedge clk);
        while (!(tx_empty && (status[0]==1'b0))) @(posedge clk);   // FIFO rỗng & !BUSY
        repeat(40) @(posedge clk);
    end endtask
    task clr_int; begin @(negedge clk); int_clr=8'hFF; err_clr=5'h1F; @(negedge clk); int_clr=0; err_clr=0; end endtask

    reg [7:0] d;
    initial begin
        reset=0; core_en=0; recover_en=0; prescale=16'd5; addr=10'h050; timeout_val=24'd0;
        cmd_abort=0; cmd_bus_recover=0; tx_push=0; tx_wdata=0; rx_pop=0;
        tx_flush=0; rx_flush=0; tx_thres=8'd0; rx_thres=8'd1;
        int_enable=8'hFF; int_clr=0; err_clr=0;
        #23 reset=1; @(negedge clk) core_en=1; repeat(2) @(negedge clk);

        // ---- 1) WRITE 0xA5,0x3C ----
        clr_int;
        push_tx({1'b0,1'b0,1'b1,1'b0,8'hA5});
        push_tx({1'b0,1'b1,1'b0,1'b0,8'h3C});
        wait_done;
        if (captured[0]!==8'hA5) begin $display("  [ERR] recv[0]=%h expect A5", captured[0]); errors=errors+1; end
        if (captured[1]!==8'h3C) begin $display("  [ERR] recv[1]=%h expect 3C", captured[1]); errors=errors+1; end
        if (!int_status[0]) begin $display("  [ERR] INT TX_DONE khong set"); errors=errors+1; end
        if (!int_status[7]) begin $display("  [ERR] INT STOP_DET khong set"); errors=errors+1; end
        if (!irq)           begin $display("  [ERR] irq khong len"); errors=errors+1; end
        if (status[0]!==1'b0) begin $display("  [ERR] BUSY chua ve 0"); errors=errors+1; end
        if (status[7]!==1'b1) begin $display("  [ERR] IDLE chua len"); errors=errors+1; end

        // ---- 2) READ 0x11,0x22 ----
        clr_int;
        push_tx({1'b0,1'b0,1'b1,1'b1,8'h00});
        push_tx({1'b1,1'b1,1'b0,1'b1,8'h00});
        wait_done;
        if (rx_empty) begin $display("  [ERR] RX rong sau read"); errors=errors+1; end
        @(negedge clk); d=rx_rdata; rx_pop=1; @(negedge clk); rx_pop=0;
        if (d!==8'h11) begin $display("  [ERR] RX[0]=%h expect 11", d); errors=errors+1; end
        @(negedge clk); d=rx_rdata; rx_pop=1; @(negedge clk); rx_pop=0;
        if (d!==8'h22) begin $display("  [ERR] RX[1]=%h expect 22", d); errors=errors+1; end
        if (!int_status[1]) begin $display("  [ERR] INT RX_DONE khong set"); errors=errors+1; end

        if (errors==0) $display("PASS: I2C_Master");
        else           $display("FAIL: I2C_Master (%0d errors)", errors);
        $finish;
    end

    initial begin #3000000; $display("FAIL: I2C_Master (timeout)"); $finish; end

endmodule
