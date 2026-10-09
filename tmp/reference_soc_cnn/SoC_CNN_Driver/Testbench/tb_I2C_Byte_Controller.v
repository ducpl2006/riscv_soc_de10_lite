`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Byte_Controller
// Tích hợp Clock_Divider + Byte_Controller + Bit_Controller + line ctrl + filter
// + slave model. Kiểm tra: START, WRITE byte + ACK, WRITE byte + NACK,
// READ byte (slave gửi) + master ACK, STOP.
// ============================================================================
module tb_I2C_Byte_Controller;

    localparam BC_START = 2'd0;
    localparam BC_STOP  = 2'd1;
    localparam BC_WRITE = 2'd2;
    localparam BC_READ  = 2'd3;

    reg         clk = 0;
    reg         reset;
    reg         core_en;

    // byte command interface
    reg  [1:0]  cmd;
    reg         cmd_valid;
    reg  [7:0]  wr_data;
    reg         ack_in;
    wire        cmd_ack;
    wire [7:0]  rd_data;
    wire        rx_ack;
    wire        al;

    // internal chain wires
    wire [2:0]  bit_cmd;
    wire        bit_cmd_valid, bit_din, bit_cmd_ack, bit_dout, bit_al;
    wire [1:0]  phase;
    wire        tick_a, tick_b, tick_c, tick_d, pause;
    wire        scl_oe, sda_oe, scl_in, sda_in;
    wire        scl_pad, sda_pad, scl_raw, sda_raw;

    integer     errors = 0;

    always #5 clk = ~clk;

    // -------- pull-up + slave --------
    reg  [7:0]  sl_send  = 0;   // byte slave gửi (READ)
    reg         sl_dir   = 0;   // 0=master write, 1=master read
    reg         sl_ack   = 1;   // slave ACK khi master write (1=ACK kéo low)
    reg  [3:0]  fcnt     = 0;
    reg         in_txn   = 0;
    reg         sl_low   = 0;

    pullup(scl_pad);
    pullup(sda_pad);
    assign sda_pad = (in_txn && sl_low) ? 1'b0 : 1'bz;

    // START/STOP detect. Tại START reset fcnt=0 để căn chỉnh lại đầu mỗi
    // transaction (SCL đang cao lúc này -> không đụng cạnh xuống SCL).
    always @(sda_in) begin
        if (scl_in) begin
            if (~sda_in) begin in_txn <= 1'b1; fcnt <= 4'd0; end   // START
            else               in_txn <= 1'b0;                     // STOP
        end
    end

    // present bit tại cạnh xuống SCL, giữ qua nửa cao (fcnt = bit index)
    always @(negedge scl_in) begin
        if (in_txn) begin
            if (sl_dir) sl_low <= (fcnt < 8) ? ~sl_send[7 - fcnt] : 1'b0;  // read: gửi bit / thả ack
            else        sl_low <= (fcnt < 8) ? 1'b0 : sl_ack;            // write: thả data / ack bit8
            fcnt <= (fcnt == 4'd8) ? 4'd0 : fcnt + 4'd1;
        end
    end

    // -------- DUT chain --------
    I2C_Clock_Divider #(.PRESCALE_WIDTH(16)) u_div (
        .clk(clk), .reset(reset), .enable(core_en), .pause(pause), .prescale(16'd7),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d));

    I2C_Byte_Controller u_byte (
        .clk(clk), .reset(reset), .core_en(core_en),
        .cmd(cmd), .cmd_valid(cmd_valid), .wr_data(wr_data), .ack_in(ack_in),
        .cmd_ack(cmd_ack), .rd_data(rd_data), .rx_ack(rx_ack), .al(al),
        .bit_cmd(bit_cmd), .bit_cmd_valid(bit_cmd_valid), .bit_din(bit_din),
        .bit_cmd_ack(bit_cmd_ack), .bit_dout(bit_dout), .bit_al(bit_al));

    I2C_Bit_Controller #(.SUPPORT_CLOCK_STRETCH(1), .ENABLE_ARBITRATION(0)) u_bit (
        .clk(clk), .reset(reset), .core_en(core_en),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d),
        .pause(pause),
        .cmd(bit_cmd), .cmd_valid(bit_cmd_valid), .din(bit_din),
        .cmd_ack(bit_cmd_ack), .dout(bit_dout), .al(bit_al),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_in(scl_in), .sda_in(sda_in));

    I2C_SCL_Controller u_scl (.bit_scl_oe(scl_oe), .rec_scl_oe(1'b0), .recovery_active(1'b0),
        .scl_pad(scl_pad), .scl_in_raw(scl_raw));
    I2C_SDA_Controller u_sda (.bit_sda_oe(sda_oe), .rec_sda_oe(1'b0), .recovery_active(1'b0),
        .sda_pad(sda_pad), .sda_in_raw(sda_raw));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_scl (.clk(clk), .reset(reset),
        .line_async(scl_raw), .line_clean(scl_in));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_sda (.clk(clk), .reset(reset),
        .line_async(sda_raw), .line_clean(sda_in));

    // -------- monitor byte master ghi: sample tại tick_c (8 bit đầu) --------
    reg        capturing = 0;
    reg [3:0]  capcnt = 0;
    reg [7:0]  mon = 0;
    always @(posedge clk)
        if (tick_c && capturing && capcnt < 8) begin
            mon <= {mon[6:0], sda_in};
            capcnt <= capcnt + 1;
        end

    // -------- helper --------
    task do_byte(input [1:0] op, input [7:0] wd, input a_in);
    begin
        @(negedge clk); cmd=op; wr_data=wd; ack_in=a_in; cmd_valid=1'b1;
        @(posedge cmd_ack); @(negedge clk); cmd_valid=1'b0; @(negedge clk);
    end
    endtask

    initial begin
        reset=0; core_en=0; cmd=0; cmd_valid=0; wr_data=0; ack_in=0;
        #23 reset=1; @(negedge clk) core_en=1; repeat(4) @(negedge clk);

        // ===== Transaction 1: WRITE (ACK) + WRITE (NACK) =====
        sl_dir=0; sl_ack=1;
        do_byte(BC_START, 8'h00, 1'b0);

        capturing=1; capcnt=0; mon=0;
        do_byte(BC_WRITE, 8'hA5, 1'b0);
        capturing=0;
        if (mon !== 8'hA5) begin $display("  [ERR] WRITE byte=%h expect A5", mon); errors=errors+1; end
        if (rx_ack !== 1'b0) begin $display("  [ERR] rx_ack=%b expect 0 (ACK)", rx_ack); errors=errors+1; end

        sl_ack=0;                                   // slave NACK byte kế
        do_byte(BC_WRITE, 8'h3C, 1'b0);
        if (rx_ack !== 1'b1) begin $display("  [ERR] rx_ack=%b expect 1 (NACK)", rx_ack); errors=errors+1; end

        do_byte(BC_STOP, 8'h00, 1'b0);

        // ===== Transaction 2: READ (slave gửi 0x5A, master ACK) =====
        sl_dir=1; sl_send=8'h5A;                     // set hướng TRƯỚC start
        do_byte(BC_START, 8'h00, 1'b0);
        do_byte(BC_READ, 8'h00, 1'b0);
        if (rd_data !== 8'h5A) begin $display("  [ERR] READ byte=%h expect 5A", rd_data); errors=errors+1; end
        do_byte(BC_STOP, 8'h00, 1'b0);

        if (errors==0) $display("PASS: I2C_Byte_Controller");
        else           $display("FAIL: I2C_Byte_Controller (%0d errors)", errors);
        $finish;
    end

    initial begin #500000; $display("FAIL: I2C_Byte_Controller (timeout)"); $finish; end

endmodule
