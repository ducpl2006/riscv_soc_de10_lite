`default_nettype none

`include "soc_map.vh"

// Module: soc_bus
// Purpose: native bus một master, một giao dịch outstanding, cắt hai chiều timing.
// Clock: clk_i, cạnh lên. Reset: rst_i đồng bộ active-high, chặn handshake ngay.
// Inputs: req/we/addr/wdata/wstrb từ CPU; response đóng gói theo lane slave.
// Outputs: payload đã chốt và one-hot req tới slave; response đã chốt về CPU.
// Protocol: CPU giữ payload tới req && ready; slave commit tại slave_req && ready.
// Latency: chụp tại N, slave sớm nhất N+1, CPU hoàn tất sớm nhất N+2.
// Error behavior: invalid/unaligned/write ROM hoặc slave err trả ready+err.
// Không capture lại request cũ ở cạnh trả response; giao dịch kế chụp ở cạnh sau.
// Reset không rollback side effect đã xảy ra tại slave trước response CPU.
module soc_bus #(
    // Dung lượng ROM theo số word 32 bit; số byte bằng ROM_WORDS*4.
    parameter integer ROM_WORDS = 8192,
    // Dung lượng SRAM theo số word 32 bit; số byte bằng RAM_WORDS*4.
    parameter integer RAM_WORDS = 2048
) (
    // Clock cho thanh ghi request/response.
    input wire clk_i,
    // Master request. Address is a byte address aligned to a 32-bit word.
    // Reset active-high xóa giao dịch đang chờ và chặn handshake.
    input  wire         rst_i,
    // Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
    input  wire         req_i,
    // 1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
    input  wire         we_i,
    // Địa chỉ byte toàn cục của CPU, phải căn 4; decoder chọn ROM/RAM/MMIO.
    input  wire [31:0]  addr_i,
    // Store payload, giữ đến response CPU; bus chụp cùng addr/we.
    input wire [31:0] wdata_i,
    input wire [3:0] wstrb_i,
    // Payload chốt của giao dịch hiện tại, dùng chung cho mọi slave.
    output reg slave_we_o,
    output reg [31:0] slave_addr_o,
    output reg [31:0] slave_wdata_o,
    output reg [3:0] slave_wstrb_o,
    // Master response. ready && err terminates a failed transaction.
    // Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
    output reg  [31:0]  rdata_o,
    // Hoàn tất giao dịch tại cạnh req && ready; có thể kèm err.
    output reg          ready_o,
    // Lỗi địa chỉ/quyền truy cập; master chỉ xét khi req && ready.
    output reg          err_o,
    // Packed slave lanes, indexed by SOC_SLAVE_* from soc_map.vh.
    // Bit SOC_SLAVE_* chọn slave; tối đa một bit bằng 1, reset/idle bằng 0.
    output reg  [`SOC_SLAVE_COUNT-1:0]    slave_req_o,
    // Lane n dùng [n*32 +: 32]; response phải khớp lane request được chọn.
    input  wire [`SOC_SLAVE_COUNT*32-1:0] slave_rdata_i,
    // Bit n báo hoàn tất từ slave n; chỉ lane được chọn được trả về master.
    input  wire [`SOC_SLAVE_COUNT-1:0]    slave_ready_i,
    // Bit n báo lỗi từ slave n; chỉ xét cùng ready của chính lane đó.
    input  wire [`SOC_SLAVE_COUNT-1:0]    slave_err_i
);
    localparam [31:0] ROM_BYTES = ROM_WORDS * 4;
    localparam [31:0] RAM_BYTES = RAM_WORDS * 4;
    localparam [1:0] IDLE=2'd0, ACCESS=2'd1, RESPONSE=2'd2;
    reg [1:0] state_q;
    // Response không phụ thuộc combinational vào decoder/slave cùng chu kỳ.
    reg [31:0] response_data_q;
    reg response_err_q;
    integer selected;
    reg selected_ready, selected_err;
    reg [31:0] selected_data;

    always @* begin
        selected = -1;
        if (slave_addr_o[1:0] == 0) begin
            if (slave_addr_o < ROM_BYTES && !slave_we_o)
                selected = `SOC_SLAVE_ROM;
            else if (slave_addr_o >= `SOC_RAM_BASE &&
                     (slave_addr_o - `SOC_RAM_BASE) < RAM_BYTES)
                selected = `SOC_SLAVE_RAM;
            else if (slave_addr_o[31:12] == (`SOC_GPIO_BASE >> 12))
                selected = `SOC_SLAVE_GPIO;
            else if (slave_addr_o[31:12] == (`SOC_UART_BASE >> 12))
                selected = `SOC_SLAVE_UART;
            else if (slave_addr_o[31:12] == (`SOC_I2C_BASE >> 12))
                selected = `SOC_SLAVE_I2C;
            else if (slave_addr_o[31:12] == (`SOC_QNN_BASE >> 12))
                selected = `SOC_SLAVE_QNN;
            else if (slave_addr_o[31:12] == (`SOC_TIMER_BASE >> 12))
                selected = `SOC_SLAVE_TIMER;
        end
        slave_req_o = 0;
        selected_ready = 0;
        selected_err = 0;
        selected_data = 0;
        if (state_q == ACCESS && !rst_i) begin
            if (selected < 0) begin
                selected_ready = 1;
                selected_err = 1;
            end
            else begin
                slave_req_o[selected] = 1;
                selected_ready = slave_ready_i[selected];
                selected_err = slave_err_i[selected];
                selected_data = slave_rdata_i[selected*32 +: 32];
            end
        end
        ready_o = (state_q == RESPONSE) && !rst_i;
        err_o = ready_o && response_err_q;
        rdata_o = (ready_o && !response_err_q) ? response_data_q : 32'd0;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            slave_addr_o <= 0;
            slave_we_o <= 0;
            slave_wdata_o <= 0;
            slave_wstrb_o <= 0;
            response_data_q <= 0;
            response_err_q <= 0;
        end
        else begin
            case (state_q)
                IDLE: if (req_i) begin
                    slave_addr_o <= addr_i;
                    slave_we_o <= we_i;
                    slave_wdata_o <= wdata_i;
                    slave_wstrb_o <= wstrb_i;
                    state_q <= ACCESS;
                end
                ACCESS: if (selected_ready) begin
                    response_data_q <= selected_err ? 32'd0 : selected_data;
                    response_err_q <= selected_err;
                    state_q <= RESPONSE;
                end
                RESPONSE: if (req_i) state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
