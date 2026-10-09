`default_nettype none
`include "rv32_defs.vh"

// MEM: giao dịch dữ liệu word, phát hiện chờ/lỗi và chọn dữ liệu ghi về WB.
// Logic tổ hợp; core giữ EX/MEM và toàn bộ payload khi req && !ready.
// Giao dịch hoàn tất tại cạnh req && ready; err chỉ có nghĩa tại cạnh đó.
// Chi tiết bus dữ liệu: docs/giao_tiep_rtl_vi.md, mục 3.
module rv32_mem_stage (
    // Reset, halt hoặc trap WB đều chặn yêu cầu dữ liệu mới.
    input  wire         rst_i,
    input  wire         halted_i,
    input  wire         wb_trap_event_i,

    // Lệnh EX/MEM: chỉ lệnh hợp lệ, chưa có ngoại lệ mới được truy cập bus.
    input  wire         valid_i,
    input  wire         exc_valid_i,

    // Truy cập dữ liệu: địa chỉ byte từ ALU, rs2 đã forwarding cho store;
    // funct3 chọn cỡ truy cập và kiểu mở rộng dữ liệu load.
    input  wire         load_i,
    input  wire         store_i,
    input  wire [31:0]  alu_result_i,
    input  wire [31:0]  store_data_i,
    input  wire [2:0]   funct3_i,

    // Nguồn ghi về: RV32_WB_ALU / LOAD / PC4; PC+4 là địa chỉ trở về của jump.
    input  wire [1:0]   wb_sel_i,
    input  wire [31:0]  pc4_i,

    // Đáp ứng bus: ready kết thúc giao dịch tại cạnh req && ready, kể cả lỗi.
    // Rdata chỉ được sử dụng cho load thành công; err chỉ có nghĩa lúc hoàn tất.
    input  wire [31:0]  dmem_rdata_i,
    input  wire         dmem_ready_i,
    input  wire         dmem_err_i,

    // Yêu cầu giữ tới cạnh req && ready; we=1 cho store, bằng 0 khi không req.
    output wire         dmem_req_o,
    output wire         dmem_we_o,

    // Địa chỉ đã căn xuống biên 4 byte; wdata và wstrb chọn đúng byte trong word.
    // Bit n của wstrb cho phép ghi byte [8*n +: 8]; không store thì wstrb=0.
    output wire [31:0]  dmem_addr_o,
    output wire [31:0]  dmem_wdata_o,
    output wire [3:0]   dmem_wstrb_o,

    // Stall giữ EX/MEM khi req && !ready; lỗi chỉ phát khi req && ready && err.
    output wire         stall_o,
    output wire         fault_raw_o,

    // Kết quả đã chọn để chốt vào MEM/WB; core loại quyền ghi rd khi có lỗi.
    output reg  [31:0]  wb_data_o
);

    localparam [1:0] WB_LOAD = `RV32_WB_LOAD;
    localparam [1:0] WB_PC4  = `RV32_WB_PC4;

    // LSU căn địa chỉ theo word, đặt byte store và mở rộng dữ liệu load.
    wire [31:0] mem_lsu_addr;
    wire [31:0] mem_lsu_wdata;
    wire [3:0]  mem_lsu_wstrb;
    wire [31:0] mem_load_data;
    // Căn chỉnh đã kiểm tra tại EX; không phát lại ngoại lệ ở MEM.
    wire        mem_lsu_misaligned_unused;

    rv32_lsu u_lsu_mem (
        .addr_i         (alu_result_i),
        .funct3_i       (funct3_i),
        .load_en_i      (load_i),
        .store_en_i     (store_i),
        .store_data_i   (store_data_i),
        .load_data_i    (dmem_rdata_i),
        .mem_addr_o     (mem_lsu_addr),
        .mem_wdata_o    (mem_lsu_wdata),
        .mem_wstrb_o    (mem_lsu_wstrb),
        .load_data_o    (mem_load_data),
        .misaligned_o   (mem_lsu_misaligned_unused)
    );

    // Chặn mọi truy cập của bubble/lệnh lỗi hoặc khi reset, halt, trap WB.
    // Core giữ EX/MEM trong lúc stall nên req và dữ liệu không đổi khi chờ.
    assign dmem_req_o = valid_i && !exc_valid_i &&
                        (load_i || store_i) &&
                        !rst_i && !halted_i && !wb_trap_event_i;
    assign dmem_we_o    = dmem_req_o && store_i;
    assign dmem_addr_o  = mem_lsu_addr;
    assign dmem_wdata_o = mem_lsu_wdata;
    assign dmem_wstrb_o = dmem_we_o ? mem_lsu_wstrb : 4'b0000;

    // Giao dịch hoàn tất tại cạnh lên khi req && ready, kể cả giao dịch lỗi.
    wire dmem_fire;

    assign dmem_fire   = dmem_req_o && dmem_ready_i;
    assign stall_o     = dmem_req_o && !dmem_ready_i;
    // Err khi không có giao dịch hoàn tất không được tạo ngoại lệ.
    assign fault_raw_o = dmem_fire && dmem_err_i;

    // Chọn kết quả cho MEM/WB; core chỉ cho load thành công quyền ghi rd.
    always @(*) begin
        case (wb_sel_i)
            WB_LOAD: wb_data_o = mem_load_data;
            WB_PC4 : wb_data_o = pc4_i;
            default: wb_data_o = alu_result_i;
        endcase
    end

endmodule

`default_nettype wire
