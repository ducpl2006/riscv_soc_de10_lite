module GPIO (

    input clk,
    input reset,

    // -------------------------
    // BUS Interface
    // -------------------------
    input [31:0] addr,
    input [31:0] wr_data,
    input        write_en,
    input        read_en,

    // -------------------------
    // Kit DE10 input
    // -------------------------
    input [9:0] SW,
    //input [1:0] KEY,

    output reg [9:0] LEDR,

    // -------------------------
    // Đưa Hex ra ngoài giải mã
    // -------------------------
    output [23:0] hex_data_out,

    // ------------------------
    // Read data về BUS
    // ------------------------
    output reg [31:0] rd_data
);

    // ==============================================   
    // Address Map (offset từ base 0x1000_0000)
    // ==============================================
    // 0x00 --> LEDR        (write/read)
    // 0x04 --> HEX data    (write/read)
    // 0x0C --> SWITCH      (read)

    wire [7:0] offset = addr [7:0];

    // ============================
    // Register
    // ============================
    reg [23:0] hex_data;
    assign hex_data_out = hex_data;

    // ============================
    // WRITE Logic
    // ============================
    always @(posedge clk) begin
        
        if (!reset) begin
            LEDR        <= 10'b0;
            hex_data    <= 24'b0;
        end

        // WRITE
        else if (write_en) begin
            case (offset)

                // LEDR
                8'h00: LEDR <= wr_data[9:0];

                // HEX data
                8'h04: hex_data <= wr_data[23:0];

                default: ;
            endcase
        end

    end

    // READ
    always @(*) begin
        
        if (read_en) begin
            case (offset)

                // LEDR
                8'h00:  rd_data = {22'b0, LEDR};

                // HEX data
                8'h04:  rd_data = {8'b0, hex_data};

                // SW
                8'h0C:  rd_data = {22'b0, SW};

                default: rd_data = 32'b0;
            endcase
        end

        else begin
            rd_data = 32'b0;
        end

    end

endmodule