// =====================================
// Module TOP kết nối DE10 Lite
// =====================================

module DE10_CORE (

    input CLOCK_50,
    input [1:0] KEY,
    input [9:0] SW,
    
    input GPIO_0,

    output [9:0] LEDR,
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5,

    output GPIO_1,

    inout  I2C_SCL,
    inout  I2C_SDA,

    output VGA_HS,
    output VGA_VS,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B
);

    CORE core_soc_cnn (

        // Input 
        .clk               (CLOCK_50),
        .reset             (KEY[0]),

        .SW                (SW),

        .GPIO_0            (GPIO_0),

        // Output
        .LEDR              (LEDR),

        .HEX0              (HEX0),
        .HEX1              (HEX1),
        .HEX2              (HEX2),
        .HEX3              (HEX3),
        .HEX4              (HEX4),
        .HEX5              (HEX5),

        .GPIO_1            (GPIO_1),

        .I2C_SCL           (I2C_SCL),
        .I2C_SDA           (I2C_SDA),

        .VGA_HS            (VGA_HS),
        .VGA_VS            (VGA_VS),
        .VGA_R             (VGA_R),
        .VGA_G             (VGA_G),
        .VGA_B             (VGA_B)
    );
endmodule