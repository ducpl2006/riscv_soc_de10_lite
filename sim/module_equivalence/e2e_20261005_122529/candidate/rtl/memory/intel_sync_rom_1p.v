`default_nettype none

// =============================================================================
// Module      : intel_sync_rom_1p
// Chức năng   : ROM đồng bộ một cổng, có backend altsyncram cho MAX 10.
//
// FPGA_SYNTHESIS được QSF định nghĩa khi chạy Quartus. Mô phỏng RTL dùng mảng
// Verilog để testbench có thể nạp vector trực tiếp; tổng hợp dùng primitive để
// bảo đảm trọng số lớn nằm trong M9K thay vì bị trải thành LUT/flip-flop.
// =============================================================================
module intel_sync_rom_1p #(
    // Số bit của mỗi phần tử lưu trữ, không phải số byte.
    parameter integer WIDTH = 8,
    // Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
    parameter integer WORDS = 256,
    // Số bit địa chỉ phần tử; phải đủ biểu diễn các chỉ số 0..WORDS-1.
    parameter integer ADDR_WIDTH = 8,
    // Khác 0: mô phỏng nạp HEX; backend Quartus dùng INIT_FILE trực tiếp.
    parameter integer USE_INIT_FILE = 0,
    // Đường dẫn file khởi tạo ROM; HEX cho mô phỏng, MIF/HEX phù hợp backend tổng hợp.
    parameter         INIT_FILE = "UNUSED"
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire                  clk_i,
    // Cho phép đọc tại cạnh lên; output giữ giá trị cũ khi en=0.
    input  wire                  en_i,
    // Chỉ số phần tử 0..WORDS-1 (địa chỉ word/entry), không phải địa chỉ byte CPU.
    input  wire [ADDR_WIDTH-1:0] addr_i,
    // Dữ liệu đọc xuất hiện sau cạnh en; RAM read-during-write trả dữ liệu cũ.
    output wire [WIDTH-1:0]      q_o
);

`ifdef FPGA_SYNTHESIS
    // Dữ liệu trả về từ primitive ROM, nối tới output wrapper.
    wire [WIDTH-1:0] rom_q;

    altsyncram u_altsyncram (
        .address_a(addr_i),
        .clock0(clk_i),
        .rden_a(en_i),
        .q_a(rom_q),
        .aclr0(1'b0),
        .addressstall_a(1'b0),
        .byteena_a(1'b1),
        .data_a({WIDTH{1'b0}}),
        .wren_a(1'b0)
    );
    defparam
        u_altsyncram.intended_device_family = "MAX 10",
        u_altsyncram.operation_mode = "ROM",
        u_altsyncram.width_a = WIDTH,
        u_altsyncram.widthad_a = ADDR_WIDTH,
        u_altsyncram.numwords_a = WORDS,
        u_altsyncram.outdata_reg_a = "UNREGISTERED",
        u_altsyncram.init_file = INIT_FILE,
        u_altsyncram.lpm_type = "altsyncram";

    assign q_o = rom_q;
`else
    // Mảng lưu trữ backend mô phỏng; primitive Intel thay thế khi tổng hợp.
    reg [WIDTH-1:0] mem [0:WORDS-1];
    // Thanh ghi dữ liệu đọc của backend mô phỏng; giữ khi en=0.
    reg [WIDTH-1:0] q_q;
    // Chỉ số vòng lặp khởi tạo ROM mô phỏng về 0 trước khi nạp file.
    integer index;
    initial begin
        for (index = 0; index < WORDS; index = index + 1)
            mem[index] = {WIDTH{1'b0}};
        if (USE_INIT_FILE != 0)
            $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk_i) begin
        if (en_i)
            q_q <= mem[addr_i];
    end
    assign q_o = q_q;
`endif

endmodule

`default_nettype wire
