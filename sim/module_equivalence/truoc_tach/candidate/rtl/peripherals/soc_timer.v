`default_nettype none

// =============================================================================
// Module      : soc_timer
// Chức năng   : Bộ đếm thời gian tự do 64 bit và mốc compare 64 bit.
// Thanh ghi   : 0x0 TIME_LO, 0x4 TIME_HI, 0x8 CMP_LO, 0xC CMP_HI.
// Đọc TIME_LO chốt TIME_HI cho lần đọc sau, tránh rách dữ liệu lúc rollover.
// irq_o giữ mức 1 khi time >= compare; compare=all-ones vô hiệu hóa IRQ.
// Purpose: timestamp/snapshot/compare, giữ datapath timer hiện tại.
// Clock: clk_i cạnh lên. Reset: rst_i synchronous active-high, chặn handshake.
// Inputs: native bus, offset 12 bit. Outputs: rdata/ready/err và irq_o mức.
// Protocol: side effect tại req && ready && !err; snapshot khi đọc TIME_LO.
// Latency: zero wait tại slave. Error behavior: offset sai/ghi TIME trả ready+err.
// =============================================================================
module soc_timer (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire        req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire        we_i,
    // Offset byte MMIO: 0x0/4 TIME_LO/HI chỉ đọc, 0x8/C CMP_LO/HI đọc/ghi.
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
    // 1 khi time>=compare ngoài reset; compare toàn bit 1 tắt IRQ; SoC chưa nối IRQ vào CPU.
    output wire        irq_o
);

    // Bộ đếm 64 bit tăng mỗi clock; reset về 0, đơn vị là chu kỳ clk_i.
    reg [63:0] time_q;
    // Mốc so sánh 64 bit cho IRQ; toàn bit 1 là giá trị vô hiệu hóa.
    reg [63:0] compare_q;
    // 32 bit cao của time được chụp khi đọc TIME_LO, tránh dữ liệu rách.
    reg [31:0] snapshot_hi_q;
    // Đã có snapshot từ lần đọc TIME_LO; TIME_HI dùng nó đến lần chụp mới/reset.
    reg snapshot_valid_q;
    assign ready_o = req_i && !rst_i;
    assign irq_o   = !rst_i && (compare_q != 64'hFFFF_FFFF_FFFF_FFFF) &&
                     (time_q >= compare_q);

    always @* begin
        err_o = 1'b0;
        case (addr_i)
            12'h000: rdata_o = time_q[31:0];
            12'h004: rdata_o = snapshot_valid_q ? snapshot_hi_q : time_q[63:32];
            12'h008: rdata_o = compare_q[31:0];
            12'h00C: rdata_o = compare_q[63:32];
            default: begin
                rdata_o = 32'd0;
                err_o = ready_o;
            end
        endcase
        if (ready_o && we_i && (addr_i != 12'h008) && (addr_i != 12'h00C))
            err_o = 1'b1;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            time_q    <= 64'd0;
            compare_q <= 64'hFFFF_FFFF_FFFF_FFFF;
            snapshot_hi_q <= 32'd0;
            snapshot_valid_q <= 1'b0;
        end
        else begin
            time_q <= time_q + 64'd1;
            if (ready_o && !we_i && !err_o && (addr_i == 12'h000)) begin
                snapshot_hi_q <= time_q[63:32];
                snapshot_valid_q <= 1'b1;
            end
            if (ready_o && we_i && !err_o) begin
                if (addr_i == 12'h008) begin
                    if (wstrb_i[0])
                        compare_q[7:0] <= wdata_i[7:0];
                    if (wstrb_i[1])
                        compare_q[15:8] <= wdata_i[15:8];
                    if (wstrb_i[2])
                        compare_q[23:16] <= wdata_i[23:16];
                    if (wstrb_i[3])
                        compare_q[31:24] <= wdata_i[31:24];
                end
                if (addr_i == 12'h00C) begin
                    if (wstrb_i[0])
                        compare_q[39:32] <= wdata_i[7:0];
                    if (wstrb_i[1])
                        compare_q[47:40] <= wdata_i[15:8];
                    if (wstrb_i[2])
                        compare_q[55:48] <= wdata_i[23:16];
                    if (wstrb_i[3])
                        compare_q[63:56] <= wdata_i[31:24];
                end
            end
        end
    end

endmodule

`default_nettype wire
