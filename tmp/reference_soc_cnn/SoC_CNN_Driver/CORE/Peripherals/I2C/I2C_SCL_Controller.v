// ============================================================================
// Module I2C_SCL_Controller
// ----------------------------------------------------------------------------
// Pad driver open-drain cho đường SCL + mux line-owner (mục A của plan).
//
// Open-drain:
//   scl_oe = 1 -> kéo SCL xuống 0 (active pull-down)
//   scl_oe = 0 -> thả line (Hi-Z) -> pull-up ngoài kéo lên 1
//   (KHÔNG bao giờ drive '1' trực tiếp — đúng chuẩn I2C)
//
// Line-owner mux:
//   recovery_active = 0 -> Bit_Controller sở hữu SCL
//   recovery_active = 1 -> Bus_Recovery   sở hữu SCL
//   (đảm bảo nguyên tắc: chỉ 1 FSM drive line tại một thời điểm)
//
// `1'bz` tristate được CÔ LẬP tại module lá này.
// scl_in_raw đưa ra ngoài -> qua I2C_Input_Filter -> mới vào FSM.
// Clock-stretch detect KHÔNG đặt ở đây (cần tín hiệu đã lọc) — xử lý ở
// Bit_Controller.
// ============================================================================
module I2C_SCL_Controller (
    // Owner: Bit_Controller
    input   bit_scl_oe,
    // Owner: Bus_Recovery
    input   rec_scl_oe,
    // Chọn owner
    input   recovery_active,

    // Chân vật lý (open-drain, cần pull-up ngoài)
    inout   scl_pad,

    // Mức bus đọc về (thô, chưa lọc)
    output  scl_in_raw
);

    // Mux owner: chọn oe theo trạng thái recovery
    wire scl_oe = recovery_active ? rec_scl_oe : bit_scl_oe;

    // Open-drain: chỉ kéo low hoặc thả
    assign scl_pad    = scl_oe ? 1'b0 : 1'bz;

    // Đọc mức line
    assign scl_in_raw = scl_pad;

endmodule
