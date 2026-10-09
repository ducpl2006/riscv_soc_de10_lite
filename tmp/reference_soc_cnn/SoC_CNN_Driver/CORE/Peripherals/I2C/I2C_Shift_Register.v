// ============================================================================
// Module I2C_Shift_Register
// ----------------------------------------------------------------------------
// Thanh ghi dịch 8-bit, MSB-first (chuẩn I2C), dùng chung cho TX và RX.
//
// TX (gửi byte):
//   1. `load` = 1 -> nạp song song `data_in`
//   2. đọc `bit_out` (= MSB) đưa ra SDA
//   3. `shift` = 1 mỗi bit -> dịch trái, MSB kế tiếp lên `bit_out`
//   (khi TX, `shift_in_bit` không quan trọng)
//
// RX (nhận byte):
//   1. mỗi bit sample được đưa vào `shift_in_bit`
//   2. `shift` = 1 -> dịch trái, bit mới vào LSB
//   3. sau 8 lần shift -> `data_out` = byte nhận đủ
//
// load ưu tiên hơn shift nếu cùng lúc.
// Reset: active-low.
// ============================================================================
module I2C_Shift_Register (
    input           clk,
    input           reset,          // active-low

    input           load,           // nạp song song (TX)
    input  [7:0]    data_in,

    input           shift,          // dịch 1 bit
    input           shift_in_bit,   // bit vào LSB (RX)

    output          bit_out,        // bit ra hiện tại = MSB (TX)
    output [7:0]    data_out        // giá trị song song hiện tại (RX)
);

    reg [7:0] shreg;

    always @(posedge clk) begin
        if (!reset)
            shreg <= 8'h00;
        else if (load)
            shreg <= data_in;                       // nạp song song
        else if (shift)
            shreg <= {shreg[6:0], shift_in_bit};    // dịch trái, MSB-first
    end

    assign bit_out  = shreg[7];
    assign data_out = shreg;

endmodule
