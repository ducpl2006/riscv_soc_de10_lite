// ============================================================================
// Module APB4_UART_Slave
// ----------------------------------------------------------------------------
// APB4 UART Peripheral
//
// Architecture:
// APB4_Interconnect
//        |
//        v
// APB4_UART_Slave
//        |
//        v
// UART_Register_IF
//        |
//        v
// UART RX/TX Core
//
// UART Address Region:
// 0x2000_0000 - 0x2000_00FF
//
// Register Map:
// ----------------------------------------------------------------------------
// Offset 0x00 : TX DATA    Write-only
// Offset 0x04 : RX DATA    Read-only
// Offset 0x08 : STATUS     Read-only
//
// STATUS Register:
// bit[0] : tx_full
// bit[1] : rx_empty
// bit[2] : tx_ready
// bit[3] : rx_irq
//
// APB4 behavior:
// ----------------------------------------------------------------------------
// Write:
//   SETUP  : latch address/data, assert uart_write_en
//   ACCESS : PREADY = 1, write completes
//
// Valid read:
//   SETUP       : latch address, assert uart_read_en
//   ACCESS #1   : PREADY = 0, wait for UART_Register_IF
//   ACCESS #2   : PREADY = 1, return PRDATA
//
// Invalid access:
//   ACCESS      : PREADY = 1, PSLVERR = 1
//
// Reset:
// PRESETn = 0 : synchronous reset active
// PRESETn = 1 : normal operation
// ============================================================================
module APB4_UART_Slave #(

    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input                       clk,
    input                       reset,

    // ================================
    // APB4 Slave Interface
    // ================================
    input [ADDR_WIDTH - 1:0]    PADDR,
    input                       PSEL,
    input                       PENABLE,
    input                       PWRITE,

    input [DATA_WIDTH - 1:0]    PWDATA,
    input [DATA_WIDTH/8-1:0]    PSTRB,
    input [2:0]                 PPROT,

    output [DATA_WIDTH - 1:0]   PRDATA,
    output                      PREADY,
    output                      PSLVERR,

    // ================================
    // UART Pins
    // ================================
    input                       rx,
    output                      tx
);

    // ================================
    // UART Register offsets
    // ================================
    localparam TX_DATA_OFFSET = 8'h00;
    localparam RX_DATA_OFFSET = 8'h04;
    localparam STATUS_OFFSET  = 8'h08;

    // ========================================================================
    // Address handling
    // ========================================================================
    // APB uses byte addressing. Clearing PADDR[1:0] identifies the containing
    // 32-bit register.
    //
    // Examples:
    // 0x00, 0x01, 0x02, 0x03 -> register offset 0x00
    // 0x04, 0x05, 0x06, 0x07 -> register offset 0x04
    // ========================================================================
    wire [7:0] reg_offset_now;

    assign reg_offset_now = {PADDR[7:2], 2'b00};

    // ========================================================================
    // Current address permission
    // ========================================================================
    // TX DATA is write-only
    wire write_addr_valid_now;

    assign write_addr_valid_now = (reg_offset_now == TX_DATA_OFFSET);

    // RX DATA and STATUS are read-only
    wire read_addr_valid_now = (reg_offset_now == RX_DATA_OFFSET) || (reg_offset_now == STATUS_OFFSET);

    // ========================================================================
    // APB phase detection
    // ========================================================================
    wire setup_phase;
    wire access_phase;

    assign setup_phase  = PSEL && !PENABLE;
    assign access_phase = PSEL &&  PENABLE;

    // ========================================================================
    // UART_Register_IF signals
    // ========================================================================
    reg [ADDR_WIDTH - 1:0]  uart_wr_addr;
    reg [ADDR_WIDTH - 1:0]  uart_rd_addr;

    reg [DATA_WIDTH - 1:0]  uart_wr_data;
    wire [DATA_WIDTH - 1:0] uart_rd_data;

    reg                     uart_write_en;
    reg                     uart_read_en;

    // Write có độ ưu tiên cao hơn Read khi xử lý với UART (Thiết kế riêng của APB_Slave -> UART)
    wire [ADDR_WIDTH - 1:0] uart_addr;

    assign uart_addr = uart_write_en ? uart_wr_addr : uart_rd_addr;

    // ================================
    // UART REGISTER INTERFACE
    // ================================
    UART_Register_IF uart_if (
        .clk        (clk),
        .reset      (reset),

        .addr       (uart_addr),
        .wr_data    (uart_wr_data),
        .write_en   (uart_write_en),
        .read_en    (uart_read_en),
        .rd_data    (uart_rd_data),

        .rx         (rx),
        .tx         (tx)
    );

    // ========================================================================
    // PSTRB masking
    // ========================================================================
    // This preserves the behavior of apply_wstrb() in AXI_UART_Slave:
    //
    // PSTRB[i] = 1 -> Giữ data của byte đó theo PWDATA
    // PSTRB[i] = 0 -> Thay dữ liệu byte đó bằng 0 (tránh nhiễu dữ liệu)
    //
    // byte_index*8 +:8:
    // + signal[start_bit +: width]
    // + Ví dụ [0 +: 8]: Bắt đầu từ bit 0 -> Lấy lên 8 bit [7:0]
    // ========================================================================
    function automatic [DATA_WIDTH - 1:0] apply_pstrb;

        input [DATA_WIDTH - 1:0] data;
        input [DATA_WIDTH/8-1:0] strb;
        
        integer byte_index;

        begin
            apply_pstrb = {DATA_WIDTH{1'b0}};

            for(byte_index = 0; byte_index < DATA_WIDTH/8; byte_index = byte_index + 1) begin
                if (strb[byte_index]) begin
                    apply_pstrb[byte_index*8 +:8] = data[byte_index*8 +:8];
                end
            end
        end

    endfunction

    // ========================================================================
    // Active APB transfer information
    // ========================================================================
    // APB yêu cầu phải giữ tín hiệu ổn định từ SETUP để tới ACCESS
    // + Tín hiệu active giữ cho giá trị ổn định, tạo wrapper
    // + Giúp ổn định dữ liệu trong quá trình giao tiếp với UART_Register_IF
    // ========================================================================
    reg active_write_reg;       // Lưu trasaction hiện tại là WRITE hay READ
    reg access_valid_reg;       // Trasaction hiện tại có hợp lệ hay không

    // ========================================================================
    // Read pipeline
    // ========================================================================
    reg                     read_pending;
    reg                     read_data_valid;
    reg [DATA_WIDTH - 1:0]  read_data_reg;

    // ========================================================================
    // Sequential request handling
    // + Xử lý WRITE và READ UART
    // ========================================================================
    always @(posedge clk) begin
        
        if (!reset) begin
            // UART Interface
            uart_wr_addr        <= {ADDR_WIDTH{1'b0}};
            uart_rd_addr        <= {ADDR_WIDTH{1'b0}};
            uart_wr_data        <= {DATA_WIDTH{1'b0}};

            uart_write_en       <= 1'b0;
            uart_read_en        <= 1'b0;

            // Active APB Transfer
            active_write_reg    <= 1'b0;
            access_valid_reg    <= 1'b0;

            // Read pipline
            read_pending        <= 1'b0;
            read_data_valid     <= 1'b0;
            read_data_reg       <= {DATA_WIDTH{1'b0}};
        end

        else begin

            // ================================================================
            // Default pulse values
            // + Cả hai tín hiệu đều kích hoạt trong 1 cycle
            // ================================================================
            uart_write_en   <= 1'b0;
            uart_read_en    <= 1'b0;

            // ================================================================
            // APB SETUP phase
            // - Tại cạnh lên khi kết thúc trạng thái SETUP
            // + address/control/data được giữ nguyên
            // + UART bắt đầu hoạt động
            // + Chu kì tiếp theo tới ACCESS
            // ================================================================
            if (setup_phase) begin
                active_write_reg <= PWRITE;     // Xác định trạng thái APB đang WRITE hay READ

                // ===============================
                // APB yêu cầu WRITE
                // ===============================
                if (PWRITE) begin
                    access_valid_reg    <= write_addr_valid_now;

                    uart_wr_addr        <= PADDR;
                    uart_wr_data        <= apply_pstrb(PWDATA, PSTRB);

                    // UART_Register_IF sẽ lấy những giá trị này khi hoàn thành ACCESS
                    if (write_addr_valid_now) begin
                        uart_write_en   <= 1'b1;
                    end

                    // Thực hiện một thao tác write UART, không read
                    read_pending    <= 1'b0;
                    read_data_valid <= 1'b0;
                end

                // ===============================
                // APB yêu cầu READ
                // ===============================
                else begin
                    access_valid_reg    <= read_addr_valid_now;

                    uart_rd_addr        <= PADDR;

                    if (read_addr_valid_now) begin
                        // Bắt đầu READ
                        uart_read_en    <= 1'b1;
                        read_pending    <= 1'b1;
                    end
                    else begin
                        // Trả kết quả đọc lỗi về PSLVERR và UART không read dữ liệu
                        read_pending    <= 1'b0;
                    end

                    read_data_valid <= 1'b0;
                end
            end

            // ================================================================
            // Chu kì đầu tiên của ACCESS khi yêu cầu read hợp lệ (valid)
            // + PREADY giữ bằng 0 trong suốt chu kì này (Chưa đọc xong)
            // + UART đã có 1 chu kì sau khi read_en được kích hoạt
            // ================================================================
            if (access_phase && !active_write_reg && access_valid_reg && read_pending) begin
                read_data_reg   <= uart_rd_data;
                read_pending    <= 1'b0;
                read_data_valid <= 1'b1;
            end

            // ================================================================
            // Transfer READ hoàn thành
            // - Tại cycle thứ 2 của ACCESS:
            // + read_data_valid = 1 --> PREADY = 1
            // + Clear valid flag tại cạnh pulse tiếp theo
            // ================================================================
            if (access_phase && PREADY && !active_write_reg && access_valid_reg) begin
                read_data_valid <= 1'b0;
            end
        end

    end

    // ========================================================================
    // APB PREADY generation
    // ========================================================================
    // Outside ACCESS:
    //   PREADY = 0. Its value is not used by APB.
    //
    // Write:
    //   Always completes in the first ACCESS cycle.
    //
    // Invalid read:
    //   Completes immediately in the first ACCESS cycle with PSLVERR.
    //
    // Valid read:
    //   First ACCESS  : read_data_valid = 0 -> PREADY = 0
    //   Second ACCESS : read_data_valid = 1 -> PREADY = 1
    // ========================================================================
    assign PREADY = !access_phase       ? 1'b0 :
                     active_write_reg   ? 1'b1 :
                    !access_valid_reg   ? 1'b1 :    // Nếu access bị lỗi, ngắt APB tránh bị treo hệ thống
                     read_data_valid;
    
    // ========================================================================
    // APB read data
    // ========================================================================
    assign PRDATA = read_data_valid ? read_data_reg : {DATA_WIDTH{1'b0}};

    // ========================================================================
    // APB slave error
    // ========================================================================
    // PSLVERR is valid only when the transfer completes:
    //
    // PSEL    = 1
    // PENABLE = 1
    // PREADY  = 1
    //
    // Errors:
    // - Write to RX DATA or STATUS
    // - Read from TX DATA
    // - Access to an undefined offset
    // ========================================================================
    assign PSLVERR = access_phase && PREADY && !access_valid_reg;

endmodule