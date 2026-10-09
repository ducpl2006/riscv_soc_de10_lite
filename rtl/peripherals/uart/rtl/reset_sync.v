`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Module    : reset_sync
// Chức năng : Đồng bộ quá trình nhả reset vào miền clock hệ thống.
//
// ĐẶC TẢ:
//   - arst_n là reset bất đồng bộ, tích cực mức thấp.
//   - Khi arst_n=0, rst_n xuống 0 ngay, không chờ cạnh clock.
//   - Khi arst_n trở lại 1, rst_n chỉ lên 1 sau hai cạnh lên liên tiếp của clk.
//   - rst_n là reset tích cực mức thấp dùng cho toàn bộ logic trong miền clk.
//   - Nguồn reset phải được kích hoạt khi khởi động để trạng thái mô phỏng và phần
//     cứng được xác định.
//
// GIAO DIỆN:
//   clk    : clock đích cần đồng bộ reset.
//   arst_n : reset thô bất đồng bộ, tích cực thấp.
//   rst_n  : reset đã được nhả đồng bộ, tích cực thấp.
// ============================================================================
module reset_sync (
    input  wire clk,
    input  wire arst_n,

    output wire rst_n
);
/*
    // Quartus dùng altera_attribute; các công cụ khác thường nhận ASYNC_REG.
`ifdef ALTERA_RESERVED_QIS
    (* altera_attribute =
           "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
`else
    (* ASYNC_REG = "TRUE" *)
`endif
*/
    reg [1:0] reset_sync_ff;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            reset_sync_ff <= 2'b00;
        end else begin
            // Mỗi cạnh clock dịch một bit 1 vào chuỗi đồng bộ.
            reset_sync_ff <= {
                reset_sync_ff[0],
                1'b1
            };
        end
    end

    assign rst_n = reset_sync_ff[1];

endmodule

`default_nettype wire
