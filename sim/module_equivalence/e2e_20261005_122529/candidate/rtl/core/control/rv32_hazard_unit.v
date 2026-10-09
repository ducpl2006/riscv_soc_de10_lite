`default_nettype none
`include "rv32_defs.vh"

// Hazard dữ liệu cho pipeline RV32I năm tầng; toàn bộ logic là tổ hợp.
// Load-use giữa ID và EX chèn một bubble; MEM chờ thì bộ điều khiển giữ pipeline.
// Forwarding tới EX ưu tiên EX/MEM hơn MEM/WB vì chứa giá trị mới hơn.
// Load tại MEM chưa được forward; phải chờ dữ liệu chốt ở MEM/WB.
// x0 không gây hazard và không được chọn làm nguồn forwarding.
module rv32_hazard_unit (
    // Nguồn mà lệnh ID thực sự đọc; uses_rs* loại bỏ phụ thuộc giả.
    input  wire [4:0] id_rs1_addr_i,
    input  wire [4:0] id_rs2_addr_i,
    input  wire       id_uses_rs1_i,
    input  wire       id_uses_rs2_i,

    // Lệnh EX: rd của load dùng để phát hiện phụ thuộc ID; rs1/rs2
    // chọn nguồn forwarding cho lệnh đang thực thi.
    input  wire       ex_valid_i,
    input  wire       ex_load_i,
    input  wire [4:0] ex_rd_addr_i,
    input  wire [4:0] ex_rs1_addr_i,
    input  wire [4:0] ex_rs2_addr_i,

    // Nguồn EX/MEM: chỉ dùng kết quả ghi rd hợp lệ, khác x0 và không phải load.
    input  wire       mem_valid_i,
    input  wire       mem_reg_write_i,
    input  wire       mem_load_i,
    input  wire [4:0] mem_rd_addr_i,

    // Nguồn MEM/WB: kết quả đã sẵn sàng, bao gồm dữ liệu load.
    input  wire       wb_valid_i,
    input  wire       wb_reg_write_i,
    input  wire [4:0] wb_rd_addr_i,

    // Hazard thô ID/EX; bộ điều khiển còn phân xử với chờ MEM và hủy lệnh.
    output reg        stall_load_use_o,

    // Hai mã chọn độc lập: 00=ID/EX, 01=MEM/WB, 10=EX/MEM; không phát 11.
    output reg  [1:0] forward_rs1_o,
    output reg  [1:0] forward_rs2_o
);

    localparam [1:0]
        FWD_NONE = `RV32_FWD_NONE,
        FWD_WB   = `RV32_FWD_WB,
        FWD_MEM  = `RV32_FWD_MEM;

    always @(*) begin
        stall_load_use_o = 1'b0;
        forward_rs1_o    = FWD_NONE;
        forward_rs2_o    = FWD_NONE;

        // ID chỉ phải chờ khi thực sự đọc đích load khác x0 của lệnh EX.
        if (ex_valid_i && ex_load_i && (ex_rd_addr_i != 5'd0)) begin
            if ((id_uses_rs1_i && (id_rs1_addr_i == ex_rd_addr_i)) ||
                (id_uses_rs2_i && (id_rs2_addr_i == ex_rd_addr_i))) begin
                stall_load_use_o = 1'b1;
            end
        end

        // Nguồn rs1: chọn kết quả mới nhất sẵn sàng; EX/MEM thắng MEM/WB.
        if (mem_valid_i && mem_reg_write_i && !mem_load_i &&
            (mem_rd_addr_i != 5'd0) &&
            (mem_rd_addr_i == ex_rs1_addr_i)) begin
            forward_rs1_o = FWD_MEM;
        end
        else if (wb_valid_i && wb_reg_write_i &&
                 (wb_rd_addr_i != 5'd0) &&
                 (wb_rd_addr_i == ex_rs1_addr_i)) begin
            forward_rs1_o = FWD_WB;
        end

        // Nguồn rs2 có cùng thứ tự ưu tiên; dùng cả cho ALU, nhánh và store.
        if (mem_valid_i && mem_reg_write_i && !mem_load_i &&
            (mem_rd_addr_i != 5'd0) &&
            (mem_rd_addr_i == ex_rs2_addr_i)) begin
            forward_rs2_o = FWD_MEM;
        end
        else if (wb_valid_i && wb_reg_write_i &&
                 (wb_rd_addr_i != 5'd0) &&
                 (wb_rd_addr_i == ex_rs2_addr_i)) begin
            forward_rs2_o = FWD_WB;
        end
    end

endmodule

`default_nettype wire
