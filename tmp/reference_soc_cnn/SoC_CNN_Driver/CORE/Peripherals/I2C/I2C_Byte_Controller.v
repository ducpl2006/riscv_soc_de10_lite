// ============================================================================
// Module I2C_Byte_Controller
// ----------------------------------------------------------------------------
// FSM mức BYTE (mục C.3 của plan). Nhận lệnh byte từ Transaction_Engine, điều
// phối I2C_Bit_Controller phát chuỗi primitive, quản lý Shift_Register.
//
// Lệnh byte (cmd):
//   BC_START : phát START / repeated START      (1 primitive START)
//   BC_STOP  : phát STOP                         (1 primitive STOP)
//   BC_WRITE : ghi 1 byte (wr_data) MSB-first    (8 WRITE + 1 READ đọc ACK)
//              -> rx_ack = ACK từ slave (0=ACK, 1=NACK)
//   BC_READ  : đọc 1 byte                        (8 READ + 1 WRITE gửi ACK)
//              -> rd_data = byte nhận; ack_in = ACK/NACK master gửi (0=ACK,1=NACK)
//
// Sequencer generic (issue/wait) dùng cho mọi lệnh:
//   S_ISSUE : nạp bit_cmd/bit_din theo (op, step), bật bit_cmd_valid
//   S_WAIT  : chờ bit_cmd_ack -> xử lý (shift/capture) -> step kế hoặc DONE
//
// Handshake trên (Transaction_Engine): latch tại cạnh lên cmd_valid, trả 1 xung
// cmd_ack. Handshake dưới (Bit_Controller): pulse bit_cmd_valid, chờ bit_cmd_ack;
// có 1 cycle bit_cmd_valid=0 giữa 2 primitive để Bit_Controller nhận cạnh lên.
//
// Reset: active-low.
// ============================================================================
module I2C_Byte_Controller (
    input           clk,
    input           reset,          // active-low
    input           core_en,

    // ---- Command interface (Transaction_Engine) ----
    input  [1:0]    cmd,
    input           cmd_valid,
    input  [7:0]    wr_data,
    input           ack_in,         // ACK/NACK master gửi sau READ (0=ACK,1=NACK)
    output          cmd_ack,
    output [7:0]    rd_data,
    output          rx_ack,         // ACK slave sau WRITE (0=ACK,1=NACK)
    output          al,             // arbitration lost

    // ---- Bit_Controller interface ----
    output [2:0]    bit_cmd,
    output          bit_cmd_valid,
    output          bit_din,
    input           bit_cmd_ack,
    input           bit_dout,
    input           bit_al
);

    // ---- Byte command encodings ----
    localparam BC_START = 2'd0;
    localparam BC_STOP  = 2'd1;
    localparam BC_WRITE = 2'd2;
    localparam BC_READ  = 2'd3;

    // ---- Bit primitive encodings (khớp I2C_Bit_Controller) ----
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    // ---- FSM states ----
    localparam S_IDLE  = 2'd0;
    localparam S_ISSUE = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0]   state;
    reg [1:0]   op;
    reg [3:0]   step;           // 0..8
    reg         rx_ack_r;
    reg         al_r;
    reg         cmd_ack_r;

    reg         bcv;            // bit_cmd_valid
    reg [2:0]   bit_cmd_r;
    reg         bit_din_r;

    reg         cmd_valid_d;
    wire        cmd_req = cmd_valid & ~cmd_valid_d;

    // last step: WRITE/READ = 8 (data 0..7 + ack ở 8); START/STOP = 0
    wire [3:0]  last_step = ((op == BC_WRITE) || (op == BC_READ)) ? 4'd8 : 4'd0;

    // ========================================================================
    // Shift Register (MSB-first)
    // ========================================================================
    wire        sh_bit_out;
    wire [7:0]  sh_data_out;

    // load khi latch lệnh WRITE; shift sau mỗi data-bit (0..7)
    wire sh_load  = (state == S_IDLE) && cmd_req && (cmd == BC_WRITE);
    wire sh_shift = (state == S_WAIT) && bit_cmd_ack && (step < 4'd8) &&
                    ((op == BC_WRITE) || (op == BC_READ));
    wire sh_shin  = (op == BC_READ) ? bit_dout : 1'b0;

    I2C_Shift_Register u_shift (
        .clk(clk), .reset(reset),
        .load(sh_load), .data_in(wr_data),
        .shift(sh_shift), .shift_in_bit(sh_shin),
        .bit_out(sh_bit_out), .data_out(sh_data_out)
    );

    // ========================================================================
    // FSM
    // ========================================================================
    always @(posedge clk) begin

        if (!reset) begin
            state       <= S_IDLE;
            op          <= BC_START;
            step        <= 4'd0;
            rx_ack_r    <= 1'b0;
            al_r        <= 1'b0;
            cmd_ack_r   <= 1'b0;
            bcv         <= 1'b0;
            bit_cmd_r   <= 3'd0;
            bit_din_r   <= 1'b0;
            cmd_valid_d <= 1'b0;
        end

        else if (!core_en) begin
            state       <= S_IDLE;
            cmd_ack_r   <= 1'b0;
            bcv         <= 1'b0;
            al_r        <= 1'b0;
            cmd_valid_d <= cmd_valid;
        end

        else begin
            cmd_valid_d <= cmd_valid;
            cmd_ack_r   <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                S_IDLE: begin
                    if (cmd_req) begin
                        op     <= cmd;
                        step   <= 4'd0;
                        al_r   <= 1'b0;
                        state  <= S_ISSUE;
                    end
                end

                // ----------------------------------------------------------------
                // Nạp bit_cmd/bit_din theo (op, step), phát bit_cmd_valid
                // ----------------------------------------------------------------
                S_ISSUE: begin
                    bcv <= 1'b1;
                    case (op)
                        BC_START: begin bit_cmd_r <= CMD_START; bit_din_r <= 1'b1; end
                        BC_STOP:  begin bit_cmd_r <= CMD_STOP;  bit_din_r <= 1'b1; end
                        BC_WRITE: begin
                            if (step < 4'd8) begin
                                bit_cmd_r <= CMD_WRITE; 
                                bit_din_r <= sh_bit_out;
                            end else begin
                                bit_cmd_r <= CMD_READ;  
                                bit_din_r <= 1'b1;  // đọc ACK
                            end
                        end
                        BC_READ: begin
                            if (step < 4'd8) begin
                                bit_cmd_r <= CMD_READ;  
                                bit_din_r <= 1'b1;
                            end else begin
                                bit_cmd_r <= CMD_WRITE; 
                                bit_din_r <= ack_in; // gửi ACK/NACK
                            end
                        end
                    endcase
                    state <= S_WAIT;
                end

                // ----------------------------------------------------------------
                // Chờ primitive xong -> xử lý, sang step kế hoặc DONE
                // ----------------------------------------------------------------
                S_WAIT: begin
                    if (bit_cmd_ack) begin
                        bcv <= 1'b0;
                        if (bit_al) al_r <= 1'b1;

                        // capture ACK từ slave (WRITE, step 8)
                        if ((op == BC_WRITE) && (step == 4'd8))
                            rx_ack_r <= bit_dout;

                        if (step == last_step)
                            state <= S_DONE;
                        else begin
                            step  <= step + 4'd1;
                            state <= S_ISSUE;
                        end
                    end
                end

                // ----------------------------------------------------------------
                S_DONE: begin
                    cmd_ack_r <= 1'b1;
                    state     <= S_IDLE;
                end

            endcase
        end
    end

    // ========================================================================
    // Outputs
    // ========================================================================
    assign bit_cmd       = bit_cmd_r;
    assign bit_cmd_valid = bcv;
    assign bit_din       = bit_din_r;

    assign cmd_ack = cmd_ack_r;
    assign rd_data = sh_data_out;
    assign rx_ack  = rx_ack_r;
    assign al      = al_r;

endmodule
