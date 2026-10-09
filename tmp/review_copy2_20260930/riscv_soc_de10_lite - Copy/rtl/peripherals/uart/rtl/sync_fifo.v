`default_nettype none

// ============================================================================
// Module    : sync_fifo
// Chức năng : FIFO đồng bộ một miền clock, giao tiếp ready/valid hai phía.
//
// ĐẶC TẢ THAM SỐ:
//   - DATA_WIDTH >= 1: số bit của mỗi phần tử.
//   - DEPTH >= 1: số phần tử lưu được; không bắt buộc là lũy thừa của hai.
//   - Con trỏ quay vòng tường minh tại DEPTH-1, hỗ trợ cả DEPTH=1.
//
// ĐẶC TẢ GHI:
//   - Ghi tại cạnh lên khi write_valid && write_ready.
//   - Phía ghi phải giữ write_valid và write_data ổn định khi write_ready=0.
//   - write_ready=0 khi FIFO full hoặc đang reset.
//
// ĐẶC TẢ ĐỌC:
//   - Đọc tại cạnh lên khi read_valid && read_ready.
//   - read_data kiểu nhìn trước: luôn phản ánh phần tử cũ nhất khi read_valid=1.
//   - read_data không có ý nghĩa khi read_valid=0.
//   - Khi read_valid=1 và read_ready=0, read_data/read_valid được giữ ổn định.
//
// ĐẶC TẢ ĐỒNG THỜI VÀ RESET:
//   - Ghi và đọc hợp lệ cùng một cạnh được hỗ trợ; mức chứa không đổi.
//   - Khi full, write_ready=0 kể cả khi read_ready=1; chu kỳ đó chỉ pop.
//   - Reset xóa con trỏ và mức chứa, không xóa mảng memory.
//   - Trong reset: empty=1, full=0, write_ready=0, read_valid=0.
// ============================================================================
module sync_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  write_valid,
    output wire                  write_ready,

    output wire [DATA_WIDTH-1:0] read_data,
    output wire                  read_valid,
    input  wire                  read_ready,

    output wire                  full,
    output wire                  empty
);

    // Trả về số bit tối thiểu để biểu diễn các giá trị từ 0 đến value-1.
    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp  = value - 1;
            clog2 = 0;

            while (temp > 0) begin
                temp  = temp >> 1;
                clog2 = clog2 + 1;
            end
        end
    endfunction

    // FIFO một phần tử vẫn cần tối thiểu một bit con trỏ và một bit đếm.
    localparam integer POINTER_WIDTH =
        (DEPTH <= 1) ? 1 : clog2(DEPTH);

    localparam integer COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : clog2(DEPTH + 1);

    localparam integer LAST_ADDRESS = DEPTH - 1;

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [POINTER_WIDTH-1:0] write_pointer;
    reg [POINTER_WIDTH-1:0] read_pointer;
    reg [COUNT_WIDTH-1:0]   occupancy;

    wire push;
    wire pop;

    assign full  = (occupancy == DEPTH);
    assign empty = (occupancy == {COUNT_WIDTH{1'b0}});

    // Khóa cả hai đầu bắt tay để không có giao dịch trong reset, kể cả khi
    // phía ghi hoặc phía đọc vẫn giữ yêu cầu ở mức 1.
    assign write_ready = rst_n && !full;
    assign read_valid  = rst_n && !empty;

    assign push = write_valid && write_ready;
    assign pop  = read_valid && read_ready;

    // Đầu ra nhìn trước. Phía đọc chỉ được dùng giá trị này khi read_valid=1;
    // memory được chủ ý không xóa bằng reset.
    assign read_data = memory[read_pointer];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= {POINTER_WIDTH{1'b0}};
            read_pointer  <= {POINTER_WIDTH{1'b0}};
            occupancy     <= {COUNT_WIDTH{1'b0}};
        end else begin
            if (push) begin
                memory[write_pointer] <= write_data;

                if (write_pointer == LAST_ADDRESS) begin
                    write_pointer <= {POINTER_WIDTH{1'b0}};
                end else begin
                    write_pointer <= write_pointer + 1'b1;
                end
            end

            if (pop) begin
                if (read_pointer == LAST_ADDRESS) begin
                    read_pointer <= {POINTER_WIDTH{1'b0}};
                end else begin
                    read_pointer <= read_pointer + 1'b1;
                end
            end

            case ({push, pop})
                2'b10: begin
                    occupancy <= occupancy + 1'b1;
                end

                2'b01: begin
                    occupancy <= occupancy - 1'b1;
                end

                default: begin
                    occupancy <= occupancy;
                end
            endcase
        end
    end
/*
    // Kiểm tra tham số chỉ phục vụ mô phỏng, không tạo logic phần cứng.
    // synthesis translate_off
    initial begin
        if (DATA_WIDTH < 1) begin
            $display("SYNC_FIFO_PARAMETER_ERROR: DATA_WIDTH must be >= 1");
            $finish;
        end

        if (DEPTH < 1) begin
            $display("SYNC_FIFO_PARAMETER_ERROR: DEPTH must be >= 1");
            $finish;
        end
    end
    // synthesis translate_on
*/
endmodule

`default_nettype wire
