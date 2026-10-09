`default_nettype none

// =============================================================================
// Module      : intel_sync_ram_1p
// Chức năng   : RAM đồng bộ một cổng, 32 bit, có byte write-enable.
//
// Khi tổng hợp cho MAX 10, wrapper dùng altsyncram để kết quả ánh xạ chắc chắn
// vào M9K. Khi mô phỏng RTL, mảng Verilog giữ khả năng quan sát và không cần
// thư viện primitive Intel. Dữ liệu đọc xuất hiện sau cạnh clock có en_i=1.
// =============================================================================
module intel_sync_ram_1p #(
    // Số bit của mỗi phần tử lưu trữ, không phải số byte.
    parameter integer WIDTH = 32,
    // Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
    parameter integer WORDS = 2048,
    // Số bit địa chỉ phần tử; phải đủ biểu diễn các chỉ số 0..WORDS-1.
    parameter integer ADDR_WIDTH = 11,
    // Số byte lane ghi, mỗi lane 8 bit; cấu hình phải khớp WIDTH.
    parameter integer BYTE_COUNT = 4
) (
    // Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
    input  wire                       clk_i,
    // Cho phép đọc tại cạnh lên; output giữ giá trị cũ khi en=0.
    input  wire                       en_i,
    // Cho phép ghi tại cạnh lên khi en=1; chỉ cập nhật byteena đã chọn.
    input  wire                       we_i,
    // Bit n cho phép ghi 8 bit data_i[n*8 +: 8].
    input  wire [BYTE_COUNT-1:0]      byteena_i,
    // Chỉ số phần tử 0..WORDS-1 (địa chỉ word/entry), không phải địa chỉ byte CPU.
    input  wire [ADDR_WIDTH-1:0]      addr_i,
    // Dữ liệu ghi storage; lấy mẫu tại cạnh en && we cùng địa chỉ và byteena.
    input  wire [WIDTH-1:0]           data_i,
    // Dữ liệu đọc xuất hiện sau cạnh en; RAM read-during-write trả dữ liệu cũ.
    output wire [WIDTH-1:0]           q_o
);

`ifdef FPGA_SYNTHESIS
    // Dữ liệu trả về từ primitive altsyncram, nối tới output wrapper.
    wire [WIDTH-1:0] ram_q;

    altsyncram u_altsyncram (
        .address_a(addr_i),
        .clock0(clk_i),
        .rden_a(en_i),
        .wren_a(en_i && we_i),
        .byteena_a(byteena_i),
        .data_a(data_i),
        .q_a(ram_q),
        .aclr0(1'b0),
        .addressstall_a(1'b0)
    );
    defparam
        u_altsyncram.intended_device_family = "MAX 10",
        u_altsyncram.operation_mode = "SINGLE_PORT",
        u_altsyncram.width_a = WIDTH,
        u_altsyncram.widthad_a = ADDR_WIDTH,
        u_altsyncram.numwords_a = WORDS,
        u_altsyncram.width_byteena_a = BYTE_COUNT,
        u_altsyncram.byte_size = 8,
        u_altsyncram.outdata_reg_a = "UNREGISTERED",
        u_altsyncram.read_during_write_mode_port_a = "OLD_DATA",
        u_altsyncram.lpm_type = "altsyncram";

    assign q_o = ram_q;
`else
    // Mảng lưu trữ backend mô phỏng; primitive Intel thay thế khi tổng hợp.
    reg [WIDTH-1:0] mem [0:WORDS-1];
    // Thanh ghi dữ liệu đọc của backend mô phỏng; giữ khi en=0.
    reg [WIDTH-1:0] q_q;
    // Chỉ số vòng lặp cập nhật từng byte lane được byteena cho phép.
    integer byte_index;

    always @(posedge clk_i) begin
        if (en_i) begin
            q_q <= mem[addr_i];
            if (we_i) begin
                for (byte_index = 0; byte_index < BYTE_COUNT;
                     byte_index = byte_index + 1) begin
                    if (byteena_i[byte_index])
                        mem[addr_i][byte_index*8 +: 8] <=
                            data_i[byte_index*8 +: 8];
                end
            end
        end
    end

    assign q_o = q_q;
`endif

endmodule

`default_nettype wire
