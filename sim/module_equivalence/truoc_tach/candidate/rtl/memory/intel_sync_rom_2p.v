`default_nettype none

// =============================================================================
// Module      : intel_sync_rom_2p
// Chức năng   : ROM đồng bộ hai cổng đọc độc lập dùng chung một khối dữ liệu.
// Backend Quartus dùng altsyncram true-dual-port để ROM chương trình 128 KiB
// chỉ chiếm một bản trong M9K dù CPU đọc đồng thời instruction và .rodata.
// =============================================================================
module intel_sync_rom_2p #(
    // Số bit của mỗi phần tử lưu trữ, không phải số byte.
    parameter integer WIDTH = 32,
    // Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
    parameter integer WORDS = 32768,
    // Số bit địa chỉ phần tử; phải đủ biểu diễn các chỉ số 0..WORDS-1.
    parameter integer ADDR_WIDTH = 15,
    // Khác 0: mô phỏng nạp HEX; backend Quartus dùng INIT_FILE trực tiếp.
    parameter integer USE_INIT_FILE = 0,
    // Đường dẫn file khởi tạo ROM; HEX cho mô phỏng, MIF/HEX phù hợp backend tổng hợp.
    parameter         INIT_FILE = "UNUSED"
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire                  clk_i,
    // Cho phép đọc cổng A tại cạnh lên; độc lập với cổng còn lại.
    input  wire                  a_en_i,
    // Chỉ số phần tử ROM cổng A, không phải địa chỉ byte CPU.
    input  wire [ADDR_WIDTH-1:0] a_addr_i,
    // Dữ liệu đọc cổng A sau cạnh enable; giữ khi không enable.
    output wire [WIDTH-1:0]      a_q_o,
    // Cho phép đọc cổng B tại cạnh lên; độc lập với cổng còn lại.
    input  wire                  b_en_i,
    // Chỉ số phần tử ROM cổng B, không phải địa chỉ byte CPU.
    input  wire [ADDR_WIDTH-1:0] b_addr_i,
    // Dữ liệu đọc cổng B sau cạnh enable; giữ khi không enable.
    output wire [WIDTH-1:0]      b_q_o
);

`ifdef FPGA_SYNTHESIS
    // Dữ liệu primitive ROM cổng A, nối ra wrapper.
    wire [WIDTH-1:0] rom_a_q;
    // Dữ liệu primitive ROM cổng B, nối ra wrapper.
    wire [WIDTH-1:0] rom_b_q;

    altsyncram u_altsyncram (
        .address_a(a_addr_i), .address_b(b_addr_i),
        .clock0(clk_i), .clock1(clk_i),
        .rden_a(a_en_i), .rden_b(b_en_i),
        .q_a(rom_a_q), .q_b(rom_b_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(1'b1), .byteena_b(1'b1),
        .data_a({WIDTH{1'b0}}), .data_b({WIDTH{1'b0}}),
        .wren_a(1'b0), .wren_b(1'b0)
    );
    defparam
        u_altsyncram.intended_device_family = "MAX 10",
        u_altsyncram.operation_mode = "BIDIR_DUAL_PORT",
        u_altsyncram.width_a = WIDTH,
        u_altsyncram.widthad_a = ADDR_WIDTH,
        u_altsyncram.numwords_a = WORDS,
        u_altsyncram.width_b = WIDTH,
        u_altsyncram.widthad_b = ADDR_WIDTH,
        u_altsyncram.numwords_b = WORDS,
        u_altsyncram.address_reg_b = "CLOCK1",
        u_altsyncram.outdata_reg_a = "UNREGISTERED",
        u_altsyncram.outdata_reg_b = "UNREGISTERED",
        u_altsyncram.init_file = INIT_FILE,
        u_altsyncram.lpm_type = "altsyncram";

    assign a_q_o = rom_a_q;
    assign b_q_o = rom_b_q;
`else
    // Mảng lưu trữ backend mô phỏng; primitive Intel thay thế khi tổng hợp.
    reg [WIDTH-1:0] mem [0:WORDS-1];
    // Dữ liệu đọc cổng A sau cạnh enable; giữ khi không enable.
    reg [WIDTH-1:0] a_q;
    // Dữ liệu đọc cổng B sau cạnh enable; giữ khi không enable.
    reg [WIDTH-1:0] b_q;
    initial begin
        if (USE_INIT_FILE != 0)
            $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk_i) begin
        if (a_en_i) a_q <= mem[a_addr_i];
        if (b_en_i) b_q <= mem[b_addr_i];
    end
    assign a_q_o = a_q;
    assign b_q_o = b_q;
`endif

endmodule

`default_nettype wire
