from pathlib import Path
p = Path('rtl/bus/soc_bus.v')
s = p.read_text(encoding='utf-8')
start = s.index('// Single-master')
end = s.index('module soc_bus')
s = s[:start] + '''// Module: soc_bus
// Purpose: native bus một master, một giao dịch outstanding, cắt hai chiều timing.
// Clock: clk_i, cạnh lên. Reset: rst_i đồng bộ active-high, chặn handshake ngay.
// Inputs: req/we/addr/wdata/wstrb từ CPU; response đóng gói theo lane slave.
// Outputs: payload đã chốt và one-hot req tới slave; response đã chốt về CPU.
// Protocol: CPU giữ payload tới req && ready; slave commit tại slave_req && ready.
// Latency: chụp tại N, slave sớm nhất N+1, CPU hoàn tất sớm nhất N+2.
// Error behavior: invalid/unaligned/write ROM hoặc slave err trả ready+err.
// Không capture lại request cũ ở cạnh trả response; giao dịch kế chụp ở cạnh sau.
// Reset không rollback side effect đã xảy ra tại slave trước response CPU.
''' + s[end:]
s = s.replace('    // Master request.', '    // Clock cho thanh ghi request/response.\n    input wire clk_i,\n    // Master request.', 1)
s = s.replace('    // Reset tích cực cao: decoder tổ hợp khóa request và response ngay khi rst=1.', '    // Reset active-high xóa giao dịch đang chờ và chặn handshake.')
s = s.replace('    // Master response.', '''    // Store payload, giữ đến response CPU; bus chụp cùng addr/we.
    input wire [31:0] wdata_i,
    input wire [3:0] wstrb_i,
    // Payload chốt của giao dịch hiện tại, dùng chung cho mọi slave.
    output reg slave_we_o,
    output reg [31:0] slave_addr_o,
    output reg [31:0] slave_wdata_o,
    output reg [3:0] slave_wstrb_o,
    // Master response.''', 1)
start = s.index('    // Chỉ số slave đã giải mã;')
s = s[:start] + '''    localparam [1:0] IDLE=2'd0, ACCESS=2'd1, RESPONSE=2'd2;
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
            else if ((slave_addr_o & `SOC_MMIO_MASK) == `SOC_GPIO_BASE)
                selected = `SOC_SLAVE_GPIO;
            else if ((slave_addr_o & `SOC_MMIO_MASK) == `SOC_UART_BASE)
                selected = `SOC_SLAVE_UART;
            else if ((slave_addr_o & `SOC_MMIO_MASK) == `SOC_I2C_BASE)
                selected = `SOC_SLAVE_I2C;
            else if ((slave_addr_o & `SOC_QNN_MASK) == `SOC_QNN_BASE)
                selected = `SOC_SLAVE_QNN;
            else if ((slave_addr_o & `SOC_MMIO_MASK) == `SOC_TIMER_BASE)
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
'''
p.write_text(s, encoding='utf-8')
p = Path('rtl/soc/rv32_soc.v')
s = p.read_text(encoding='utf-8')
s = s.replace('    // Request và response của mỗi slave', '''    // Payload sau thanh ghi request của bus; slave không dùng trực tiếp dmem_*.
    wire bus_we;
    wire [31:0] bus_addr, bus_wdata;
    wire [3:0] bus_wstrb;
    // Request và response của mỗi slave''')
s = s.replace('    ) u_bus (\n', '''    ) u_bus (
        .clk_i(clk_i),
        .wdata_i(dmem_wdata),
        .wstrb_i(dmem_wstrb),
        .slave_we_o(bus_we),
        .slave_addr_o(bus_addr),
        .slave_wdata_o(bus_wdata),
        .slave_wstrb_o(bus_wstrb),
''')
i = s.index('    // 3. Bộ nhớ:')
s = s[:i] + s[i:].replace('dmem_addr', 'bus_addr').replace('dmem_we', 'bus_we').replace('dmem_wdata', 'bus_wdata').replace('dmem_wstrb', 'bus_wstrb')
p.write_text(s, encoding='utf-8')
