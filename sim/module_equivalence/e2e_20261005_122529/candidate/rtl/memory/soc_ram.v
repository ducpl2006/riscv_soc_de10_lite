`default_nettype none

// =============================================================================
// Module      : soc_ram
// Chức năng   : SRAM on-chip 8 KiB mặc định, một cổng, byte write-enable.
//
// Giao thức:
//   - Master giữ req/address/write-data cho tới khi ready_o=1.
//   - Chụp request ở cạnh N, đăng ký ready/data sau N+1; master lấy ở N+2.
//   - Ghi storage xảy ra ở N; reset trước ready không hoàn tác dữ liệu đã ghi.
//   - Địa chỉ ngoài vùng hoặc lệch word trả ready+err, không làm bus treo.
//
// Backend lưu trữ nằm trong intel_sync_ram_1p. Tách handshake khỏi primitive làm
// RTL dễ kiểm tra và tránh Quartus trải RAM thành FF/mux do process quá phức tạp.
// =============================================================================
module soc_ram #(
    // Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
    parameter integer WORDS = 2048
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire        req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire        we_i,
    // Offset byte tính từ RAM_BASE, phải căn 4 và nhỏ hơn WORDS*4.
    input  wire [31:0] addr_i,
    // Dữ liệu ghi 32 bit; chỉ các byte được wstrb chọn mới được cập nhật.
    input  wire [31:0] wdata_i,
    // Bit n chọn byte [8*n +: 8]; không chọn byte nào vẫn phải kiểm tra quyền/địa chỉ.
    input  wire [3:0]  wstrb_i,
    // Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
    output reg  [31:0] rdata_o,
    // Hoàn tất giao dịch tại cạnh req && ready; có thể kèm err.
    output reg         ready_o,
    // Lỗi địa chỉ/quyền truy cập; master chỉ xét khi req && ready.
    output reg         err_o
);

    // Giới hạn offset byte hợp lệ; không phải số word của storage.
    localparam [31:0] RAM_BYTES = WORDS * 4;

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

    // Số bit chỉ số word; tối thiểu 1 để tránh vector có độ rộng bằng 0.
    localparam integer ADDR_WIDTH = (WORDS > 1) ? clog2(WORDS) : 1;
    // Đã chụp request, đang chờ dữ liệu storage để đăng ký response.
    reg pending_q;
    // Lỗi range/alignment của request đã chụp, giữ tới response.
    reg pending_err_q;

    // Địa chỉ nằm trong dung lượng SRAM và chia hết cho 4.
    wire valid_addr = (addr_i < RAM_BYTES) && (addr_i[1:0] == 2'b00);
    // Chụp request khi rảnh; khác với handshake hoàn tất req && ready.
    wire accept = req_i && !rst_i && !ready_o && !pending_q;
    // Cho storage hoạt động khi chụp request có địa chỉ hợp lệ.
    wire ram_enable = accept && valid_addr;
    // Word storage đọc ở cạnh chụp; khi ghi, trả word cũ trước cập nhật.
    wire [31:0] ram_q;

    intel_sync_ram_1p #(
        .WIDTH(32), .WORDS(WORDS), .ADDR_WIDTH(ADDR_WIDTH), .BYTE_COUNT(4)
    ) u_storage (
        .clk_i(clk_i),
        .en_i(ram_enable),
        .we_i(we_i),
        .byteena_i(wstrb_i),
        .addr_i(addr_i[ADDR_WIDTH+1:2]),
        .data_i(wdata_i),
        .q_o(ram_q)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            rdata_o      <= 32'd0;
            ready_o      <= 1'b0;
            err_o        <= 1'b0;
            pending_q    <= 1'b0;
            pending_err_q <= 1'b0;
        end
        else begin
            if (ready_o) begin
                ready_o <= 1'b0;
                err_o   <= 1'b0;
            end
            else if (pending_q) begin
                ready_o   <= 1'b1;
                err_o     <= pending_err_q;
                rdata_o   <= pending_err_q ? 32'd0 : ram_q;
                pending_q <= 1'b0;
            end
            else if (req_i) begin
                pending_q     <= 1'b1;
                pending_err_q <= !valid_addr;
            end
        end
    end

endmodule

`default_nettype wire
