`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Bit_Controller
// Tích hợp: Clock_Divider + Bit_Controller + SDA/SCL_Controller + Input_Filter
//           + slave model (pull-up + kéo low SDA/SCL).
// Kiểm tra: START, WRITE 8 bit (0xA5), READ bit (ACK & '1'), STOP,
//           clock stretching (slave giữ SCL low -> pause + primitive vẫn xong).
// ============================================================================
module tb_I2C_Bit_Controller;

    // Primitive encodings (khớp DUT)
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    reg         clk = 0;
    reg         reset;
    reg         core_en;

    // command interface
    reg  [2:0]  cmd;
    reg         cmd_valid;
    reg         din;
    wire        cmd_ack;
    wire        dout;
    wire        al;

    // clock divider
    wire [1:0]  phase;
    wire        tick_a, tick_b, tick_c, tick_d;
    wire        pause;

    // line
    wire        scl_oe, sda_oe;
    wire        scl_in, sda_in;
    wire        scl_pad, sda_pad;
    wire        scl_in_raw, sda_in_raw;

    integer     errors = 0;

    always #5 clk = ~clk;

    // Pull-up + slave model
    reg  slave_scl_low = 0;
    reg  slave_sda_low = 0;
    pullup(scl_pad);
    pullup(sda_pad);
    assign scl_pad = slave_scl_low ? 1'b0 : 1'bz;
    assign sda_pad = slave_sda_low ? 1'b0 : 1'bz;

    // -------- DUT chain --------
    I2C_Clock_Divider #(.PRESCALE_WIDTH(16)) u_div (
        .clk(clk), .reset(reset), .enable(core_en), .pause(pause),
        .prescale(16'd7),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d)
    );

    I2C_Bit_Controller #(.SUPPORT_CLOCK_STRETCH(1), .ENABLE_ARBITRATION(0)) u_bit (
        .clk(clk), .reset(reset), .core_en(core_en),
        .phase(phase), .tick_a(tick_a), .tick_b(tick_b), .tick_c(tick_c), .tick_d(tick_d),
        .pause(pause),
        .cmd(cmd), .cmd_valid(cmd_valid), .din(din),
        .cmd_ack(cmd_ack), .dout(dout), .al(al),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_in(scl_in), .sda_in(sda_in)
    );

    I2C_SCL_Controller u_scl (
        .bit_scl_oe(scl_oe), .rec_scl_oe(1'b0), .recovery_active(1'b0),
        .scl_pad(scl_pad), .scl_in_raw(scl_in_raw)
    );
    I2C_SDA_Controller u_sda (
        .bit_sda_oe(sda_oe), .rec_sda_oe(1'b0), .recovery_active(1'b0),
        .sda_pad(sda_pad), .sda_in_raw(sda_in_raw)
    );

    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_scl (
        .clk(clk), .reset(reset), .line_async(scl_in_raw), .line_clean(scl_in));
    I2C_Input_Filter #(.SYNC_STAGES(2), .SPIKE_LEN(0)) f_sda (
        .clk(clk), .reset(reset), .line_async(sda_in_raw), .line_clean(sda_in));

    // -------- Monitors --------
    reg start_detected = 0;
    reg stop_detected  = 0;
    always @(negedge sda_in) if (scl_in) start_detected <= 1'b1;   // SDA↓ khi SCL cao
    always @(posedge sda_in) if (scl_in) stop_detected  <= 1'b1;   // SDA↑ khi SCL cao

    // Reconstruct byte ghi: sample sda_in tại pha C khi đang capture
    reg        capturing = 0;
    reg [7:0]  mon_byte  = 0;
    always @(posedge clk)
        if (tick_c && capturing) mon_byte <= {mon_byte[6:0], sda_in};

    // -------- Helper: chạy 1 primitive --------
    task do_cmd(input [2:0] c, input b);
    begin
        @(negedge clk); cmd = c; din = b; cmd_valid = 1'b1;
        @(posedge cmd_ack);
        @(negedge clk); cmd_valid = 1'b0;
        @(negedge clk);
    end
    endtask

    integer i;
    reg [7:0] wr_val;
    time t_normal, t_stretch;

    initial begin
        reset=0; core_en=0; cmd=0; cmd_valid=0; din=0;
        #23 reset=1;
        @(negedge clk); core_en=1;
        repeat(4) @(negedge clk);

        // 1) START
        do_cmd(CMD_START, 1'b0);
        repeat(4) @(negedge clk);   // chờ filter cho SDA xuống (edge START)
        if (!start_detected) begin $display("  [ERR] khong thay START"); errors=errors+1; end

        // 2) WRITE 8 bit 0xA5 (MSB-first)
        wr_val = 8'hA5;
        capturing = 1; mon_byte = 0;
        for (i=7; i>=0; i=i-1) do_cmd(CMD_WRITE, wr_val[i]);
        capturing = 0;
        if (mon_byte !== wr_val) begin
            $display("  [ERR] WRITE byte = %h, expect %h", mon_byte, wr_val); errors=errors+1;
        end

        // 3a) READ bit: slave ACK (kéo SDA low) -> dout=0
        slave_sda_low = 1;
        do_cmd(CMD_READ, 1'b0);
        if (dout !== 1'b0) begin $display("  [ERR] READ ACK: dout=%b expect 0", dout); errors=errors+1; end
        slave_sda_low = 0;

        // 3b) READ bit: slave thả (pull-up) -> dout=1
        do_cmd(CMD_READ, 1'b0);
        if (dout !== 1'b1) begin $display("  [ERR] READ '1': dout=%b expect 1", dout); errors=errors+1; end

        // 4) STOP
        do_cmd(CMD_STOP, 1'b0);
        repeat(4) @(negedge clk);   // chờ filter cho SDA lên (edge STOP)
        if (!stop_detected) begin $display("  [ERR] khong thay STOP"); errors=errors+1; end

        // 5) Clock stretching: đo thời gian 1 WRITE bình thường vs khi slave giữ SCL
        do_cmd(CMD_START, 1'b0);

        t_normal = $time;
        do_cmd(CMD_WRITE, 1'b1);
        t_normal = $time - t_normal;

        // WRITE có stretch: slave giữ SCL low ngay sau khi DUT thả (tick_b)
        fork
            begin
                t_stretch = $time;
                do_cmd(CMD_WRITE, 1'b1);
                t_stretch = $time - t_stretch;
            end
            begin
                @(posedge tick_b);          // DUT vừa thả SCL
                #1 slave_scl_low = 1;
                repeat(40) @(negedge clk);
                if (!pause) begin $display("  [ERR] stretch: pause khong len"); errors=errors+1; end
                slave_scl_low = 0;
            end
        join

        if (t_stretch <= t_normal) begin
            $display("  [ERR] stretch khong keo dai transfer (norm=%0t stretch=%0t)", t_normal, t_stretch);
            errors=errors+1;
        end

        do_cmd(CMD_STOP, 1'b0);

        if (errors==0) $display("PASS: I2C_Bit_Controller");
        else           $display("FAIL: I2C_Bit_Controller (%0d errors)", errors);
        $finish;
    end

    // safety timeout
    initial begin #200000; $display("  [ERR] TIMEOUT"); $display("FAIL: I2C_Bit_Controller (timeout)"); $finish; end

endmodule
