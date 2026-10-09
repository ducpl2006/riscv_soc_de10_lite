`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Shift_Register
// Kiểm tra: TX (nạp + dịch ra MSB-first), RX (dịch vào + ghép byte).
// ============================================================================
module tb_I2C_Shift_Register;

    reg         clk = 0;
    reg         reset;
    reg         load;
    reg  [7:0]  data_in;
    reg         shift;
    reg         shift_in_bit;
    wire        bit_out;
    wire [7:0]  data_out;

    integer     errors = 0;
    integer     i;
    reg  [7:0]  tx_val;
    reg  [7:0]  rx_val;

    I2C_Shift_Register dut (
        .clk(clk), .reset(reset),
        .load(load), .data_in(data_in),
        .shift(shift), .shift_in_bit(shift_in_bit),
        .bit_out(bit_out), .data_out(data_out)
    );

    always #5 clk = ~clk;

    initial begin
        reset=0; load=0; data_in=0; shift=0; shift_in_bit=0;
        #12 reset=1;

        // ---- TX: nạp 0xA5 = 1010_0101, đọc bit_out MSB-first ----
        tx_val = 8'hA5;
        @(negedge clk); load=1; data_in=tx_val;
        @(negedge clk); load=0;
        for (i=7; i>=0; i=i-1) begin
            if (bit_out !== tx_val[i]) begin
                $display("  [ERR] TX bit %0d = %b, expect %b", i, bit_out, tx_val[i]);
                errors=errors+1;
            end
            @(negedge clk); shift=1; shift_in_bit=0;
            @(negedge clk); shift=0;
        end

        // ---- RX: dịch vào 0x3C = 0011_1100 MSB-first ----
        rx_val = 8'h3C;
        for (i=7; i>=0; i=i-1) begin
            @(negedge clk); shift=1; shift_in_bit=rx_val[i];
            @(negedge clk); shift=0;
        end
        if (data_out !== rx_val) begin
            $display("  [ERR] RX data_out = %h, expect %h", data_out, rx_val);
            errors=errors+1;
        end

        if (errors==0) $display("PASS: I2C_Shift_Register");
        else           $display("FAIL: I2C_Shift_Register (%0d errors)", errors);
        $finish;
    end

endmodule
