// ============================================================================
// Module I2C_SDA_Controller
// ----------------------------------------------------------------------------
// Pad driver open-drain cho đường SDA + mux line-owner (mục A của plan).
//
// Open-drain:
//   sda_oe = 1 -> kéo SDA xuống 0 (active pull-down)
//   sda_oe = 0 -> thả line (Hi-Z) -> pull-up ngoài kéo lên 1
//
// Line-owner mux:
//   recovery_active = 0 -> Bit_Controller sở hữu SDA
//   recovery_active = 1 -> Bus_Recovery   sở hữu SDA
//
// `1'bz` tristate được CÔ LẬP tại module lá này.
// sda_in_raw đưa ra ngoài -> qua I2C_Input_Filter -> mới vào FSM.
// Arbitration detect KHÔNG đặt ở đây (cần tín hiệu đã lọc + ngữ cảnh pha) —
// xử lý ở Bit_Controller: so sánh bit dự định drive với sda_in tại pha C.
// ============================================================================
module I2C_SDA_Controller (
    // Owner: Bit_Controller
    input   bit_sda_oe,
    // Owner: Bus_Recovery
    input   rec_sda_oe,
    // Chọn owner
    input   recovery_active,

    // Chân vật lý (open-drain, cần pull-up ngoài)
    inout   sda_pad,

    // Mức bus đọc về (thô, chưa lọc)
    output  sda_in_raw
);

    // Mux owner
    wire sda_oe = recovery_active ? rec_sda_oe : bit_sda_oe;

    // Open-drain: chỉ kéo low hoặc thả
    assign sda_pad    = sda_oe ? 1'b0 : 1'bz;

    // Đọc mức line
    assign sda_in_raw = sda_pad;

endmodule
