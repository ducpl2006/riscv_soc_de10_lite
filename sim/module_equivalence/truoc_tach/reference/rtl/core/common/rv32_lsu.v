`default_nettype none

/*
 * Load/Store Unit (LSU) tổ hợp cho RV32I, bus dữ liệu rộng 32 bit
 *
 * Đặc tả giao tiếp:
 * - addr_i là địa chỉ byte hiệu dụng do ALU tính (rs1 + immediate).
 * - funct3_i dùng mã ISA chuẩn. Load: 000 LB, 001 LH, 010 LW,
 *   100 LBU, 101 LHU. Store: 000 SB, 001 SH, 010 SW.
 * - load_en_i và store_en_i phải loại trừ nhau đối với một lệnh hợp lệ.
 * - load_data_i là word 32 bit đọc tại địa chỉ đã căn word; byte ở địa
 *   chỉ thấp nhất nằm trong load_data_i[7:0] (little-endian).
 * - store_data_i chứa dữ liệu rs2; LSU chỉ dùng 8/16/32 bit thấp tùy cỡ.
 * - mem_addr_o luôn là địa chỉ word đã căn: {addr_i[31:2], 2'b00}.
 * - mem_wdata_o đặt dữ liệu store đúng byte lane; mem_wstrb_o[n] cho phép
 *   ghi byte mem_wdata_o[8*n +: 8].
 * - load_data_o là dữ liệu đã chọn lane và mở rộng dấu/zero lên 32 bit.
 *
 * Thời gian:
 * - Khối hoàn toàn tổ hợp, không phát request/ready và không giữ trạng thái.
 * - Trong pipeline 5 tầng, tín hiệu điều khiển/địa chỉ/store-data đi qua
 *   EX/MEM; dữ liệu đọc ở MEM được khối này căn lane trước khi về MEM/WB.
 * - Khối điều khiển bus bên ngoài chỉ được ghi khi mem_wstrb_o khác 0.
 *
 * Quy tắc an toàn và góc biên:
 * - Byte không có yêu cầu căn hàng. Halfword cần addr_i[0] = 0; word cần
 *   addr_i[1:0] = 00. Truy cập lệch hàng đặt misaligned_o = 1.
 * - Store lệch hàng bị chặn bằng mem_wstrb_o = 0000; load lệch hàng trả 0.
 * - funct3 dành riêng không tạo strobe, không báo lệch hàng và trả load = 0.
 * - LSU không tách một truy cập lệch hàng thành hai giao dịch bus.
 */
module eq_reference_rv32_lsu (
    // Địa chỉ byte hiệu dụng rs1+immediate, chưa căn word; dùng bit thấp chọn lane.
    input  wire [31:0] addr_i,
    // 000=byte, 001=halfword, 010=word; load 100/101 mở rộng zero.
    input  wire [2:0]  funct3_i,
    // Cho phép xử lý load; phải loại trừ với store_en cho một lệnh hợp lệ.
    input  wire        load_en_i,
    // Cho phép tạo dữ liệu/strobe store; không phát strobe nếu lệch hàng.
    input  wire        store_en_i,
    // Giá trị rs2; lấy 8/16/32 bit thấp theo cỡ store.
    input  wire [31:0] store_data_i,
    // Word 32 bit tại địa chỉ căn word; byte địa chỉ thấp nằm ở bit [7:0].
    input  wire [31:0] load_data_i,

    // Địa chỉ byte căn word: xóa addr_i[1:0]; không phải chỉ số word.
    output wire [31:0] mem_addr_o,
    // Dữ liệu store đã dịch tới đúng byte lane little-endian.
    output reg  [31:0] mem_wdata_o,
    // Bit n chọn byte n; bằng 0 nếu không store hoặc store lệch hàng.
    output reg  [3:0]  mem_wstrb_o,
    // Kết quả load đã chọn lane và mở rộng dấu/zero lên 32 bit.
    output reg  [31:0] load_data_o,
    // Truy cập halfword/word lệch hàng; byte không cần căn hàng.
    output reg         misaligned_o
);

    localparam [2:0]
        F3_BYTE   = 3'b000,
        F3_HALF   = 3'b001,
        F3_WORD   = 3'b010,
        F3_BYTE_U = 3'b100,
        F3_HALF_U = 3'b101;

    // Số bit dịch chọn byte lane, bằng addr_i[1:0]*8 (0/8/16/24).
    wire [4:0] lane_shift;
    // Word đọc đã dịch phải để byte cần đọc nằm ở bit [7:0].
    reg  [31:0] load_shifted;

    assign mem_addr_o = {addr_i[31:2], 2'b00};
    assign lane_shift = {addr_i[1:0], 3'b000};

    always @(*) begin
        mem_wdata_o  = 32'b0;
        mem_wstrb_o  = 4'b0000;
        load_data_o  = 32'b0;
        misaligned_o = 1'b0;
        load_shifted = load_data_i >> lane_shift;

        if (load_en_i) begin
            case (funct3_i)
                F3_BYTE: begin
                    load_data_o = {
                        {24{load_shifted[7]}},
                        load_shifted[7:0]
                    };
                end

                F3_HALF: begin
                    if (addr_i[0]) begin
                        misaligned_o = 1'b1;
                        load_data_o  = 32'b0;
                    end
                    else begin
                        load_data_o = {
                            {16{load_shifted[15]}},
                            load_shifted[15:0]
                        };
                    end
                end

                F3_WORD: begin
                    if (addr_i[1:0] != 2'b00) begin
                        misaligned_o = 1'b1;
                        load_data_o  = 32'b0;
                    end
                    else begin
                        load_data_o = load_data_i;
                    end
                end

                F3_BYTE_U: begin
                    load_data_o = {24'b0, load_shifted[7:0]};
                end

                F3_HALF_U: begin
                    if (addr_i[0]) begin
                        misaligned_o = 1'b1;
                        load_data_o  = 32'b0;
                    end
                    else begin
                        load_data_o = {16'b0, load_shifted[15:0]};
                    end
                end

                default: load_data_o = 32'b0;
            endcase
        end

        if (store_en_i) begin
            case (funct3_i)
                F3_BYTE: begin
                    mem_wstrb_o = 4'b0001 << addr_i[1:0];
                    mem_wdata_o =
                        {24'b0, store_data_i[7:0]} << lane_shift;
                end

                F3_HALF: begin
                    if (addr_i[0]) begin
                        misaligned_o = 1'b1;
                        mem_wstrb_o  = 4'b0000;
                        mem_wdata_o  = 32'b0;
                    end
                    else begin
                        mem_wstrb_o = 4'b0011 << addr_i[1:0];
                        mem_wdata_o =
                            {16'b0, store_data_i[15:0]} << lane_shift;
                    end
                end

                F3_WORD: begin
                    if (addr_i[1:0] != 2'b00) begin
                        misaligned_o = 1'b1;
                        mem_wstrb_o  = 4'b0000;
                        mem_wdata_o  = 32'b0;
                    end
                    else begin
                        mem_wstrb_o = 4'b1111;
                        mem_wdata_o = store_data_i;
                    end
                end

                default: begin
                    mem_wstrb_o = 4'b0000;
                    mem_wdata_o = 32'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
