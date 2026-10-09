`default_nettype none

// =============================================================================
// Module      : rv32_regfile
// Chức năng   : Tập 32 thanh ghi nguyên RV32I, hai cổng đọc và một cổng ghi.
//
// Đặc tả giao tiếp
//   - rs1_addr_i/rs2_addr_i chọn hai nguồn đọc tổ hợp độc lập.
//   - rd_we_i, rd_addr_i, rd_data_i tạo cổng ghi đồng bộ ở cạnh lên clk_i.
//   - x0 luôn đọc bằng 0 và mọi yêu cầu ghi x0 đều bị bỏ qua.
//
// Nguyên tắc thời gian cho pipeline 5 tầng
//   - Dữ liệu rd được lưu vào x1..x31 tại cạnh lên khi rd_we_i = 1.
//   - Có bypass write-through WB -> ID: trong chu kỳ ghi, nếu địa chỉ đọc trùng
//     rd_addr_i hợp lệ thì cổng đọc trả ngay rd_data_i, kể cả trước cạnh ghi.
//   - Bypass loại bỏ phụ thuộc WB/ID cùng chu kỳ; các hazard gần hơn vẫn do khối
//     forwarding/stall của pipeline xử lý.
//
// Reset và trường hợp biên
//   - rst_i tích cực mức cao, đồng bộ và ưu tiên hơn thao tác ghi.
//   - Khi rst_i = 1, bypass bị khóa; x1..x31 chỉ được xóa tại cạnh lên kế tiếp.
//   - Thiết kế phải được reset trước khi đọc x1..x31 để tránh trạng thái X.
//   - Reset toàn bộ mảng giúp trạng thái xác định nhưng thường khiến FPGA dùng
//     31 x 32 flip-flop thay vì suy luận block RAM; đây là chủ đích kiến trúc.
// =============================================================================
module rv32_regfile (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire        clk_i,
    // Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
    input  wire        rst_i,

    // Chỉ số thanh ghi nguồn rs1 (0..31); không phải địa chỉ bộ nhớ.
    input  wire [4:0]  rs1_addr_i,
    // Chỉ số thanh ghi nguồn rs2 (0..31); không phải địa chỉ bộ nhớ.
    input  wire [4:0]  rs2_addr_i,
    // Dữ liệu đọc tổ hợp rs1: ưu tiên x0=0, rồi bypass WB, rồi mảng thanh ghi.
    output reg  [31:0] rs1_data_o,
    // Dữ liệu đọc tổ hợp rs2: ưu tiên x0=0, rồi bypass WB, rồi mảng thanh ghi.
    output reg  [31:0] rs2_data_o,

    // Yêu cầu ghi rd tại cạnh lên; module còn chặn reset và rd=x0.
    input  wire        rd_we_i,
    // Chỉ số thanh ghi đích rd (0..31); ghi x0 bị bỏ qua tại commit.
    input  wire [4:0]  rd_addr_i,
    // Dữ liệu ghi rd; đồng thời là nguồn bypass tới cổng đọc trùng địa chỉ.
    input  wire [31:0] rd_data_i
);

    // x0 là hằng 0 nên chỉ cần phần tử lưu trữ cho x1..x31.
    // 31 thanh ghi x1..x31; x0 là hằng 0 nên không có phần tử lưu trữ.
    reg [31:0] registers [1:31];

    // Ghi hợp lệ sau khi loại reset và x0; cũng bật bypass write-through.
    wire write_valid;
    // Chỉ số vòng lặp xóa x1..x31 khi reset.
    integer reset_index;

    assign write_valid = rd_we_i
                       && (rd_addr_i != 5'd0)
                       && !rst_i;

    // Ghi đồng bộ; reset đồng bộ có ưu tiên cao nhất.
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (reset_index = 1; reset_index < 32;
                 reset_index = reset_index + 1) begin
                registers[reset_index] <= 32'b0;
            end
        end
        else if (write_valid) begin
            registers[rd_addr_i] <= rd_data_i;
        end
    end

    // Cổng đọc 1: ưu tiên x0, sau đó bypass WB -> ID, cuối cùng là mảng lưu.
    always @(*) begin
        if (rs1_addr_i == 5'd0) begin
            rs1_data_o = 32'b0;
        end
        else if (write_valid && (rd_addr_i == rs1_addr_i)) begin
            rs1_data_o = rd_data_i;
        end
        else begin
            rs1_data_o = registers[rs1_addr_i];
        end
    end

    // Cổng đọc 2 có cùng chính sách ưu tiên với cổng đọc 1.
    always @(*) begin
        if (rs2_addr_i == 5'd0) begin
            rs2_data_o = 32'b0;
        end
        else if (write_valid && (rd_addr_i == rs2_addr_i)) begin
            rs2_data_o = rd_data_i;
        end
        else begin
            rs2_data_o = registers[rs2_addr_i];
        end
    end

endmodule

`default_nettype wire
