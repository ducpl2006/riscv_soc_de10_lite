`default_nettype none

// =============================================================================
// Module      : soc_i2c_master
// Chức năng   : I2C master theo từng byte, firmware hiện dùng giao tiếp INA228.
// Purpose: byte transfer, watchdog và phục hồi bus một master.
// Clock: clk_i cạnh lên. Reset: rst_i synchronous active-high, nhả open-drain.
// Inputs: native bus offset 12 bit, SCL/SDA đã đồng bộ. Outputs: response/drive-low.
// Protocol: MMIO hoàn tất tại req && ready; tác dụng phụ chỉ khi !err.
// Latency: read/no-op/error zero wait; DATA/CMD có thể chờ busy, RECOVER được ưu tiên.
// Error behavior: offset sai/ghi RO/pending write bị timeout trả ready+err.
//
// Thanh ghi:
//   0x0 DATA   : byte phát; sau lệnh READ chứa byte nhận. Ghi khi busy phải chờ.
//   0x4 CMD    : bit0 START, bit1 STOP, bit2 READ, bit3 NACK sau READ,
//                bit4 CLEAR_DONE, bit5 RECOVER, bit6 CLEAR_ERRORS, bit7 EXECUTE.
//   0x8 STATUS : bit0 busy, bit1 done, bit2 ack_error, bit3 timeout,
//                bit4 recovery_error. Hai cờ mới sticky đến CLEAR_ERRORS/reset.
//   0xC DIVIDER: số chu kỳ clock trong nửa chu kỳ SCL (chỉ đọc).
//
// Nguyên tắc điện:
//   scl_drive_low_o/sda_drive_low_o chỉ ra lệnh kéo thấp. Top-level phải nối
//   open-drain: assign pin = drive_low ? 1'b0 : 1'bz. Cần điện trở pull-up.
//   Phiên bản này không hỗ trợ multi-master; clock stretching được tôn trọng
//   bằng cách chỉ lấy mẫu khi chân SCL thực sự đã lên cao.
// =============================================================================
module soc_i2c_master #(
    // Tần số clk_i tính bằng Hz, dùng tính bộ chia UART/I2C.
    parameter integer CLOCK_HZ = 50000000,
    // Tần số SCL mục tiêu tính bằng Hz; cần CLOCK_HZ >= 4*I2C_HZ.
    parameter integer I2C_HZ   = 100000,
    // Giới hạn một lần chờ SCL/SDA liên tục; 10 ms tại 50 MHz. 0 tắt watchdog.
    // Sàn 1024 clock giữ test/mô hình tần số thấp có thời gian đồng bộ hợp lý.
    parameter integer TIMEOUT_CYCLES = (CLOCK_HZ / 100 > 1024) ? CLOCK_HZ / 100 : 1024
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire        req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire        we_i,
    // Offset byte MMIO: DATA=0x0, CMD=0x4, STATUS=0x8, DIVIDER=0xC.
    input  wire [11:0]  addr_i,
    // Dữ liệu ghi 32 bit; chỉ các byte được wstrb chọn mới được cập nhật.
    input  wire [31:0] wdata_i,
    // Bit n chọn byte [8*n +: 8]; không chọn byte nào vẫn phải kiểm tra quyền/địa chỉ.
    input  wire [3:0]  wstrb_i,
    // Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
    output reg  [31:0] rdata_o,
    // DATA/CMD chờ khi busy; RECOVER được nhận ngay để hủy lệnh đang kẹt.
    output wire        ready_o,
    // Lỗi địa chỉ/quyền hoặc ghi đang chờ bị timeout; xét tại req && ready.
    output wire        err_o,

    // Mức SCL thực tế đã đồng bộ; FSM chờ khi thiết bị giữ SCL thấp.
    input  wire        scl_i,
    // Mức SDA thực tế đã đồng bộ; lấy mẫu bit dữ liệu/ACK từ thiết bị.
    input  wire        sda_i,
    // 1: kéo SCL thấp; 0: nhả high-Z, không chủ động lái mức cao.
    output reg         scl_drive_low_o,
    // 1: kéo SDA thấp; 0: nhả high-Z, cần điện trở pull-up.
    output reg         sda_drive_low_o,
    // 1 khi FSM đang thực hiện lệnh truyền/nhận một byte và START/STOP tùy chọn.
    output wire        busy_o
);

    // Số clock của một nửa chu kỳ SCL danh định, chưa kể clock stretching.
    localparam integer HALF_DIV = (I2C_HZ > 0) ? CLOCK_HZ / (I2C_HZ * 2) : 1;
    // Có thêm chỗ cho HALF_DIV khi chờ SCL/SDA được nhả.
    localparam integer DIV_WIDTH = (HALF_DIV > 1) ? $clog2(HALF_DIV + 1) : 1;
    // Giá trị nạp bộ đếm khi bắt đầu một pha SCL bình thường.
    localparam integer HALF_RELOAD = HALF_DIV - 1;
    localparam integer TIMEOUT_WIDTH = (TIMEOUT_CYCLES > 1) ? $clog2(TIMEOUT_CYCLES) : 1;

    // synthesis translate_off
    initial begin
        if (CLOCK_HZ <= 0 || I2C_HZ <= 0 || HALF_DIV < 2 || TIMEOUT_CYCLES < 0)
            $fatal(1, "soc_i2c_master: CLOCK_HZ must be at least 4 * I2C_HZ");
    end
    // synthesis translate_on

    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_START_A    = 4'd1,
        ST_START_B    = 4'd2,
        ST_BIT_LOW    = 4'd3,
        ST_BIT_HIGH   = 4'd4,
        ST_ACK_LOW    = 4'd5,
        ST_ACK_HIGH   = 4'd6,
        ST_STOP_A     = 4'd7,
        ST_STOP_B     = 4'd8,
        ST_STOP_C     = 4'd9,
        ST_COMPLETE   = 4'd10,
        ST_START_PRE  = 4'd11,
        ST_REC_LOW    = 4'd12,
        ST_REC_HIGH   = 4'd13;

    // Trạng thái FSM tạo START, 8 bit dữ liệu, ACK/NACK và STOP.
    reg [3:0] state_q;
    // Bộ đếm lùi cho nửa chu kỳ SCL; được giữ/nạp lại khi bus kéo dài pha chờ.
    reg [DIV_WIDTH-1:0] divider_q;
    // Byte DATA đã ghi, phát MSB trước khi thực hiện lệnh write.
    reg [7:0] tx_data_q;
    // Byte nhận được; phần mềm đọc qua DATA sau lệnh read.
    reg [7:0] rx_data_q;
    // Chỉ số bit đang truyền/nhận, đếm từ 7 xuống 0 (MSB trước).
    reg [2:0] bit_index_q;
    // Lệnh đã chốt: 1 nhận byte, 0 phát tx_data_q.
    reg command_read_q;
    // Lệnh đã chốt: tạo STOP sau byte/ACK khi bằng 1.
    reg command_stop_q;
    // Lệnh read đã chốt: 1 gửi NACK, 0 gửi ACK sau byte nhận.
    reg command_nack_q;
    // FSM đang chạy; chặn ghi DATA/CMD byte thấp cho đến khi hoàn tất.
    reg busy_q;
    // Cờ hoàn tất giữ đến clear-done, execute/recover mới hoặc reset.
    reg done_q;
    // Thiết bị không ACK byte đã phát; xóa khi execute mới hoặc reset.
    reg ack_error_q;
    // Watchdog chỉ đếm khi chờ chân bus, không đếm pha thấp do master chủ động.
    reg [TIMEOUT_WIDTH-1:0] wait_count_q;
    reg timeout_q, recovery_error_q;
    // Kết thúc đúng một ghi MMIO đang chờ bằng lỗi sau khi watchdog hủy lệnh.
    reg timeout_response_q;
    // Quyền điều khiển bus thuộc cùng FSM; không có hai bộ phát tranh chân.
    reg recovering_q;
    // Số xung phục hồi đã hoàn tất trước xung hiện tại (0..8).
    reg [3:0] recovery_pulses_q;

    // Decode MMIO: offset, byte enable và loại lệnh.
    // Kiểm tra đúng một trong bốn offset DATA/CMD/STATUS/DIVIDER.
    wire valid_addr = (addr_i == 12'h000) || (addr_i == 12'h004) ||
                      (addr_i == 12'h008) || (addr_i == 12'h00C);
    // Yêu cầu ghi byte thấp CMD; chỉ xử lý khi bus ready.
    wire cmd_write = req_i && we_i && (addr_i == 12'h004) && wstrb_i[0];
    // Yêu cầu ghi byte thấp DATA; chỉ cập nhật tx_data_q khi ready và không lỗi.
    wire data_write = req_i && we_i && (addr_i == 12'h000) && wstrb_i[0];
    // RECOVER độc lập EXECUTE và ưu tiên hơn EXECUTE nếu cả hai cùng bật.
    wire recover_write = cmd_write && wdata_i[5];
    // Điều kiện tiến FSM và watchdog, độc lập với decode MMIO.
    // Bộ chia hết thời gian nửa chu kỳ; FSM được tiến nếu không chờ bus.
    wire tick = (divider_q == 0);
    // Count a full high phase AFTER the target releases SCL. Sampling once per
    // divider tick could otherwise shorten a stretched high phase to one clock.
    // Đang muốn SCL cao nhưng chân thực tế còn thấp (clock stretching).
    wire wait_scl = ((state_q == ST_START_A) || (state_q == ST_BIT_HIGH) ||
                     (state_q == ST_ACK_HIGH) || (state_q == ST_STOP_B) ||
                     (state_q == ST_REC_HIGH) || (state_q == ST_STOP_C)) && !scl_i;
    // Chờ SDA trước START hoặc sau STOP phục hồi, kể cả độ trễ synchronizer.
    wire wait_bus = ((state_q == ST_START_A) ||
                     (recovering_q && state_q == ST_STOP_C)) && !sda_i;
    wire wait_expired = (TIMEOUT_CYCLES > 0) && busy_q && (wait_scl || wait_bus) &&
                        (wait_count_q == TIMEOUT_CYCLES - 1);

    assign busy_o = busy_q;

    // Handshake: RECOVER có thể hủy busy; timeout kết thúc ghi đang chờ bằng lỗi.
    assign err_o = req_i && !rst_i && (!valid_addr ||
                   (we_i && (addr_i != 12'h000) && (addr_i != 12'h004)) ||
                   (timeout_response_q && (cmd_write || data_write)));
    assign ready_o = req_i && !rst_i &&
                     (err_o || recover_write || !((cmd_write || data_write) && busy_q));

    // Readback không gây side effect.
    always @* begin
        case (addr_i)
            12'h000: rdata_o = {24'd0, rx_data_q};
            12'h008: rdata_o = {27'd0, recovery_error_q, timeout_q, ack_error_q, done_q, busy_q};
            12'h00C: rdata_o = HALF_DIV;
            default: rdata_o = 32'd0;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q          <= ST_IDLE;
            divider_q        <= {DIV_WIDTH{1'b0}};
            tx_data_q        <= 8'd0;
            rx_data_q        <= 8'd0;
            bit_index_q      <= 3'd7;
            command_read_q   <= 1'b0;
            command_stop_q   <= 1'b0;
            command_nack_q   <= 1'b1;
            busy_q           <= 1'b0;
            done_q           <= 1'b0;
            ack_error_q      <= 1'b0;
            wait_count_q     <= 0;
            timeout_q        <= 1'b0;
            recovery_error_q <= 1'b0;
            timeout_response_q <= 1'b0;
            recovering_q     <= 1'b0;
            recovery_pulses_q <= 0;
            scl_drive_low_o  <= 1'b0;
            sda_drive_low_o  <= 1'b0;
        end
        else begin
            timeout_response_q <= 1'b0;
            if (!busy_q || !(wait_scl || wait_bus) || wait_expired)
                wait_count_q <= 0;
            else if (TIMEOUT_CYCLES > 0)
                wait_count_q <= wait_count_q + 1'b1;

            // Side effect DATA/CMD chỉ sau handshake thành công.
            if (data_write && ready_o && !err_o)
                tx_data_q <= wdata_i[7:0];

            if (cmd_write && ready_o && !err_o) begin
                if (wdata_i[4])
                    done_q <= 1'b0;
                if (wdata_i[6]) begin
                    ack_error_q <= 1'b0;
                    timeout_q <= 1'b0;
                    recovery_error_q <= 1'b0;
                end
                if (wdata_i[5]) begin
                    // Hủy lệnh cũ, nhả SDA, phát tối đa 9 xung rồi tạo STOP.
                    // Luôn chờ SCL thực sự cao; SCL kẹt sẽ hết hạn watchdog.
                    busy_q <= 1'b1;
                    done_q <= 1'b0;
                    recovering_q <= 1'b1;
                    recovery_pulses_q <= 0;
                    wait_count_q <= 0;
                    divider_q <= HALF_RELOAD[DIV_WIDTH-1:0];
                    scl_drive_low_o <= 1'b1;
                    sda_drive_low_o <= 1'b0;
                    state_q <= ST_REC_LOW;
                end
                else if (wdata_i[7]) begin
                    recovering_q   <= 1'b0;
                    wait_count_q   <= 0;
                    command_read_q <= wdata_i[2];
                    command_stop_q <= wdata_i[1];
                    command_nack_q <= wdata_i[3];
                    bit_index_q    <= 3'd7;
                    rx_data_q      <= 8'd0;
                    busy_q         <= 1'b1;
                    done_q         <= 1'b0;
                    ack_error_q    <= 1'b0;
                    divider_q      <= HALF_RELOAD[DIV_WIDTH-1:0];
                    if (wdata_i[0]) begin
                        // Repeated START: release SDA while SCL is still low,
                        // then raise SCL. Never generate a spurious STOP.
                        sda_drive_low_o <= 1'b0;
                        state_q <= scl_drive_low_o ? ST_START_PRE : ST_START_A;
                    end
                    else begin
                        scl_drive_low_o <= 1'b1;
                        sda_drive_low_o <= wdata_i[2] ? 1'b0 : !tx_data_q[7];
                        state_q         <= ST_BIT_LOW;
                    end
                end
            end
            else if (wait_expired) begin
                // Nhả cả hai chân và kết thúc lệnh; không phát tiếp sau timeout.
                state_q <= ST_IDLE;
                busy_q <= 1'b0;
                done_q <= 1'b1;
                timeout_q <= 1'b1;
                ack_error_q <= 1'b1; // firmware cũ chỉ đọc bit lỗi này vẫn thấy thất bại
                if (recovering_q) recovery_error_q <= 1'b1;
                recovering_q <= 1'b0;
                timeout_response_q <= cmd_write || data_write;
                scl_drive_low_o <= 1'b0;
                sda_drive_low_o <= 1'b0;
            end
            else if (busy_q) begin
                if (wait_scl || wait_bus) begin
                    divider_q <= HALF_DIV[DIV_WIDTH-1:0];
                end
                else if (!tick) begin
                    divider_q <= divider_q - 1'b1;
                end
                else begin
                    divider_q <= HALF_RELOAD[DIV_WIDTH-1:0];
                    case (state_q)
                        ST_REC_LOW: begin
                            scl_drive_low_o <= 1'b0;
                            state_q <= ST_REC_HIGH;
                        end
                        ST_REC_HIGH: begin
                            if (sda_i) begin
                                scl_drive_low_o <= 1'b1;
                                sda_drive_low_o <= 1'b1;
                                state_q <= ST_STOP_A;
                            end
                            else if (recovery_pulses_q == 8) begin
                                recovery_error_q <= 1'b1;
                                ack_error_q <= 1'b1;
                                busy_q <= 1'b0;
                                done_q <= 1'b1;
                                recovering_q <= 1'b0;
                                state_q <= ST_IDLE;
                                scl_drive_low_o <= 1'b0;
                                sda_drive_low_o <= 1'b0;
                            end
                            else begin
                                recovery_pulses_q <= recovery_pulses_q + 1'b1;
                                scl_drive_low_o <= 1'b1;
                                state_q <= ST_REC_LOW;
                            end
                        end
                        ST_START_PRE: begin
                            scl_drive_low_o <= 1'b0;
                            state_q <= ST_START_A;
                        end
                        ST_START_A: begin
                            // Bus rảnh: cả hai đường đã được nhả cao.
                            sda_drive_low_o <= 1'b1;
                            state_q <= ST_START_B;
                        end
                        ST_START_B: begin
                            scl_drive_low_o <= 1'b1;
                            sda_drive_low_o <= command_read_q ? 1'b0 : !tx_data_q[7];
                            state_q <= ST_BIT_LOW;
                        end
                        ST_BIT_LOW: begin
                            scl_drive_low_o <= 1'b0;
                            state_q <= ST_BIT_HIGH;
                        end
                        ST_BIT_HIGH: begin
                            if (scl_i) begin
                                if (command_read_q)
                                    rx_data_q[bit_index_q] <= sda_i;
                                scl_drive_low_o <= 1'b1;
                                if (bit_index_q == 0) begin
                                    sda_drive_low_o <= command_read_q ? !command_nack_q : 1'b0;
                                    state_q <= ST_ACK_LOW;
                                end
                                else begin
                                    bit_index_q <= bit_index_q - 1'b1;
                                    sda_drive_low_o <= command_read_q ? 1'b0 : !tx_data_q[bit_index_q - 1'b1];
                                    state_q <= ST_BIT_LOW;
                                end
                            end
                        end
                        ST_ACK_LOW: begin
                            scl_drive_low_o <= 1'b0;
                            state_q <= ST_ACK_HIGH;
                        end
                        ST_ACK_HIGH: begin
                            // Finish the ninth pulse before accepting the next
                            // byte. A command without STOP retains SCL low.
                            scl_drive_low_o <= 1'b1;
                            if (!command_read_q)
                                ack_error_q <= sda_i;
                            if (command_stop_q) begin
                                scl_drive_low_o <= 1'b1;
                                sda_drive_low_o <= 1'b1;
                                state_q <= ST_STOP_A;
                            end
                            else begin
                                sda_drive_low_o <= 1'b0;
                                state_q <= ST_COMPLETE;
                            end
                        end
                        ST_STOP_A: begin
                            scl_drive_low_o <= 1'b0;
                            state_q <= ST_STOP_B;
                        end
                        ST_STOP_B: begin
                            sda_drive_low_o <= 1'b0;
                            state_q <= ST_STOP_C;
                        end
                        ST_STOP_C: begin
                            state_q <= ST_COMPLETE;
                        end
                        ST_COMPLETE: begin
                            busy_q <= 1'b0;
                            done_q <= 1'b1;
                            state_q <= ST_IDLE;
                            recovering_q <= 1'b0;
                            // STOP already released SCL; otherwise keep it low
                            // across software latency between byte commands.
                            sda_drive_low_o <= 1'b0;
                        end
                        default: begin
                            busy_q <= 1'b0;
                            state_q <= ST_IDLE;
                            scl_drive_low_o <= 1'b0;
                            sda_drive_low_o <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule

`default_nettype wire
