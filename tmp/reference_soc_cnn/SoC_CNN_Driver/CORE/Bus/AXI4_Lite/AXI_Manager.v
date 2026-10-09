// ======================================================
// Module AXI Manager
// + Bộ Manager của AXI
// + Bản Lite
// 
// ------------------------------------------------------
// Chức năng
// + Nhận request đơn giản từ CPU: addr, data, we, re
// --> Chuyển thành tín hiệu AXI: AW, W, B, AR, R
//
// ------------------------------------------------------
// Các trạng thái channels của AXI hoạt động theo FSM
// ======================================================

module AXI_Manager #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)
(
    input clk,
    input reset,

    // =============== CPU Interface ===============
    input [ADDR_WIDTH - 1:0] mem_addr,
    input [DATA_WIDTH - 1:0] mem_wdata,
    input [DATA_WIDTH/8 - 1:0] mem_wstrb,        // Byte enable từ CPU (cho SB/SH/SW)
    input mem_we,
    input mem_re,
    output reg [DATA_WIDTH - 1:0] mem_rdata,
    output reg mem_ready,                       // Cờ báo khi hoàn tất xong một transaction

    // =============== AXI Write Address ===============
    output reg [ADDR_WIDTH - 1:0] axi_awaddr,
    output reg axi_awvalid,
    input axi_awready,

    // =============== AXI Write Data ===============
    output reg [DATA_WIDTH - 1:0] axi_wdata,
    output reg [DATA_WIDTH/8 - 1:0] axi_wstrb,    // wstrb cho biết byte nào wdata là hợp lệ và được ghi (32/8 = 4 bytes)
    output reg axi_wvalid,
    input axi_wready,

    // =============== AXI Write Response ===============
    input [1:0] axi_bresp,
    input axi_bvalid,
    output reg axi_bready,

    // =============== AXI Read Address ===============
    output reg [ADDR_WIDTH - 1:0] axi_araddr,
    output reg axi_arvalid,
    input axi_arready,

    // =============== AXI Read Data ===============
    input [DATA_WIDTH - 1:0] axi_rdata,
    input [1:0] axi_rresp,
    input axi_rvalid,
    output reg axi_rready
);

    // =============== FSM STATE ===============
    localparam [2:0] IDLE         = 3'b000;
    localparam [2:0] WRITE_CHAN   = 3'b001;     // Write Channel Race Condition
    localparam [2:0] WRITE_RESP   = 3'b010;
    localparam [2:0] READ_ADDR    = 3'b011;
    localparam [2:0] READ_DATA    = 3'b100;
    localparam [2:0] POST_WRITE   = 3'b101;     // 1-cycle cooldown sau WRITE: tránh re-trigger khi CPU chưa kịp hạ mem_we
    localparam [2:0] POST_READ    = 3'b110;     // 1-cycle cooldown sau READ: tránh re-trigger khi CPU chưa kịp hạ mem_re

    reg [2:0] state;

    // =============== MAIN FSM ===============
    reg aw_done;        // Báo AW channel đã handshake xong
    reg w_done;         // Báo W channel đã handshake xong
    always @(posedge clk) begin
        
        if (!reset) begin
            state       <= IDLE;

            axi_awvalid <= 0;
            axi_wvalid  <= 0;
            axi_bready  <= 0;
            axi_arvalid <= 0;
            axi_rready  <= 0;

            axi_wstrb   <= 0;

            aw_done     <= 0;
            w_done      <= 0;

            mem_ready   <= 0;
            mem_rdata   <= 0;
        end

        // DEFAULT
        else begin
            mem_ready   <= 0;

            case (state)

                // =============== IDLE ===============
                IDLE: begin
                    // WRITE ADDRESS
                    if (mem_we) begin
                        // Setup write
                        axi_awaddr  <= mem_addr;
                        axi_awvalid <= 1;

                        axi_wdata   <= mem_wdata;
                        axi_wvalid  <= 1;

                        axi_wstrb   <= mem_wstrb;       // Byte enable từ CPU (SB/SH/SW)

                        aw_done     <= 0;
                        w_done      <= 0;

                        state       <= WRITE_CHAN;
                    end

                    // READ ADDRESS
                    else if (mem_re) begin
                        // Setup read
                        axi_araddr  <= mem_addr;
                        axi_arvalid <= 1;

                        state       <= READ_ADDR;
                    end
                end

                // =============== WRITE ADDRESS + WRITE DATA ===============
                /*
                    WRITE_CHAN: Xử lý AW và W song song trong cùng 1 chu kỳ
                    + Vì trong AXI thì AW và W là 2 channel độc lập, handshake có thể xảy ra ở cùng 1 chu kỳ hoặc khác chu kỳ
                    + 2 tín hiệu done: chỉ khi nào AW và W handshake xong thì mới chuyển sang Resp
                */
                WRITE_CHAN: begin
                    // AW Handshake
                    if (axi_awvalid && axi_awready) begin
                        axi_awvalid <= 0;
                        aw_done     <= 1;
                    end

                    // W Handshake
                    if (axi_wvalid && axi_wready) begin
                        axi_wvalid  <= 0;
                        w_done      <= 1;
                    end

                    if ((aw_done || (axi_awvalid && axi_awready)) && (w_done || (axi_wvalid && axi_wready))) begin
                        axi_bready  <= 1;
                        state       <= WRITE_RESP;      // Cờ báo Master sẵn sàng nhận dữ liệu gửi từ Slave
                    end
                end

                // =============== WRITE RESPONSE ===============
                WRITE_RESP: begin
                    if (axi_bvalid && axi_bready) begin
                        axi_bready  <= 0;

                        mem_ready   <= 1;
                        state       <= POST_WRITE;
                    end
                end

                // =============== READ ADDR ===============
                READ_ADDR: begin
                    if (axi_arready && axi_arvalid) begin
                        axi_arvalid <= 0;

                        axi_rready  <= 1;           // Master báo đã sẵn sàng nhận dữ liệu từ Slave gửi về
                        state       <= READ_DATA;
                    end
                end

                // =============== READ DATA ===============
                READ_DATA: begin
                    if (axi_rvalid) begin
                        mem_rdata   <= axi_rdata;

                        axi_rready  <= 0;
                        mem_ready   <= 1;

                        state       <= POST_READ;
                    end
                end

                // =============== POST WRITE (cooldown 1 cycle) ===============
                // Tránh re-trigger duplicate write khi mem_we còn HIGH do CPU pipeline chưa kịp update EX/MEM
                POST_WRITE: begin
                    state <= IDLE;
                end

                // =============== POST READ (cooldown 1 cycle) ===============
                // Tránh re-trigger duplicate read (đặc biệt nguy hiểm với UART RX FIFO pop 2 lần)
                POST_READ: begin
                    state <= IDLE;
                end

            endcase
        end

    end

endmodule