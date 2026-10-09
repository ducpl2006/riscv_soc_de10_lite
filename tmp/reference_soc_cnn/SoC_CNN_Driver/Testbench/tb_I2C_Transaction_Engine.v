`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Transaction_Engine
// Tích hợp toàn bộ core I2C + FIFO_Controller + slave model có địa chỉ (0x50).
// Kiểm tra:
//   - WRITE transaction: START, addr+W, 2 data byte, STOP -> slave nhận đúng
//   - READ transaction : START, addr+R, 2 data byte (ACK, NACK), STOP -> RX FIFO đúng
// ============================================================================
module tb_I2C_Transaction_Engine;

    reg         clk = 0;
    reg         reset;
    reg         core_en;

    // TX/CMD FIFO push (tb -> FIFO)
    reg         tx_push;
    reg  [11:0] tx_wdata;
    // RX FIFO pop (FIFO -> tb)
    reg         rx_pop;
    wire [7:0]  rx_rdata;
    wire        rx_empty;

    // engine <-> FIFO
    wire        tx_pop, tx_empty;
    wire [11:0] tx_entry;
    wire        rx_push;
    wire [7:0]  rx_wdata;
    wire [7:0]  tx_level, rx_level;

    // engine <-> byte
    wire [1:0]  byte_cmd;
    wire        byte_cmd_valid, byte_ack_in, byte_cmd_ack, byte_rx_ack, byte_al;
    wire [7:0]  byte_wr_data, byte_rd_data;

    // byte <-> bit
    wire [2:0]  bit_cmd;
    wire        bit_cmd_valid, bit_din, bit_cmd_ack, bit_dout, bit_al;

    // clock divider / line
    wire [1:0]  phase;
    wire        tick_a, tick_b, tick_c, tick_d, pause;
    wire        scl_oe, sda_oe, scl_in, sda_in;
    wire        scl_pad, sda_pad, scl_raw, sda_raw;

    // engine status
    wire        busy, ev_tx_done, ev_rx_done, ev_nack, ev_stop, ev_arb_lost, rxack;

    integer errors = 0;

    always #5 clk = ~clk;

    // ================= Slave model (địa chỉ 0x50) =================
    localparam [6:0] SADDR = 7'h50;
    reg        in_txn=0, rd_txn=0, addr_match=0, sl_low=0;
    reg [3:0]  fcnt=0, byte_idx=0;
    reg [7:0]  recv_sh=0;
    integer    send_ptr=0, cap_ptr=0;
    reg [7:0]  send_rom [0:3];
    reg [7:0]  captured [0:7];

    initial begin send_rom[0]=8'h11; send_rom[1]=8'h22; send_rom[2]=8'h33; send_rom[3]=8'h44; end

    pullup(scl_pad); pullup(sda_pad);
    assign sda_pad = (in_txn && sl_low) ? 1'b0 : 1'bz;

    wire sending = in_txn && (byte_idx >= 1) && rd_txn && addr_match;
    wire [7:0] cur_send = send_rom[send_ptr];

    // START/STOP
    always @(sda_in) begin
        if (scl_in) begin
            if (~sda_in) begin in_txn<=1'b1; fcnt<=0; byte_idx<=0; recv_sh<=0; send_ptr<=0; cap_ptr<=0; end
            else in_txn<=1'b0;
        end
    end

    // sample master writes tại cạnh lên (khi recv)
    always @(posedge scl_in)
        if (in_txn && !sending) recv_sh <= {recv_sh[6:0], sda_in};

    // present + advance tại cạnh xuống
    always @(negedge scl_in) begin
        if (in_txn) begin
            if (sending)
                sl_low <= (fcnt < 8) ? ~cur_send[7 - fcnt] : 1'b0;          // gửi data / thả ack
            else
                sl_low <= (fcnt < 8) ? 1'b0 :                                // recv data: thả
                          ((byte_idx == 0) ? (recv_sh[7:1] == SADDR)         // addr: ACK nếu khớp
                                           : 1'b1);                          // data write: ACK
            if (fcnt == 4'd8) begin
                fcnt <= 4'd0;
                byte_idx <= byte_idx + 4'd1;
                if (byte_idx == 0) begin
                    addr_match <= (recv_sh[7:1] == SADDR);
                    rd_txn     <= recv_sh[0];
                end else if (sending) begin
                    send_ptr <= send_ptr + 1;
                end else begin
                    captured[cap_ptr] <= recv_sh;
                    cap_ptr <= cap_ptr + 1;
                end
            end else fcnt <= fcnt + 4'd1;
        end
    end

    // ================= DUT chain =================
    I2C_FIFO_Controller #(.TX_WIDTH(12), .RX_WIDTH(8), .DEPTH(16)) u_fifo (
        .clk(clk), .reset(reset), .tx_flush(1'b0), .rx_flush(1'b0),
        .tx_push(tx_push), .tx_wdata(tx_wdata), .tx_pop(tx_pop),
        .tx_rdata(tx_entry), .tx_empty(tx_empty), .tx_full(),
        .rx_push(rx_push), .rx_wdata(rx_wdata), .rx_pop(rx_pop),
        .rx_rdata(rx_rdata), .rx_empty(rx_empty), .rx_full(),
        .tx_level(tx_level), .rx_level(rx_level),
        .tx_thres(8'd0), .rx_thres(8'd1), .tx_thres_irq(), .rx_thres_irq());

    I2C_Transaction_Engine u_eng (
        .clk(clk), .reset(reset), .core_en(core_en), .abort(1'b0),
        .addr(10'h050),
        .tx_empty(tx_empty), .tx_entry(tx_entry), .tx_pop(tx_pop),
        .rx_push(rx_push), .rx_wdata(rx_wdata),
        .byte_cmd(byte_cmd), .byte_cmd_valid(byte_cmd_valid), .byte_wr_data(byte_wr_data),
        .byte_ack_in(byte_ack_in), .byte_cmd_ack(byte_cmd_ack), .byte_rd_data(byte_rd_data),
        .byte_rx_ack(byte_rx_ack), .byte_al(byte_al),
        .busy(busy), .ev_tx_done(ev_tx_done), .ev_rx_done(ev_rx_done), .ev_nack(ev_nack),
        .ev_stop(ev_stop), .ev_arb_lost(ev_arb_lost), .rxack(rxack));

    I2C_Byte_Controller u_byte (
        .clk(clk), .reset(reset), .core_en(core_en),
        .cmd(byte_cmd), .cmd_valid(byte_cmd_valid), .wr_data(byte_wr_data), .ack_in(byte_ack_in),
        .cmd_ack(byte_cmd_ack), .rd_data(byte_rd_data), .rx_ack(byte_rx_ack), .al(byte_al),
        .bit_cmd(bit_cmd), .bit_cmd_valid(bit_cmd_valid), .bit_din(bit_din),
        .bit_cmd_ack(bit_cmd_ack), .bit_dout(bit_dout), .bit_al(bit_al));

    I2C_Bit_Controller #(.SUPPORT_CLOCK_STRETCH(1), .ENABLE_ARBITRATION(0)) u_bit (
        .clk(clk), .reset(reset), .core_en(core_en),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d), .pause(pause),
        .cmd(bit_cmd), .cmd_valid(bit_cmd_valid), .din(bit_din),
        .cmd_ack(bit_cmd_ack), .dout(bit_dout), .al(bit_al),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_in(scl_in), .sda_in(sda_in));

    I2C_Clock_Divider #(.PRESCALE_WIDTH(16)) u_div (
        .clk(clk), .reset(reset), .enable(core_en), .pause(pause), .prescale(16'd5),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d));

    I2C_SCL_Controller u_scl (.bit_scl_oe(scl_oe), .rec_scl_oe(1'b0), .recovery_active(1'b0),
        .scl_pad(scl_pad), .scl_in_raw(scl_raw));
    I2C_SDA_Controller u_sda (.bit_sda_oe(sda_oe), .rec_sda_oe(1'b0), .recovery_active(1'b0),
        .sda_pad(sda_pad), .sda_in_raw(sda_raw));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_scl (.clk(clk), .reset(reset), .line_async(scl_raw), .line_clean(scl_in));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_sda (.clk(clk), .reset(reset), .line_async(sda_raw), .line_clean(sda_in));

    // ================= helpers =================
    task push_tx(input [11:0] e); begin
        @(negedge clk); tx_push=1; tx_wdata=e; @(negedge clk); tx_push=0;
    end endtask

    task wait_done; begin
        @(posedge clk);
        while (!(tx_empty && !busy)) @(posedge clk);
        repeat(30) @(posedge clk);
    end endtask

    reg [7:0] d;
    initial begin
        reset=0; core_en=0; tx_push=0; tx_wdata=0; rx_pop=0;
        #23 reset=1; @(negedge clk) core_en=1; repeat(2) @(negedge clk);

        // ===== WRITE transaction: addr 0x50, data A5, 3C =====
        // entry = {NACK, STOP, START, CMD, DATA[7:0]}
        push_tx({1'b0,1'b0,1'b1,1'b0,8'hA5});   // START + write A5
        push_tx({1'b0,1'b1,1'b0,1'b0,8'h3C});   // write 3C + STOP
        wait_done;
        if (captured[0]!==8'hA5) begin $display("  [ERR] slave recv[0]=%h expect A5", captured[0]); errors=errors+1; end
        if (captured[1]!==8'h3C) begin $display("  [ERR] slave recv[1]=%h expect 3C", captured[1]); errors=errors+1; end

        // ===== READ transaction: addr 0x50, đọc 2 byte (ACK, NACK) =====
        push_tx({1'b0,1'b0,1'b1,1'b1,8'h00});   // START + read (master ACK)
        push_tx({1'b1,1'b1,1'b0,1'b1,8'h00});   // read + NACK + STOP
        wait_done;
        if (rx_empty) begin $display("  [ERR] RX FIFO rong sau read"); errors=errors+1; end
        // pop byte0
        @(negedge clk); d=rx_rdata; rx_pop=1; @(negedge clk); rx_pop=0;
        if (d!==8'h11) begin $display("  [ERR] RX[0]=%h expect 11", d); errors=errors+1; end
        @(negedge clk); d=rx_rdata; rx_pop=1; @(negedge clk); rx_pop=0;
        if (d!==8'h22) begin $display("  [ERR] RX[1]=%h expect 22", d); errors=errors+1; end

        if (errors==0) $display("PASS: I2C_Transaction_Engine");
        else           $display("FAIL: I2C_Transaction_Engine (%0d errors)", errors);
        $finish;
    end

    initial begin #2000000; $display("FAIL: I2C_Transaction_Engine (timeout)"); $finish; end

endmodule
