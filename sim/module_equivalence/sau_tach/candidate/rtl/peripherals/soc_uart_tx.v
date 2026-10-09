`default_nettype none

// =============================================================================
// Module      : soc_uart_tx
// Chức năng   : UART truyền 8N1, có FIFO để hấp thụ các đợt ghi log ngắn.
//
// Thanh ghi:
//   0x0 DATA   : ghi byte để truyền; bus chờ khi FIFO không còn chỗ.
//   0x4 STATUS : bit 0 còn chỗ nhận byte, bit 1 còn dữ liệu chưa phát xong.
//
// FIFO_DEPTH=0 giữ chế độ cũ: ghi DATA phải chờ hết frame đang phát.
// busy bao gồm cả FIFO và frame: phần mềm chờ busy=0 để flush toàn bộ log.
// =============================================================================
module soc_uart_tx #(
    // Tần số clk_i tính bằng Hz, dùng tính bộ chia UART/I2C.
    parameter integer CLOCK_HZ = 50000000,
    // Tốc độ UART, bit/giây; bộ chia làm tròn theo CLOCK_HZ.
    parameter integer BAUD     = 115200,
    // Số byte chờ ngoài thanh ghi phát; hỗ trợ cả độ sâu không phải lũy thừa 2.
    parameter integer FIFO_DEPTH = 4
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire        req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire        we_i,
    // Offset byte MMIO: 0x0 DATA để ghi byte phát, 0x4 STATUS chỉ đọc.
    input  wire [3:0]  addr_i,
    // Dữ liệu ghi 32 bit; chỉ các byte được wstrb chọn mới được cập nhật.
    input  wire [31:0] wdata_i,
    // Bit n chọn byte [8*n +: 8]; không chọn byte nào vẫn phải kiểm tra quyền/địa chỉ.
    input  wire [3:0]  wstrb_i,
    // Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
    output reg  [31:0] rdata_o,
    // Ghi DATA byte thấp chờ khi hết chỗ; truy cập lỗi luôn hoàn tất để báo err.
    output wire        ready_o,
    // Lỗi địa chỉ/quyền truy cập; master chỉ xét khi req && ready.
    output wire        err_o,
    // Tín hiệu UART nối tiếp 8N1; mức 1 khi rảnh, phát bit thấp trước.
    output wire        tx_o,
    // 1 khi FIFO còn byte hoặc frame hiện tại chưa phát hết stop bit.
    output wire        busy_o
);

    // Số clock mỗi bit UART, làm tròn gần nhất từ CLOCK_HZ/BAUD.
    localparam integer BAUD_DIV = (BAUD > 0) ? (CLOCK_HZ + (BAUD/2)) / BAUD : 1;
    // Độ rộng đủ chứa bộ đếm lùi, tối thiểu 1 bit.
    localparam integer DIV_WIDTH = (BAUD_DIV > 1) ? $clog2(BAUD_DIV) : 1;
    // Đếm từ BAUD_DIV-1 về 0 cho đủ BAUD_DIV chu kỳ mỗi bit.
    localparam integer BAUD_RELOAD = BAUD_DIV - 1;
    localparam integer FIFO_SLOTS = (FIFO_DEPTH > 0) ? FIFO_DEPTH : 1;
    localparam integer PTR_WIDTH = (FIFO_SLOTS > 1) ? $clog2(FIFO_SLOTS) : 1;
    localparam integer COUNT_WIDTH = $clog2(FIFO_SLOTS + 1);

    // synthesis translate_off
    initial begin
        if (CLOCK_HZ <= 0 || BAUD <= 0 || BAUD_DIV < 1 || FIFO_DEPTH < 0)
            $fatal(1, "soc_uart_tx: invalid CLOCK_HZ/BAUD");
    end
    // synthesis translate_on

    // Khung 10 bit {stop, data[7:0], start}; bit 0 được phát trước.
    reg [9:0] tx_shift_q;
    // Số bit còn phải phát, từ 10 về 0; gồm cả start và stop.
    reg [3:0] bit_count_q;
    // Bộ đếm lùi số chu kỳ clock còn lại của bit UART hiện tại.
    reg [DIV_WIDTH-1:0] baud_count_q;
    // Trạng thái serializer; chỉ nạp frame kế tiếp sau khi phát đủ stop bit.
    reg busy_q;
    // FIFO dùng một clock; không reset bộ nhớ, chỉ xóa con trỏ và số byte hợp lệ.
    reg [7:0] fifo_q [0:FIFO_SLOTS-1];
    reg [PTR_WIDTH-1:0] read_ptr_q, write_ptr_q;
    reg [COUNT_WIDTH-1:0] count_q;

    // Chỉ DATA=0x0 và STATUS=0x4 là địa chỉ thanh ghi hợp lệ.
    wire valid_addr = (addr_i == 4'h0) || (addr_i == 4'h4);
    // Yêu cầu ghi DATA có chọn byte thấp; chỉ phát khi đồng thời ready.
    wire data_write = req_i && we_i && (addr_i == 4'h0) && wstrb_i[0];

    // Pop và push được phép cùng cạnh, kể cả khi FIFO đang đầy.
    wire fifo_pop = !busy_q && (count_q != 0);
    wire can_accept = (FIFO_DEPTH == 0) ? !busy_q :
                      ((count_q < FIFO_DEPTH) || fifo_pop);
    wire data_accept = data_write && ready_o && !err_o;
    // Bypass khi rảnh và FIFO rỗng để byte đầu không mất thêm một clock.
    wire direct_send = !busy_q && (count_q == 0) && data_accept;
    wire fifo_push = data_accept && !direct_send;
    wire launch = fifo_pop || direct_send;

    assign busy_o  = busy_q || (count_q != 0);
    assign tx_o    = busy_q ? tx_shift_q[0] : 1'b1;
    assign err_o   = req_i && !rst_i && (!valid_addr || (we_i && (addr_i != 4'h0)));
    assign ready_o = req_i && !rst_i && (err_o || !data_write || can_accept);

    always @* begin
        case (addr_i)
            4'h4: rdata_o = {30'd0, busy_o, can_accept};
            default: rdata_o = 32'd0;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_shift_q   <= 10'h3FF;
            bit_count_q  <= 4'd0;
            baud_count_q <= {DIV_WIDTH{1'b0}};
            busy_q       <= 1'b0;
            read_ptr_q   <= 0;
            write_ptr_q  <= 0;
            count_q      <= 0;
        end
        else begin
            if (fifo_push) begin
                fifo_q[write_ptr_q] <= wdata_i[7:0];
                write_ptr_q <= (write_ptr_q == FIFO_SLOTS-1) ? {PTR_WIDTH{1'b0}} : write_ptr_q + 1'b1;
            end
            if (fifo_pop)
                read_ptr_q <= (read_ptr_q == FIFO_SLOTS-1) ? {PTR_WIDTH{1'b0}} : read_ptr_q + 1'b1;
            case ({fifo_push, fifo_pop})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: begin end
            endcase
            if (launch) begin
                // LSB phát trước: start(0), 8 data bit, stop(1).
                tx_shift_q   <= {1'b1, (fifo_pop ? fifo_q[read_ptr_q] : wdata_i[7:0]), 1'b0};
                bit_count_q  <= 4'd10;
                baud_count_q <= BAUD_RELOAD[DIV_WIDTH-1:0];
                busy_q       <= 1'b1;
            end
            else if (busy_q) begin
                if (baud_count_q == 0) begin
                    tx_shift_q   <= {1'b1, tx_shift_q[9:1]};
                    baud_count_q <= BAUD_RELOAD[DIV_WIDTH-1:0];
                    if (bit_count_q == 1) begin
                        bit_count_q <= 4'd0;
                        busy_q      <= 1'b0;
                    end
                    else begin
                        bit_count_q <= bit_count_q - 4'd1;
                    end
                end
                else begin
                    baud_count_q <= baud_count_q - 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
