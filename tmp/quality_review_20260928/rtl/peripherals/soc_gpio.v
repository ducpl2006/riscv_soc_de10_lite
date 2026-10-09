`default_nettype none

// =============================================================================
// Module      : soc_gpio
// Purpose     : GPIO MMIO mặc định 8 LED phần mềm và 10 switch DE10-Lite.
// Clock: clk_i cạnh lên. Reset: rst_i synchronous active-high, chặn handshake.
// Inputs: native bus offset 12 bit, switches_i đã đồng bộ.
// Outputs: rdata/ready/err và leds_o theo GPIO_LED_WIDTH.
// Protocol: ghi đúng lane tại req && ready && !err; byte ngoài độ rộng là no-op.
// Latency: zero wait tại slave. Error behavior: offset sai/ghi SWITCH trả ready+err.
// Thanh ghi   : 0x0 LED_RW, 0x4 SWITCH_RO.
// =============================================================================
module soc_gpio #(
    // Số bit LED phần mềm; DE10-Lite dành hai LED còn lại cho QNN/trap.
    parameter integer GPIO_LED_WIDTH=8
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire        req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire        we_i,
    // Offset byte MMIO: 0x0 LED đọc/ghi, 0x4 SWITCH chỉ đọc.
    input  wire [11:0]  addr_i,
    // Dữ liệu ghi 32 bit; chỉ các byte được wstrb chọn mới được cập nhật.
    input  wire [31:0] wdata_i,
    // Bit n chọn byte [8*n +: 8]; không chọn byte nào vẫn phải kiểm tra quyền/địa chỉ.
    input  wire [3:0]  wstrb_i,
    // Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
    output reg  [31:0] rdata_o,
    // Hoàn tất giao dịch tại cạnh req && ready; có thể kèm err.
    output wire        ready_o,
    // Lỗi địa chỉ/quyền truy cập; master chỉ xét khi req && ready.
    output reg         err_o,
    // Mức của 10 switch đã đồng bộ với clk_i tại lớp board.
    input  wire [9:0]  switches_i,
    // Chỉ chứa các LED phần mềm thực sự sở hữu, không bao gồm QNN/trap.
    output wire [GPIO_LED_WIDTH-1:0] leds_o
);

    // Thanh ghi LED, cập nhật từng byte được chọn trong phạm vi độ rộng.
    reg [GPIO_LED_WIDTH-1:0] leds_q;
    integer bit_index;
    assign leds_o  = leds_q;
    assign ready_o = req_i && !rst_i;

    always @* begin
        rdata_o = 32'd0;
        err_o   = 1'b0;
        case (addr_i)
            12'h000: rdata_o = {{(32-GPIO_LED_WIDTH){1'b0}}, leds_q};
            12'h004: rdata_o = {22'd0, switches_i};
            default: err_o = ready_o;
        endcase
        if (ready_o && we_i && (addr_i != 12'h000))
            err_o = 1'b1;
    end

    always @(posedge clk_i) begin
        if (rst_i)
            leds_q <= {GPIO_LED_WIDTH{1'b0}};
        else if (ready_o && we_i && !err_o) begin
            for (bit_index=0;bit_index<GPIO_LED_WIDTH;bit_index=bit_index+1)
                if (wstrb_i[bit_index/8]) leds_q[bit_index] <= wdata_i[bit_index];
        end
    end
    // synthesis translate_off
    initial if (GPIO_LED_WIDTH<1 || GPIO_LED_WIDTH>32) $fatal(1,"Invalid GPIO_LED_WIDTH");
    // synthesis translate_on

endmodule

`default_nettype wire
