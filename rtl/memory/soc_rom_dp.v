`default_nettype none

// =============================================================================
// Module      : soc_rom_dp
// Chức năng   : ROM hai cổng đọc đồng bộ cho instruction và data.
//
// Giao thức:
//   - Cổng instruction tách request/response. req && gnt nhận một địa chỉ mới;
//     rvalid trả kết quả theo thứ tự sau một chu kỳ và có thể liên tiếp mỗi chu kỳ.
//   - Cổng data giữ req/địa chỉ tới cạnh req && ready; tối đa một giao dịch.
//     Chụp nội bộ ở N, master lấy đáp ứng ở N+2; chụp tiếp sớm nhất ở N+3.
//   - err đi cùng rvalid (instruction) hoặc ready (data).
//   - Reset tích cực cao, đồng bộ; hủy giao dịch nhưng không xóa nội dung ROM.
//   - WORDS phải dương, 4*WORDS biểu diễn được trong 32 bit.
// Đặc tả      : docs/giao_tiep_rtl_vi.md, mục 4.1.
//
// Tổng hợp:
//   - Mảng word và hai cổng đọc đồng bộ phù hợp suy luận ROM hai cổng MAX 10.
//   - File hex chứa một word 32 bit little-endian trên mỗi dòng.
// =============================================================================
module soc_rom_dp #(
    // Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
    parameter integer WORDS = 8192,
    // Khác 0: mô phỏng nạp HEX; backend Quartus dùng INIT_FILE trực tiếp.
    parameter integer USE_INIT_FILE = 0,
    // Đường dẫn file khởi tạo ROM; HEX cho mô phỏng, MIF/HEX phù hợp backend tổng hợp.
    parameter         INIT_FILE = ""
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,

    // Yêu cầu đọc instruction; nhận tại cạnh i_req && i_gnt.
    input  wire        i_req_i,
    // Offset byte instruction trong ROM, căn 4 và nhỏ hơn WORDS*4.
    input  wire [31:0] i_addr_i,
    // Cho phép nhận request mới mỗi chu kỳ ngoài reset; không phải response valid.
    output wire        i_gnt_o,
    // Word lệnh cho request trước đó; bằng 0 khi không valid hoặc có lỗi.
    output wire [31:0] i_rdata_o,
    // Đáp ứng instruction; core lấy mẫu sớm nhất một cạnh sau grant.
    output wire        i_rvalid_o,
    // Lỗi range/alignment instruction, chỉ có nghĩa khi i_rvalid=1.
    output wire        i_err_o,

    // Yêu cầu đọc cổng data; giữ cùng địa chỉ tới cạnh d_req && d_ready.
    input  wire        d_req_i,
    // Offset byte cổng data trong ROM, căn 4 và nhỏ hơn WORDS*4.
    input  wire [31:0] d_addr_i,
    // Word đọc cổng data; chỉ dùng tại d_req && d_ready && !d_err.
    output reg  [31:0] d_rdata_o,
    // Hoàn tất data ở N+2 nếu chụp nội bộ tại N; nhận tiếp sớm nhất N+3.
    output reg         d_ready_o,
    // Lỗi range/alignment cổng data; có nghĩa khi d_req && d_ready.
    output reg         d_err_o
);

    // Giới hạn offset byte; hai cổng dùng chung dung lượng ROM này.
    localparam [31:0] ROM_BYTES = WORDS * 4;
    function integer clog2;
        // Số phần tử cần tính ceil(log2) để chọn độ rộng địa chỉ storage.
        input integer value;
        // Biến tạm dịch phải value-1 trong hàm clog2.
        integer temporary;
        begin
            temporary = value - 1;
            for (clog2 = 0; temporary > 0; clog2 = clog2 + 1)
                temporary = temporary >> 1;
        end
    endfunction
    // Số bit chỉ số word trong ROM; tối thiểu 1 dù WORDS=1.
    localparam integer ADDR_WIDTH = (WORDS > 1) ? clog2(WORDS) : 1;
    // Dữ liệu storage cổng instruction, chốt tại cạnh nhận request.
    wire [31:0] i_rom_q;
    // Dữ liệu storage cổng data, chuyển sang response khi pending.
    wire [31:0] d_rom_q;
    // Đã chụp request data, đang đợi để đăng ký response.
    reg d_pending_q;
    // Metadata cho instruction đã grant; đồng hành với dữ liệu ROM.
    reg i_valid_q;
    // Lỗi địa chỉ của instruction đã grant, đồng hành với i_valid_q.
    reg i_err_q;
    // Lỗi địa chỉ data đã chụp, giữ đến lúc phát d_ready.
    reg d_pending_err_q;

    // Địa chỉ instruction trong ROM và chia hết cho 4.
    wire i_valid_addr = (i_addr_i < ROM_BYTES) && (i_addr_i[1:0] == 2'b00);
    // Địa chỉ data trong ROM và chia hết cho 4.
    wire d_valid_addr = (d_addr_i < ROM_BYTES) && (d_addr_i[1:0] == 2'b00);

    intel_sync_rom_2p #(
        .WIDTH(32), .WORDS(WORDS), .ADDR_WIDTH(ADDR_WIDTH),
        .USE_INIT_FILE(USE_INIT_FILE), .INIT_FILE(INIT_FILE)
    ) u_storage (
        .clk_i(clk_i),
        .a_en_i(i_req_i && i_gnt_o && i_valid_addr),
        .a_addr_i(i_addr_i[ADDR_WIDTH+1:2]), .a_q_o(i_rom_q),
        .b_en_i(d_req_i && !rst_i && !d_ready_o && !d_pending_q && d_valid_addr),
        .b_addr_i(d_addr_i[ADDR_WIDTH+1:2]), .b_q_o(d_rom_q)
    );

    assign i_gnt_o = !rst_i;
    // Storage đã chốt dữ liệu tại cạnh nhận yêu cầu. Metadata chốt cùng cạnh;
    // bên nhận lấy đáp ứng ở cạnh kế tiếp, không thêm một tầng chốt dữ liệu.
    assign i_rvalid_o = !rst_i && i_valid_q;
    assign i_err_o = i_rvalid_o && i_err_q;
    assign i_rdata_o = (i_rvalid_o && !i_err_q) ? i_rom_q : 32'b0;

    always @(posedge clk_i) begin
        if (rst_i) begin
            i_valid_q <= 1'b0;
            i_err_q <= 1'b0;
            d_rdata_o <= 32'd0;
            d_ready_o <= 1'b0;
            d_err_o   <= 1'b0;
            d_pending_q <= 1'b0;
            d_pending_err_q <= 1'b0;
        end
        else begin
            i_valid_q <= i_req_i && i_gnt_o;
            i_err_q <= i_req_i && i_gnt_o && !i_valid_addr;

            if (d_ready_o) begin
                d_ready_o <= 1'b0;
                d_err_o   <= 1'b0;
            end
            else if (d_pending_q) begin
                d_ready_o <= 1'b1;
                d_err_o   <= d_pending_err_q;
                d_pending_q <= 1'b0;
                if (!d_pending_err_q)
                    d_rdata_o <= d_rom_q;
                else
                    d_rdata_o <= 32'd0;
            end
            else if (d_req_i) begin
                d_pending_q <= 1'b1;
                d_pending_err_q <= !d_valid_addr;
            end
        end
    end

endmodule

`default_nettype wire
