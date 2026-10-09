// ============================================================================
// Module I2C_Bit_Controller
// ----------------------------------------------------------------------------
// FSM mức BIT (mục C của plan). Nhận primitive từ Byte_Controller, dùng 4 pha
// của I2C_Clock_Divider để canh cạnh SCL và sample SDA.
//
// Primitive (cmd):
//   CMD_START : điều kiện START / repeated START
//   CMD_STOP  : điều kiện STOP
//   CMD_WRITE : ghi 1 bit (= din)
//   CMD_READ  : đọc 1 bit  (-> dout)
//
// Mỗi primitive chạy đúng 1 chu kỳ 4 pha A->B->C->D và kết thúc bằng 1 xung
// `cmd_ack` tại pha D.
//
// Bảng drive (oe=1 => kéo low; oe=0 => thả -> pull-up high):
//   cmd     A (SCL low, set SDA)  B (thả SCL)  C (SCL high)     D
//   WRITE   scl=1, sda=~din       scl=0        arb check        scl=1 (SCL low)
//   READ    scl=1, sda=0(thả)     scl=0        dout<=sda_in     scl=1 (SCL low)
//   START   scl=1, sda=0(thả)     scl=0        --               sda=1,scl=0 (SDA↓/SCL cao)
//   STOP    scl=1, sda=1          scl=0        --               sda=0,scl=0 (SDA↑/SCL cao)
//
// Clock stretching: tại pha B, nếu đã thả SCL (scl_oe=0) mà scl_in vẫn 0
//   -> slave đang giữ SCL -> kéo `pause`=1 để đóng băng Clock_Divider.
//
// Arbitration (chỉ khi ENABLE_ARBITRATION=1): tại pha C khi WRITE din=1
//   (ta thả SDA) mà đọc sda_in=0 -> master khác đang kéo -> al=1.
//
// Handshake: latch cmd tại CẠNH LÊN của cmd_valid (byte controller phải hạ
// cmd_valid giữa 2 lệnh). Khi rảnh, giữ nguyên mức drive cuối (giữ SCL/SDA).
// Reset: active-low.
// ============================================================================
module I2C_Bit_Controller #(

    parameter SUPPORT_CLOCK_STRETCH = 1,
    parameter ENABLE_ARBITRATION    = 0
)
(
    input           clk,
    input           reset,          // active-low
    input           core_en,        // CTRL.EN

    // ---- Clock_Divider interface ----
    input  [1:0]    phase,          // 0=A,1=B,2=C,3=D
    input           tick_a,
    input           tick_b,
    input           tick_c,
    input           tick_d,
    output          pause,          // -> Clock_Divider: freeze (clock stretching)

    // ---- Command interface (Byte_Controller) ----
    input  [2:0]    cmd,
    input           cmd_valid,
    input           din,            // bit ghi (CMD_WRITE)
    output          cmd_ack,        // 1 xung khi primitive hoàn tất
    output          dout,           // bit đọc (CMD_READ), valid tại cmd_ack
    output          al,             // arbitration lost (giữ tới lệnh kế)

    // ---- Line interface (SDA/SCL controllers) ----
    output          scl_oe,         // 1 -> kéo SCL low
    output          sda_oe,         // 1 -> kéo SDA low
    input           scl_in,         // đã lọc
    input           sda_in          // đã lọc
);

    // ========================================================================
    // Encodings
    // ========================================================================
    localparam CMD_IDLE  = 3'd0;
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    localparam PHASE_B = 2'd1;

    // ========================================================================
    // State
    // ========================================================================
    reg [2:0]   cmd_r;
    reg         din_r;
    reg         busy;           // primitive đang chạy
    reg         pending;        // đã latch cmd, chờ tick_a để bắt đầu
    reg         cmd_valid_d;    // phát hiện cạnh lên cmd_valid

    reg         scl_oe_r;
    reg         sda_oe_r;
    reg         dout_r;
    reg         al_r;
    reg         cmd_ack_r;

    wire cmd_req = cmd_valid & ~cmd_valid_d;     // cạnh lên

    // ========================================================================
    // Clock stretching: pha B, đã thả SCL nhưng line vẫn low
    // ========================================================================
    assign pause = (SUPPORT_CLOCK_STRETCH != 0) &&
                    busy && (phase == PHASE_B) &&
                    (scl_oe_r == 1'b0) && (scl_in == 1'b0);

    // ========================================================================
    // Sequential FSM
    // ========================================================================
    always @(posedge clk) begin

        if (!reset) begin
            cmd_r       <= CMD_IDLE;
            din_r       <= 1'b0;
            busy        <= 1'b0;
            pending     <= 1'b0;
            cmd_valid_d <= 1'b0;
            scl_oe_r    <= 1'b0;        // thả -> bus idle high
            sda_oe_r    <= 1'b0;
            dout_r      <= 1'b0;
            al_r        <= 1'b0;
            cmd_ack_r   <= 1'b0;
        end

        else if (!core_en) begin
            // Core tắt -> thả bus, huỷ mọi hoạt động
            busy        <= 1'b0;
            pending     <= 1'b0;
            scl_oe_r    <= 1'b0;
            sda_oe_r    <= 1'b0;
            cmd_ack_r   <= 1'b0;
            al_r        <= 1'b0;
            cmd_valid_d <= cmd_valid;
        end

        else begin
            cmd_valid_d <= cmd_valid;
            cmd_ack_r   <= 1'b0;        // mặc định: xung 1 cycle

            // ---- Latch command (cạnh lên cmd_valid) ----
            if (cmd_req && !busy && !pending && (cmd != CMD_IDLE)) begin
                cmd_r   <= cmd;
                din_r   <= din;
                pending <= 1'b1;
                al_r    <= 1'b0;        // xoá AL cho lệnh mới
            end

            // ---- Bắt đầu tại pha A: set SCL + SDA theo lệnh ----
            // START "clean": THẢ SCL (giữ cao) -> không tạo xung SCL giả trước
            // điều kiện START. Các lệnh khác kéo SCL low để đổi SDA an toàn.
            if (pending && tick_a) begin
                pending <= 1'b0;
                busy    <= 1'b1;

                case (cmd_r)
                    CMD_START: begin scl_oe_r <= 1'b0; sda_oe_r <= 1'b0; end // SCL cao, SDA cao
                    CMD_STOP:  begin scl_oe_r <= 1'b1; sda_oe_r <= 1'b1; end // SCL low, SDA low
                    CMD_WRITE: begin scl_oe_r <= 1'b1; sda_oe_r <= ~din_r; end
                    CMD_READ:  begin scl_oe_r <= 1'b1; sda_oe_r <= 1'b0;  end
                    default:   begin scl_oe_r <= 1'b1; sda_oe_r <= 1'b0;  end
                endcase
            end

            // ---- Pha B: thả SCL (cạnh lên SCL) ----
            if (busy && tick_b) begin
                scl_oe_r <= 1'b0;
            end

            // ---- Pha C: SCL cao, sample ----
            if (busy && tick_c) begin
                case (cmd_r)
                    CMD_READ: dout_r <= sda_in;
                    CMD_WRITE: begin
                        if ((ENABLE_ARBITRATION != 0) && din_r && (sda_in == 1'b0))
                            al_r <= 1'b1;
                    end
                    default: ;
                endcase
            end

            // ---- Pha D: kết thúc primitive ----
            if (busy && tick_d) begin
                case (cmd_r)
                    CMD_START: begin
                        // SDA xuống low khi SCL còn cao -> START edge
                        sda_oe_r <= 1'b1;
                        scl_oe_r <= 1'b0;
                    end
                    CMD_STOP: begin
                        // SDA lên high khi SCL còn cao -> STOP edge
                        sda_oe_r <= 1'b0;
                        scl_oe_r <= 1'b0;
                    end
                    CMD_WRITE: scl_oe_r <= 1'b1;    // SCL low, giữ SDA
                    CMD_READ:  scl_oe_r <= 1'b1;    // SCL low
                    default:   scl_oe_r <= 1'b1;
                endcase

                busy      <= 1'b0;
                cmd_ack_r <= 1'b1;
            end
        end
    end

    // ========================================================================
    // Outputs
    // ========================================================================
    assign scl_oe  = scl_oe_r;
    assign sda_oe  = sda_oe_r;
    assign dout    = dout_r;
    assign al      = al_r;
    assign cmd_ack = cmd_ack_r;

endmodule
