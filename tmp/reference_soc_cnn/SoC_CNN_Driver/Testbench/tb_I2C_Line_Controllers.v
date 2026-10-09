`timescale 1ns/1ps
// ============================================================================
// tb_I2C_Line_Controllers
// Kiểm tra open-drain + mux line-owner cho SCL/SDA controller:
//  - oe=1 -> kéo low; oe=0 -> thả (pull-up = high)
//  - recovery_active chọn đúng owner
//  - thiết bị ngoài kéo low -> đọc về 0 dù ta đã thả
// ============================================================================
module tb_I2C_Line_Controllers;

    reg  bit_scl_oe, rec_scl_oe;
    reg  bit_sda_oe, rec_sda_oe;
    reg  recovery_active;
    reg  ext_low;               // thiết bị ngoài kéo cả 2 line xuống 0

    wire scl_pad, sda_pad;
    wire scl_in, sda_in;

    integer errors = 0;

    // Pull-up ngoài
    pullup(scl_pad);
    pullup(sda_pad);

    // Thiết bị ngoài (slave/master khác) kéo low
    assign scl_pad = ext_low ? 1'b0 : 1'bz;
    assign sda_pad = ext_low ? 1'b0 : 1'bz;

    I2C_SCL_Controller u_scl (
        .bit_scl_oe(bit_scl_oe), .rec_scl_oe(rec_scl_oe),
        .recovery_active(recovery_active),
        .scl_pad(scl_pad), .scl_in_raw(scl_in)
    );

    I2C_SDA_Controller u_sda (
        .bit_sda_oe(bit_sda_oe), .rec_sda_oe(rec_sda_oe),
        .recovery_active(recovery_active),
        .sda_pad(sda_pad), .sda_in_raw(sda_in)
    );

    task chk; input val; input exp; input [8*24:1] name; begin
        if (val !== exp) begin
            $display("  [ERR] %0s = %b, expect %b", name, val, exp);
            errors = errors + 1;
        end
    end endtask

    initial begin
        bit_scl_oe=0; rec_scl_oe=0; bit_sda_oe=0; rec_sda_oe=0;
        recovery_active=0; ext_low=0;
        #10;

        // 1) Thả cả 2 -> pull-up high
        chk(scl_in,1'b1,"idle scl"); chk(sda_in,1'b1,"idle sda");

        // 2) Bit owner kéo low
        bit_scl_oe=1; bit_sda_oe=1; #10;
        chk(scl_in,1'b0,"bit drive scl low"); chk(sda_in,1'b0,"bit drive sda low");
        bit_scl_oe=0; bit_sda_oe=0; #10;

        // 3) recovery_active=1 -> owner = recovery; bit oe bị bỏ qua
        recovery_active=1;
        bit_scl_oe=1; bit_sda_oe=1;     // owner cũ, phải bị mux bỏ qua
        rec_scl_oe=0; rec_sda_oe=0; #10;
        chk(scl_in,1'b1,"recov: bit ignored scl"); chk(sda_in,1'b1,"recov: bit ignored sda");
        rec_scl_oe=1; rec_sda_oe=1; #10;
        chk(scl_in,1'b0,"recov drive scl low"); chk(sda_in,1'b0,"recov drive sda low");
        recovery_active=0; rec_scl_oe=0; rec_sda_oe=0; bit_scl_oe=0; bit_sda_oe=0; #10;

        // 4) Ta thả nhưng thiết bị ngoài kéo low -> đọc về 0
        ext_low=1; #10;
        chk(scl_in,1'b0,"ext pulls scl low"); chk(sda_in,1'b0,"ext pulls sda low");
        ext_low=0; #10;
        chk(scl_in,1'b1,"released back high"); chk(sda_in,1'b1,"released back high");

        if (errors==0) $display("PASS: I2C_Line_Controllers");
        else           $display("FAIL: I2C_Line_Controllers (%0d errors)", errors);
        $finish;
    end

endmodule
