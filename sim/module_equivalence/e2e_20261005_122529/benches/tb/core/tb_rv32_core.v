`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench tích hợp cho rv32_core pipeline 5 tầng
 *
 * Đặc tả môi trường mô phỏng:
 * - Hai mô hình nhớ Harvard độc lập. Instruction memory chứa word 32 bit;
 *   data memory chứa byte để mô hình hóa little-endian và byte strobe thật.
 * - Độ trễ nhớ xác định từ địa chỉ. Instruction chụp địa chỉ tại req && gnt,
 *   trả rvalid độc lập sau thời gian chờ. Data giữ ready thấp tới khi hoàn tất;
 *   core phải giữ nguyên request và payload dữ liệu trong thời gian chờ này.
 * - STRESS_SEED khác 0 thay lịch cố định bằng fetch hai request, grant/response
 *   thay đổi và data chờ 0..31 chu kỳ. Seed tái lập được, không sửa chương trình.
 * - Chương trình RV32I được mã hóa trực tiếp bằng sáu hàm R/I/S/B/U/J;
 *   không phụ thuộc assembler, linker hay toolchain bên ngoài.
 *
 * Phạm vi tự kiểm tra:
 * - Forward EX/MEM và MEM/WB, load-use stall, phụ thuộc store-data.
 * - Branch taken/not-taken và loại bỏ lệnh sai đường; JAL/JALR, link và flush.
 * - LUI/AUIPC; đầy đủ các lớp ALU OP và OP-IMM của RV32I.
 * - LB/LBU/LH/LHU/LW, SB/SH/SW, mọi byte lane và hai halfword lane.
 * - FENCE như NOP hợp lệ; kết thúc chính xác bằng EBREAK, cause breakpoint=3.
 * - Signature trong data memory, trace retire, không retire trùng PC, không
 *   retire EBREAK hay bất kỳ lệnh sai đường nào.
 *
 * Quy tắc thất bại:
 * - Mọi sai khác dùng $fatal với PC/tín hiệu liên quan; watchdog ngăn treo.
 * - Testbench không truy cập để sửa trạng thái nội bộ DUT và không che lỗi RTL.
 */
module tb_rv32_core #(
    // 0 giữ lịch chờ baseline; khác 0 bật fetch hai request và wait-state giả ngẫu nhiên.
    parameter integer STRESS_SEED = 0
);

    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_BYTES = 1024;
    localparam [31:0] DATA_BASE   = 32'h00000100;
    localparam [31:0] SIG_BASE    = 32'h00000200;
    localparam [31:0] EBREAK_INSN = 32'h00100073;

    localparam [6:0]
        OPC_LOAD     = 7'b0000011,
        OPC_MISC_MEM = 7'b0001111,
        OPC_OP_IMM   = 7'b0010011,
        OPC_AUIPC    = 7'b0010111,
        OPC_STORE    = 7'b0100011,
        OPC_OP       = 7'b0110011,
        OPC_LUI      = 7'b0110111,
        OPC_BRANCH   = 7'b1100011,
        OPC_JALR     = 7'b1100111,
        OPC_JAL      = 7'b1101111;

    reg clk;
    reg rst;

    wire        imem_req;
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_gnt;
    wire        imem_rvalid;
    wire        imem_err;

    wire        dmem_req;
    wire        dmem_we;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;
    wire        dmem_err;

    wire        halted;
    wire        trap_valid;
    wire [4:0]  trap_cause;
    wire [31:0] trap_pc;
    wire [31:0] trap_instr;

    wire        retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    wire        retire_rd_we;
    wire [4:0]  retire_rd_addr;
    wire [31:0] retire_rd_data;
    wire [31:0] debug_fetch_pc;

    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [7:0]  dmem [0:DMEM_BYTES-1];
    reg [31:0] expected_sig [0:36];
    reg        retired_seen [0:IMEM_WORDS-1];

    reg        imem_active;
    reg [2:0]  imem_wait_count;
    reg [31:0] imem_addr_hold;
    reg [31:0] imem_rdata_hold;

    reg        dmem_active;
    reg [4:0]  dmem_wait_count;
    reg [31:0] dmem_addr_hold;
    reg        dmem_we_hold;
    reg [31:0] dmem_wdata_hold;
    reg [3:0]  dmem_wstrb_hold;
    reg [31:0] dmem_rdata_hold;

    integer program_words;
    integer expected_retire_count;
    integer retire_count;
    integer imem_transaction_count;
    integer dmem_transaction_count;
    integer imem_wait_cycles;
    integer dmem_wait_cycles;
    integer init_index;
    integer wrong_index;
    integer retire_index;

    integer idx_branch_taken;
    integer idx_branch_target;
    integer idx_jal;
    integer idx_jal_target;
    integer idx_jalr_auipc;
    integer idx_jalr_addi;
    integer idx_jalr;
    integer idx_jalr_target;
    integer idx_auipc_value;

    reg [31:0] wrong_path_pc [0:5];
    reg [31:0] pc_forward_exmem;
    reg [31:0] pc_forward_wb;
    reg [31:0] pc_load_use;
    reg [31:0] pc_branch_taken;
    reg [31:0] pc_branch_not_taken;
    reg [31:0] pc_jal;
    reg [31:0] pc_jalr;
    reg [31:0] pc_lui;
    reg [31:0] pc_auipc;
    reg [31:0] pc_fence;
    reg [31:0] pc_ebreak;

    reg        cov_forward_exmem;
    reg        cov_forward_wb;
    reg        cov_load_use;
    reg        cov_branch_taken;
    reg        cov_branch_not_taken;
    reg        cov_jal;
    reg        cov_jalr;
    reg        cov_lui;
    reg        cov_auipc;
    reg        cov_fence;
    reg [9:0]  cov_op;
    reg [8:0]  cov_op_imm;
    reg [4:0]  cov_load;
    reg [2:0]  cov_store;
    reg [6:0]  cov_wstrb;
    reg        cov_imem_stall;
    reg        cov_dmem_stall;

    rv32_core #(
        .RESET_VECTOR (32'h00000000)
    ) dut (
        .clk_i            (clk),
        .rst_i            (rst),
        .imem_req_o       (imem_req),
        .imem_addr_o      (imem_addr),
        .imem_gnt_i       (imem_gnt),
        .imem_rvalid_i    (imem_rvalid),
        .imem_rdata_i     (imem_rdata),
        .imem_err_i       (imem_err),
        .dmem_req_o       (dmem_req),
        .dmem_we_o        (dmem_we),
        .dmem_addr_o      (dmem_addr),
        .dmem_wdata_o     (dmem_wdata),
        .dmem_wstrb_o     (dmem_wstrb),
        .dmem_rdata_i     (dmem_rdata),
        .dmem_ready_i     (dmem_ready),
        .dmem_err_i       (dmem_err),
        .halted_o         (halted),
        .trap_valid_o     (trap_valid),
        .trap_cause_o     (trap_cause),
        .trap_pc_o        (trap_pc),
        .trap_instr_o     (trap_instr),
        .retire_valid_o   (retire_valid),
        .retire_pc_o      (retire_pc),
        .retire_instr_o   (retire_instr),
        .retire_rd_we_o   (retire_rd_we),
        .retire_rd_addr_o (retire_rd_addr),
        .retire_rd_data_o (retire_rd_data),
        .debug_fetch_pc_o (debug_fetch_pc)
    );

    // ---------------------------------------------------------------------
    // Bộ mã hóa lệnh độc lập với decoder của DUT.
    // ---------------------------------------------------------------------
    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] enc_i;
        input [11:0] immediate;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            enc_i = {immediate, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] enc_s;
        input [11:0] immediate;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [6:0]  opcode;
        begin
            enc_s = {
                immediate[11:5], rs2, rs1, funct3,
                immediate[4:0], opcode
            };
        end
    endfunction

    function [31:0] enc_b;
        input [12:0] immediate;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [6:0]  opcode;
        begin
            enc_b = {
                immediate[12], immediate[10:5], rs2, rs1, funct3,
                immediate[4:1], immediate[11], opcode
            };
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] immediate_upper;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            enc_u = {immediate_upper, rd, opcode};
        end
    endfunction

    function [31:0] enc_j;
        input [20:0] immediate;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            enc_j = {
                immediate[20], immediate[10:1], immediate[11],
                immediate[19:12], rd, opcode
            };
        end
    endfunction

    task emit;
        input [31:0] instruction;
        begin
            if (program_words >= IMEM_WORDS)
                $fatal(1, "Program exceeds instruction memory");
            imem[program_words] = instruction;
            program_words = program_words + 1;
        end
    endtask

    // ---------------------------------------------------------------------
    // Hàm đọc memory và lịch wait-state xác định.
    // ---------------------------------------------------------------------
    function [31:0] read_imem_word;
        input [31:0] byte_address;
        begin
            if ((byte_address[1:0] == 2'b00) &&
                (byte_address[31:2] < IMEM_WORDS)) begin
                read_imem_word = imem[byte_address[31:2]];
            end
            else begin
                read_imem_word = 32'b0;
            end
        end
    endfunction

    function [31:0] read_dmem_word;
        input [31:0] byte_address;
        begin
            if (byte_address <= (DMEM_BYTES - 4)) begin
                read_dmem_word = {
                    dmem[byte_address + 32'd3],
                    dmem[byte_address + 32'd2],
                    dmem[byte_address + 32'd1],
                    dmem[byte_address]
                };
            end
            else begin
                read_dmem_word = 32'b0;
            end
        end
    endfunction

    function [2:0] imem_delay;
        input [31:0] byte_address;
        begin
            case (byte_address[3:2])
                2'b00: imem_delay = 3'd1;
                2'b01: imem_delay = 3'd3;
                2'b10: imem_delay = 3'd2;
                default: imem_delay = 3'd1;
            endcase
        end
    endfunction

    function [2:0] dmem_delay;
        input [31:0] byte_address;
        begin
            case (byte_address[3:2])
                2'b00: dmem_delay = 3'd2;
                2'b01: dmem_delay = 3'd1;
                2'b10: dmem_delay = 3'd3;
                default: dmem_delay = 3'd2;
            endcase
        end
    endfunction

    // Mô hình stress độc lập với trạng thái nội bộ CPU: tối đa hai request,
    // grant có thể chờ, response đúng thứ tự và không sớm hơn cạnh sau grant.
    reg [31:0] stress_rng;
    integer stress_cycle, stress_count;
    integer stress_two_pending, stress_overlap;
    reg fetch_held;
    reg [31:0] fetch_held_addr;
    reg [31:0] stress_data [0:1];
    integer stress_due [0:1];
    wire stress_pop = STRESS_SEED != 0 && stress_count > 0 &&
                      stress_cycle >= stress_due[0];
    wire stress_grant = stress_count < 2 && (stress_rng[0] || stress_rng[1]);
    wire stress_push = imem_req && imem_gnt;
    wire [31:0] rng_step_a = stress_rng ^ (stress_rng << 13);
    wire [31:0] rng_step_b = rng_step_a ^ (rng_step_a >> 17);
    wire [31:0] rng_next = rng_step_b ^ (rng_step_b << 5);

    always @(posedge clk) begin
        if (rst) begin
            stress_rng <= STRESS_SEED == 0 ? 32'd1 : STRESS_SEED;
            stress_cycle <= 0;
            stress_count <= 0;
            stress_two_pending <= 0;
            stress_overlap <= 0;
            stress_due[0] <= 0;
            stress_due[1] <= 0;
            stress_data[0] <= 0;
            stress_data[1] <= 0;
        end
        else if (STRESS_SEED != 0) begin
            stress_cycle <= stress_cycle + 1;
            stress_rng <= rng_next;
            if (stress_count == 2) stress_two_pending <= stress_two_pending + 1;
            if (stress_push && stress_pop) stress_overlap <= stress_overlap + 1;
            if (stress_pop) begin
                stress_data[0] <= stress_data[1];
                stress_due[0] <= stress_due[1];
            end
            if (stress_push) begin
                imem_transaction_count = imem_transaction_count + 1;
                if (imem_addr[1:0] !== 0 || imem_addr[31:2] >= IMEM_WORDS)
                    $fatal(1, "Stress fetch address %h", imem_addr);
                stress_data[stress_count - (stress_pop ? 1 : 0)] <= read_imem_word(imem_addr);
                stress_due[stress_count - (stress_pop ? 1 : 0)] <=
                    stress_cycle + 1 + (stress_rng[2] ? 0 : stress_rng[5:3]);
            end
            case ({stress_push, stress_pop})
                2'b10: stress_count <= stress_count + 1;
                2'b01: stress_count <= stress_count - 1;
                default: begin end
            endcase
        end
    end

    assign imem_gnt = STRESS_SEED != 0 ? stress_grant : !imem_active;
    assign imem_rvalid = STRESS_SEED != 0 ? stress_pop :
                        imem_active && (imem_wait_count == 3'd0);
    assign imem_rdata = STRESS_SEED != 0 ? stress_data[0] : imem_rdata_hold;
    assign imem_err   = 1'b0;

    assign dmem_ready = dmem_active && (dmem_wait_count == 3'd0);
    assign dmem_rdata = dmem_rdata_hold;
    assign dmem_err   = 1'b0;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Baseline instruction memory: một transaction tại một thời điểm.
    always @(posedge clk) begin
        if (rst) begin
            imem_active     <= 1'b0;
            imem_wait_count <= 3'b0;
            imem_addr_hold  <= 32'b0;
            imem_rdata_hold <= 32'b0;
        end
        else if (STRESS_SEED == 0) begin
            if (!imem_active) begin
                if (imem_req && imem_gnt) begin
                    if (imem_addr[1:0] !== 2'b00)
                        $fatal(1, "IMEM address is not word aligned: %h",
                               imem_addr);
                    if (imem_addr[31:2] >= IMEM_WORDS)
                        $fatal(1, "IMEM address out of range: %h", imem_addr);
                    imem_active     <= 1'b1;
                    imem_wait_count <= imem_delay(imem_addr);
                    imem_addr_hold  <= imem_addr;
                    imem_rdata_hold <= read_imem_word(imem_addr);
                    imem_transaction_count = imem_transaction_count + 1;
                end
            end
            else if (imem_wait_count != 3'd0) begin
                imem_wait_count <= imem_wait_count - 3'd1;
            end
            else begin
                // rvalid đang ở mức 1; response hoàn tất tại cạnh này.
                imem_active <= 1'b0;
            end
        end
    end

    // Data memory: commit byte ghi duy nhất tại cạnh req && ready.
    always @(posedge clk) begin
        if (rst) begin
            dmem_active      <= 1'b0;
            dmem_wait_count  <= 3'b0;
            dmem_addr_hold   <= 32'b0;
            dmem_we_hold     <= 1'b0;
            dmem_wdata_hold  <= 32'b0;
            dmem_wstrb_hold  <= 4'b0;
            dmem_rdata_hold  <= 32'b0;
        end
        else begin
            if (!dmem_active) begin
                if (dmem_req) begin
                    if (dmem_addr[1:0] !== 2'b00)
                        $fatal(1, "DMEM address is not word aligned: %h",
                               dmem_addr);
                    if (dmem_addr > (DMEM_BYTES - 4))
                        $fatal(1, "DMEM address out of range: %h", dmem_addr);
                    if (dmem_we && (dmem_wstrb == 4'b0000))
                        $fatal(1, "Store request has zero byte strobe at %h",
                               dmem_addr);
                    if (!dmem_we && (dmem_wstrb != 4'b0000))
                        $fatal(1, "Load request has nonzero strobe at %h",
                               dmem_addr);

                    dmem_active      <= 1'b1;
                    dmem_wait_count  <= STRESS_SEED != 0 ? stress_rng[12:8] : dmem_delay(dmem_addr);
                    dmem_addr_hold   <= dmem_addr;
                    dmem_we_hold     <= dmem_we;
                    dmem_wdata_hold  <= dmem_wdata;
                    dmem_wstrb_hold  <= dmem_wstrb;
                    dmem_rdata_hold  <= dmem_we
                                      ? 32'b0
                                      : read_dmem_word(dmem_addr);
                    dmem_transaction_count = dmem_transaction_count + 1;
                end
            end
            else if (dmem_wait_count != 3'd0) begin
                dmem_wait_count <= dmem_wait_count - 3'd1;
            end
            else begin
                if (dmem_we_hold) begin
                    if (dmem_wstrb_hold[0])
                        dmem[dmem_addr_hold] <= dmem_wdata_hold[7:0];
                    if (dmem_wstrb_hold[1])
                        dmem[dmem_addr_hold + 32'd1]
                            <= dmem_wdata_hold[15:8];
                    if (dmem_wstrb_hold[2])
                        dmem[dmem_addr_hold + 32'd2]
                            <= dmem_wdata_hold[23:16];
                    if (dmem_wstrb_hold[3])
                        dmem[dmem_addr_hold + 32'd3]
                            <= dmem_wdata_hold[31:24];

                    case (dmem_wstrb_hold)
                        4'b0001: cov_wstrb[0] = 1'b1;
                        4'b0010: cov_wstrb[1] = 1'b1;
                        4'b0100: cov_wstrb[2] = 1'b1;
                        4'b1000: cov_wstrb[3] = 1'b1;
                        4'b0011: cov_wstrb[4] = 1'b1;
                        4'b1100: cov_wstrb[5] = 1'b1;
                        4'b1111: cov_wstrb[6] = 1'b1;
                        default:
                            $fatal(1, "Unexpected store strobe: %b",
                                   dmem_wstrb_hold);
                    endcase
                end
                dmem_active <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Assertion protocol: request và payload phải giữ ổn định tới ready.
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            fetch_held <= 0;
            fetch_held_addr <= 0;
        end
        else begin
            if (fetch_held && (imem_req !== 1'b1 || imem_addr !== fetch_held_addr))
                $fatal(1, "IMEM request/address changed before grant");
            fetch_held <= imem_req && !imem_gnt;
            fetch_held_addr <= imem_addr;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if ((^imem_req) === 1'bx)
                $fatal(1, "IMEM req contains X/Z");
            if ((^dmem_req) === 1'bx)
                $fatal(1, "DMEM req contains X/Z");

            if (imem_req && !imem_gnt) begin
                cov_imem_stall = 1'b1;
                imem_wait_cycles = imem_wait_cycles + 1;
            end
            if (dmem_req && !dmem_ready) begin
                cov_dmem_stall = 1'b1;
                dmem_wait_cycles = dmem_wait_cycles + 1;
            end

            if (dmem_active) begin
                if (dmem_req !== 1'b1)
                    $fatal(1, "DMEM request dropped before ready; held=%h",
                           dmem_addr_hold);
                if ((dmem_addr  !== dmem_addr_hold)  ||
                    (dmem_we    !== dmem_we_hold)    ||
                    (dmem_wdata !== dmem_wdata_hold) ||
                    (dmem_wstrb !== dmem_wstrb_hold)) begin
                    $fatal(1,
                           "DMEM payload changed while stalled: held addr/we/data/strb=%h/%b/%h/%b now=%h/%b/%h/%b",
                           dmem_addr_hold, dmem_we_hold,
                           dmem_wdata_hold, dmem_wstrb_hold,
                           dmem_addr, dmem_we, dmem_wdata, dmem_wstrb);
                end
            end

            if (dmem_we && !dmem_req)
                $fatal(1, "dmem_we asserted without dmem_req");
        end
    end

    // ---------------------------------------------------------------------
    // Scoreboard retire và coverage chức năng.
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && retire_valid) begin
            if ((retire_pc[1:0] !== 2'b00) ||
                (retire_pc[31:2] >= IMEM_WORDS)) begin
                $fatal(1, "Invalid retire PC: %h", retire_pc);
            end
            if (retire_instr !== imem[retire_pc[31:2]]) begin
                $fatal(1,
                       "Retire instruction mismatch at PC=%h got=%h expected=%h",
                       retire_pc, retire_instr, imem[retire_pc[31:2]]);
            end
            if (retire_instr === EBREAK_INSN)
                $fatal(1, "EBREAK incorrectly retired as successful at PC=%h",
                       retire_pc);

            retire_index = retire_pc[31:2];
            if (retired_seen[retire_index])
                $fatal(1, "Instruction retired twice at PC=%h", retire_pc);
            retired_seen[retire_index] = 1'b1;
            retire_count = retire_count + 1;

            for (wrong_index = 0; wrong_index < 6;
                 wrong_index = wrong_index + 1) begin
                if (retire_pc === wrong_path_pc[wrong_index])
                    $fatal(1, "Wrong-path instruction retired at PC=%h",
                           retire_pc);
            end

            // Điểm kiểm tra trực tiếp cho từng loại hazard/control quan trọng.
            if (retire_pc == pc_forward_exmem) begin
                if (!retire_rd_we || (retire_rd_addr != 5'd2) ||
                    (retire_rd_data != 32'd12))
                    $fatal(1, "EX/MEM forwarding failed at PC=%h data=%h",
                           retire_pc, retire_rd_data);
                cov_forward_exmem = 1'b1;
            end
            if (retire_pc == pc_forward_wb) begin
                if (!retire_rd_we || (retire_rd_addr != 5'd5) ||
                    (retire_rd_data != 32'd14))
                    $fatal(1, "MEM/WB forwarding failed at PC=%h data=%h",
                           retire_pc, retire_rd_data);
                cov_forward_wb = 1'b1;
            end
            if (retire_pc == pc_load_use) begin
                if (!retire_rd_we || (retire_rd_addr != 5'd12) ||
                    (retire_rd_data != 32'd2))
                    $fatal(1, "Load-use result failed at PC=%h data=%h",
                           retire_pc, retire_rd_data);
                cov_load_use = 1'b1;
            end
            if (retire_pc == pc_branch_taken)
                cov_branch_taken = 1'b1;
            if (retire_pc == pc_branch_not_taken)
                cov_branch_not_taken = 1'b1;
            if (retire_pc == pc_jal) begin
                if (!retire_rd_we || (retire_rd_addr != 5'd15) ||
                    (retire_rd_data != (pc_jal + 32'd4)))
                    $fatal(1, "JAL link failed at PC=%h data=%h",
                           retire_pc, retire_rd_data);
                cov_jal = 1'b1;
            end
            if (retire_pc == pc_jalr) begin
                if (!retire_rd_we || (retire_rd_addr != 5'd17) ||
                    (retire_rd_data != (pc_jalr + 32'd4)))
                    $fatal(1, "JALR link failed at PC=%h data=%h",
                           retire_pc, retire_rd_data);
                cov_jalr = 1'b1;
            end
            if (retire_pc == pc_lui) begin
                if (!retire_rd_we || (retire_rd_data != 32'h12345000))
                    $fatal(1, "LUI result failed: %h", retire_rd_data);
                cov_lui = 1'b1;
            end
            if (retire_pc == pc_auipc) begin
                if (!retire_rd_we ||
                    (retire_rd_data != (pc_auipc + 32'h00001000)))
                    $fatal(1, "AUIPC result failed: %h", retire_rd_data);
                cov_auipc = 1'b1;
            end
            if (retire_pc == pc_fence) begin
                if (retire_rd_we)
                    $fatal(1, "FENCE unexpectedly writes a register");
                cov_fence = 1'b1;
            end

            case (retire_instr[6:0])
                OPC_OP: begin
                    case ({retire_instr[31:25], retire_instr[14:12]})
                        10'b0000000_000: cov_op[0] = 1'b1; // ADD
                        10'b0100000_000: cov_op[1] = 1'b1; // SUB
                        10'b0000000_001: cov_op[2] = 1'b1; // SLL
                        10'b0000000_010: cov_op[3] = 1'b1; // SLT
                        10'b0000000_011: cov_op[4] = 1'b1; // SLTU
                        10'b0000000_100: cov_op[5] = 1'b1; // XOR
                        10'b0000000_101: cov_op[6] = 1'b1; // SRL
                        10'b0100000_101: cov_op[7] = 1'b1; // SRA
                        10'b0000000_110: cov_op[8] = 1'b1; // OR
                        10'b0000000_111: cov_op[9] = 1'b1; // AND
                        default:
                            $fatal(1, "Unexpected retired OP encoding %h",
                                   retire_instr);
                    endcase
                end

                OPC_OP_IMM: begin
                    case (retire_instr[14:12])
                        3'b000: cov_op_imm[0] = 1'b1; // ADDI
                        3'b001: cov_op_imm[1] = 1'b1; // SLLI
                        3'b010: cov_op_imm[2] = 1'b1; // SLTI
                        3'b011: cov_op_imm[3] = 1'b1; // SLTIU
                        3'b100: cov_op_imm[4] = 1'b1; // XORI
                        3'b101: begin
                            if (retire_instr[30])
                                cov_op_imm[6] = 1'b1; // SRAI
                            else
                                cov_op_imm[5] = 1'b1; // SRLI
                        end
                        3'b110: cov_op_imm[7] = 1'b1; // ORI
                        3'b111: cov_op_imm[8] = 1'b1; // ANDI
                        default:
                            $fatal(1, "Unexpected retired OP-IMM %h",
                                   retire_instr);
                    endcase
                end

                OPC_LOAD: begin
                    case (retire_instr[14:12])
                        3'b000: cov_load[0] = 1'b1; // LB
                        3'b001: cov_load[1] = 1'b1; // LH
                        3'b010: cov_load[2] = 1'b1; // LW
                        3'b100: cov_load[3] = 1'b1; // LBU
                        3'b101: cov_load[4] = 1'b1; // LHU
                        default:
                            $fatal(1, "Unexpected retired LOAD %h",
                                   retire_instr);
                    endcase
                end

                OPC_STORE: begin
                    case (retire_instr[14:12])
                        3'b000: cov_store[0] = 1'b1; // SB
                        3'b001: cov_store[1] = 1'b1; // SH
                        3'b010: cov_store[2] = 1'b1; // SW
                        default:
                            $fatal(1, "Unexpected retired STORE %h",
                                   retire_instr);
                    endcase
                end
            endcase
        end
    end

    task verify_signature;
        integer signature_index;
        reg [31:0] observed;
        begin
            for (signature_index = 0; signature_index <= 36;
                 signature_index = signature_index + 1) begin
                observed = read_dmem_word(
                    SIG_BASE + (signature_index * 4)
                );
                if (observed !== expected_sig[signature_index]) begin
                    $fatal(1,
                           "Signature[%0d] mismatch at %h: got=%h expected=%h",
                           signature_index,
                           SIG_BASE + (signature_index * 4),
                           observed, expected_sig[signature_index]);
                end
            end

            if (read_dmem_word(SIG_BASE + 32'd160) !== 32'b0)
                $fatal(1, "Taken-branch wrong-path store was not flushed");
            if (read_dmem_word(SIG_BASE + 32'd164) !== 32'b0)
                $fatal(1, "JAL wrong-path store was not flushed");
            if (read_dmem_word(SIG_BASE + 32'd168) !== 32'b0)
                $fatal(1, "JALR wrong-path store was not flushed");
        end
    endtask

    // ---------------------------------------------------------------------
    // Tạo chương trình và dữ liệu tham chiếu.
    // ---------------------------------------------------------------------
    initial begin
        rst = 1'b1;

        imem_active = 1'b0;
        imem_wait_count = 3'b0;
        imem_addr_hold = 32'b0;
        imem_rdata_hold = 32'b0;
        dmem_active = 1'b0;
        dmem_wait_count = 3'b0;
        dmem_addr_hold = 32'b0;
        dmem_we_hold = 1'b0;
        dmem_wdata_hold = 32'b0;
        dmem_wstrb_hold = 4'b0;
        dmem_rdata_hold = 32'b0;

        program_words = 0;
        retire_count = 0;
        imem_transaction_count = 0;
        dmem_transaction_count = 0;
        imem_wait_cycles = 0;
        dmem_wait_cycles = 0;

        cov_forward_exmem = 1'b0;
        cov_forward_wb = 1'b0;
        cov_load_use = 1'b0;
        cov_branch_taken = 1'b0;
        cov_branch_not_taken = 1'b0;
        cov_jal = 1'b0;
        cov_jalr = 1'b0;
        cov_lui = 1'b0;
        cov_auipc = 1'b0;
        cov_fence = 1'b0;
        cov_op = 10'b0;
        cov_op_imm = 9'b0;
        cov_load = 5'b0;
        cov_store = 3'b0;
        cov_wstrb = 7'b0;
        cov_imem_stall = 1'b0;
        cov_dmem_stall = 1'b0;

        for (init_index = 0; init_index < IMEM_WORDS;
             init_index = init_index + 1) begin
            imem[init_index] = enc_i(
                12'b0, 5'd0, 3'b000, 5'd0, OPC_OP_IMM
            );
            retired_seen[init_index] = 1'b0;
        end
        for (init_index = 0; init_index < DMEM_BYTES;
             init_index = init_index + 1)
            dmem[init_index] = 8'b0;
        for (init_index = 0; init_index <= 36;
             init_index = init_index + 1)
            expected_sig[init_index] = 32'b0;
        for (init_index = 0; init_index < 6;
             init_index = init_index + 1)
            wrong_path_pc[init_index] = 32'hFFFFFFFF;

        // x20=data base, x21=signature base.
        emit(enc_i(12'h100, 5'd0, 3'b000, 5'd20, OPC_OP_IMM));
        emit(enc_i(12'h200, 5'd0, 3'b000, 5'd21, OPC_OP_IMM));

        // Forwarding EX/MEM, ưu tiên MEM trên WB, và forwarding từ WB.
        emit(enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM));
        pc_forward_exmem = program_words * 4;
        emit(enc_i(12'd7, 5'd1, 3'b000, 5'd2, OPC_OP_IMM));
        emit(enc_r(7'b0000000, 5'd1, 5'd2, 3'b000, 5'd3, OPC_OP));
        emit(enc_i(12'd9, 5'd0, 3'b000, 5'd4, OPC_OP_IMM));
        emit(enc_i(12'd0, 5'd0, 3'b000, 5'd0, OPC_OP_IMM));
        pc_forward_wb = program_words * 4;
        emit(enc_r(7'b0000000, 5'd1, 5'd4, 3'b000, 5'd5, OPC_OP));
        emit(enc_s(12'd0, 5'd2, 5'd21, 3'b010, OPC_STORE));
        emit(enc_s(12'd4, 5'd3, 5'd21, 3'b010, OPC_STORE));
        emit(enc_s(12'd8, 5'd5, 5'd21, 3'b010, OPC_STORE));
        expected_sig[0] = 32'd12;
        expected_sig[1] = 32'd17;
        expected_sig[2] = 32'd14;

        // Toàn bộ lớp ALU dạng R; store ngay sau producer còn kiểm store-data.
        emit(enc_i(12'hFF0, 5'd0, 3'b000, 5'd6, OPC_OP_IMM)); // -16
        emit(enc_i(12'd3, 5'd0, 3'b000, 5'd7, OPC_OP_IMM));

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b000, 5'd8, OPC_OP));
        emit(enc_s(12'd12, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[3] = 32'hFFFFFFF3;

        emit(enc_r(7'b0100000, 5'd6, 5'd7, 3'b000, 5'd8, OPC_OP));
        emit(enc_s(12'd16, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[4] = 32'h00000013;

        emit(enc_r(7'b0000000, 5'd7, 5'd7, 3'b001, 5'd8, OPC_OP));
        emit(enc_s(12'd20, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[5] = 32'h00000018;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b010, 5'd8, OPC_OP));
        emit(enc_s(12'd24, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[6] = 32'h00000001;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b011, 5'd8, OPC_OP));
        emit(enc_s(12'd28, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[7] = 32'h00000000;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b100, 5'd8, OPC_OP));
        emit(enc_s(12'd32, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[8] = 32'hFFFFFFF3;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b101, 5'd8, OPC_OP));
        emit(enc_s(12'd36, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[9] = 32'h1FFFFFFE;

        emit(enc_r(7'b0100000, 5'd7, 5'd6, 3'b101, 5'd8, OPC_OP));
        emit(enc_s(12'd40, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[10] = 32'hFFFFFFFE;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b110, 5'd8, OPC_OP));
        emit(enc_s(12'd44, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[11] = 32'hFFFFFFF3;

        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b111, 5'd8, OPC_OP));
        emit(enc_s(12'd48, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[12] = 32'h00000000;

        // Toàn bộ lớp ALU immediate, gồm hai loại dịch phải.
        emit(enc_i(12'd0, 5'd6, 3'b010, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd52, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[13] = 32'h00000001;

        emit(enc_i(12'hFFF, 5'd7, 3'b011, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd56, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[14] = 32'h00000001;

        emit(enc_i(12'h0FF, 5'd6, 3'b100, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd60, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[15] = 32'hFFFFFF0F;

        emit(enc_i(12'h155, 5'd0, 3'b110, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd64, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[16] = 32'h00000155;

        emit(enc_i(12'h00F, 5'd6, 3'b111, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd68, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[17] = 32'h00000000;

        emit(enc_i(12'h004, 5'd7, 3'b001, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd72, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[18] = 32'h00000030;

        emit(enc_i(12'h004, 5'd6, 3'b101, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd76, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[19] = 32'h0FFFFFFF;

        emit(enc_i(12'h404, 5'd6, 3'b101, 5'd8, OPC_OP_IMM));
        emit(enc_s(12'd80, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[20] = 32'hFFFFFFFF;

        // U-type: LUI và AUIPC, rồi dùng ngay kết quả làm store-data.
        pc_lui = program_words * 4;
        emit(enc_u(20'h12345, 5'd8, OPC_LUI));
        emit(enc_s(12'd84, 5'd8, 5'd21, 3'b010, OPC_STORE));
        expected_sig[21] = 32'h12345000;

        idx_auipc_value = program_words;
        pc_auipc = program_words * 4;
        emit(enc_u(20'h00001, 5'd9, OPC_AUIPC));
        emit(enc_s(12'd88, 5'd9, 5'd21, 3'b010, OPC_STORE));
        expected_sig[22] = (idx_auipc_value * 4) + 32'h00001000;

        // Mẫu little-endian tại DATA_BASE: byte 01, 7F, FF, 80.
        emit(enc_u(20'h80FF8, 5'd10, OPC_LUI));
        emit(enc_i(12'hF01, 5'd10, 3'b000, 5'd10, OPC_OP_IMM));
        emit(enc_s(12'd0, 5'd10, 5'd20, 3'b010, OPC_STORE));

        emit(enc_i(12'd0, 5'd20, 3'b000, 5'd11, OPC_LOAD)); // LB
        pc_load_use = program_words * 4;
        emit(enc_i(12'd1, 5'd11, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd92, 5'd12, 5'd21, 3'b010, OPC_STORE));
        expected_sig[23] = 32'h00000002;

        emit(enc_i(12'd2, 5'd20, 3'b000, 5'd11, OPC_LOAD)); // LB
        emit(enc_s(12'd96, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[24] = 32'hFFFFFFFF;

        emit(enc_i(12'd2, 5'd20, 3'b100, 5'd11, OPC_LOAD)); // LBU
        emit(enc_s(12'd100, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[25] = 32'h000000FF;

        emit(enc_i(12'd0, 5'd20, 3'b001, 5'd11, OPC_LOAD)); // LH
        emit(enc_s(12'd104, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[26] = 32'h00007F01;

        emit(enc_i(12'd2, 5'd20, 3'b001, 5'd11, OPC_LOAD)); // LH
        emit(enc_s(12'd108, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[27] = 32'hFFFF80FF;

        emit(enc_i(12'd2, 5'd20, 3'b101, 5'd11, OPC_LOAD)); // LHU
        emit(enc_s(12'd112, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[28] = 32'h000080FF;

        emit(enc_i(12'd0, 5'd20, 3'b010, 5'd11, OPC_LOAD)); // LW
        emit(enc_s(12'd116, 5'd11, 5'd21, 3'b010, OPC_STORE));
        expected_sig[29] = 32'h80FF7F01;

        // SB trên cả bốn byte lane; mỗi store dùng producer ngay trước nó.
        emit(enc_i(12'h011, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd0, 5'd12, 5'd20, 3'b000, OPC_STORE));
        emit(enc_i(12'h022, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd1, 5'd12, 5'd20, 3'b000, OPC_STORE));
        emit(enc_i(12'h033, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd2, 5'd12, 5'd20, 3'b000, OPC_STORE));
        emit(enc_i(12'h044, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd3, 5'd12, 5'd20, 3'b000, OPC_STORE));
        emit(enc_i(12'd0, 5'd20, 3'b010, 5'd13, OPC_LOAD));
        emit(enc_s(12'd120, 5'd13, 5'd21, 3'b010, OPC_STORE));
        expected_sig[30] = 32'h44332211;

        // SH tại lower/upper halfword lane rồi đọc lại bằng LW.
        emit(enc_i(12'h123, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd0, 5'd12, 5'd20, 3'b001, OPC_STORE));
        emit(enc_i(12'h456, 5'd0, 3'b000, 5'd12, OPC_OP_IMM));
        emit(enc_s(12'd2, 5'd12, 5'd20, 3'b001, OPC_STORE));
        emit(enc_i(12'd0, 5'd20, 3'b010, 5'd13, OPC_LOAD));
        emit(enc_s(12'd124, 5'd13, 5'd21, 3'b010, OPC_STORE));
        expected_sig[31] = 32'h04560123;

        // Branch taken: hai lệnh ngay sau phải bị flush hoàn toàn.
        emit(enc_i(12'd7, 5'd0, 3'b000, 5'd1, OPC_OP_IMM));
        emit(enc_i(12'd7, 5'd0, 3'b000, 5'd2, OPC_OP_IMM));
        idx_branch_taken = program_words;
        pc_branch_taken = program_words * 4;
        emit(32'b0); // backpatch BEQ
        wrong_path_pc[0] = program_words * 4;
        emit(enc_i(12'd99, 5'd0, 3'b000, 5'd14, OPC_OP_IMM));
        wrong_path_pc[1] = program_words * 4;
        emit(enc_s(12'd160, 5'd14, 5'd21, 3'b010, OPC_STORE));
        idx_branch_target = program_words;
        emit(enc_i(12'd1, 5'd0, 3'b000, 5'd14, OPC_OP_IMM));
        emit(enc_s(12'd128, 5'd14, 5'd21, 3'b010, OPC_STORE));
        imem[idx_branch_taken] = enc_b(
            (idx_branch_target - idx_branch_taken) * 4,
            5'd2, 5'd1, 3'b000, OPC_BRANCH
        );
        expected_sig[32] = 32'h00000001;

        // BNE không taken; ADDI tuần tự phải được giữ và retire.
        pc_branch_not_taken = program_words * 4;
        emit(enc_b(13'd8, 5'd2, 5'd1, 3'b001, OPC_BRANCH));
        emit(enc_i(12'd2, 5'd0, 3'b000, 5'd14, OPC_OP_IMM));
        emit(enc_s(12'd132, 5'd14, 5'd21, 3'b010, OPC_STORE));
        expected_sig[33] = 32'h00000002;

        // JAL: link=PC+4; hai lệnh sai đường không được retire/ghi memory.
        idx_jal = program_words;
        pc_jal = program_words * 4;
        emit(32'b0); // backpatch JAL
        wrong_path_pc[2] = program_words * 4;
        emit(enc_i(12'd77, 5'd0, 3'b000, 5'd15, OPC_OP_IMM));
        wrong_path_pc[3] = program_words * 4;
        emit(enc_s(12'd164, 5'd15, 5'd21, 3'b010, OPC_STORE));
        idx_jal_target = program_words;
        emit(enc_s(12'd136, 5'd15, 5'd21, 3'b010, OPC_STORE));
        imem[idx_jal] = enc_j(
            (idx_jal_target - idx_jal) * 4,
            5'd15, OPC_JAL
        );
        expected_sig[34] = (idx_jal * 4) + 32'd4;

        // AUIPC+ADDI dựng địa chỉ tuyệt đối, JALR dùng kết quả forward mới nhất.
        idx_jalr_auipc = program_words;
        emit(enc_u(20'h00000, 5'd16, OPC_AUIPC));
        idx_jalr_addi = program_words;
        emit(32'b0); // backpatch ADDI tạo target
        idx_jalr = program_words;
        pc_jalr = program_words * 4;
        emit(enc_i(12'd0, 5'd16, 3'b000, 5'd17, OPC_JALR));
        wrong_path_pc[4] = program_words * 4;
        emit(enc_i(12'd55, 5'd0, 3'b000, 5'd17, OPC_OP_IMM));
        wrong_path_pc[5] = program_words * 4;
        emit(enc_s(12'd168, 5'd17, 5'd21, 3'b010, OPC_STORE));
        idx_jalr_target = program_words;
        emit(enc_s(12'd140, 5'd17, 5'd21, 3'b010, OPC_STORE));
        imem[idx_jalr_addi] = enc_i(
            (idx_jalr_target - idx_jalr_auipc) * 4,
            5'd16, 3'b000, 5'd16, OPC_OP_IMM
        );
        expected_sig[35] = (idx_jalr * 4) + 32'd4;

        // FENCE phải retire như NOP hợp lệ; magic xác nhận chương trình tới cuối.
        pc_fence = program_words * 4;
        emit(enc_i(12'b0, 5'd0, 3'b000, 5'd0, OPC_MISC_MEM));
        emit(enc_u(20'h600DD, 5'd18, OPC_LUI));
        emit(enc_i(12'hAFE, 5'd18, 3'b000, 5'd18, OPC_OP_IMM));
        emit(enc_s(12'd144, 5'd18, 5'd21, 3'b010, OPC_STORE));
        expected_sig[36] = 32'h600DCAFE;

        pc_ebreak = program_words * 4;
        emit(EBREAK_INSN);

        // Sáu lệnh sai đường và EBREAK không thuộc trace retire thành công.
        expected_retire_count = program_words - 7;

        // Reset đồng bộ qua nhiều cạnh để xóa toàn bộ register file/pipeline.
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    end

    // ---------------------------------------------------------------------
    // Điều kiện kết thúc và tổng hợp coverage.
    // ---------------------------------------------------------------------
    initial begin
        wait (rst === 1'b0);
        wait (trap_valid === 1'b1);
        #1;

        if (!halted)
            $fatal(1, "trap_valid asserted but halted_o is low");
        if (trap_cause !== 5'd3)
            $fatal(1, "Wrong EBREAK cause: got=%0d expected=3", trap_cause);
        if ((trap_pc !== pc_ebreak) || (trap_instr !== EBREAK_INSN)) begin
            $fatal(1,
                   "Wrong trap metadata: pc/instr=%h/%h expected=%h/%h",
                   trap_pc, trap_instr, pc_ebreak, EBREAK_INSN);
        end

        verify_signature;

        if (retire_count != expected_retire_count)
            $fatal(1, "Retire count mismatch: got=%0d expected=%0d",
                   retire_count, expected_retire_count);
        if (!cov_forward_exmem || !cov_forward_wb || !cov_load_use)
            $fatal(1, "Hazard coverage missing: EXMEM/WB/load-use=%b/%b/%b",
                   cov_forward_exmem, cov_forward_wb, cov_load_use);
        if (!cov_branch_taken || !cov_branch_not_taken ||
            !cov_jal || !cov_jalr)
            $fatal(1, "Control-flow coverage missing: B_T/B_N/J/JR=%b/%b/%b/%b",
                   cov_branch_taken, cov_branch_not_taken, cov_jal, cov_jalr);
        if (!cov_lui || !cov_auipc || !cov_fence)
            $fatal(1, "U/FENCE coverage missing: LUI/AUIPC/FENCE=%b/%b/%b",
                   cov_lui, cov_auipc, cov_fence);
        if (cov_op !== 10'b1111111111)
            $fatal(1, "OP coverage incomplete: %b", cov_op);
        if (cov_op_imm !== 9'b111111111)
            $fatal(1, "OP-IMM coverage incomplete: %b", cov_op_imm);
        if (cov_load !== 5'b11111)
            $fatal(1, "LOAD coverage incomplete: %b", cov_load);
        if (cov_store !== 3'b111)
            $fatal(1, "STORE coverage incomplete: %b", cov_store);
        if (cov_wstrb !== 7'b1111111)
            $fatal(1, "Byte-strobe coverage incomplete: %b", cov_wstrb);
        if (!cov_imem_stall || !cov_dmem_stall)
            $fatal(1, "Wait-state coverage missing: imem/dmem=%b/%b",
                   cov_imem_stall, cov_dmem_stall);

        if (STRESS_SEED != 0) begin
            if (stress_two_pending == 0 || stress_overlap == 0)
                $fatal(1, "Stress did not cover two outstanding requests and simultaneous grant/response");
            $display("Stress seed=%0d: two_pending_cycles=%0d simultaneous_grant_response=%0d",
                     STRESS_SEED, stress_two_pending, stress_overlap);
        end

        // Cho phép request fetch sai đường đang pending được drain sau trap.
        repeat (16) @(posedge clk);
        #1;
        if (!trap_valid || !halted)
            $fatal(1, "Trap/halted state was not sticky");
        if (imem_req || dmem_req)
            $fatal(1, "Memory request remains after halted: imem/dmem=%b/%b",
                   imem_req, dmem_req);

        $display(
            "PASS tb_rv32_core: retired=%0d, imem_tx=%0d, dmem_tx=%0d, imem_wait_cycles=%0d, dmem_wait_cycles=%0d",
            retire_count, imem_transaction_count, dmem_transaction_count,
            imem_wait_cycles, dmem_wait_cycles
        );
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $fatal(1,
               "Timeout: fetch_pc=%h retire_count=%0d imem(req/gnt/addr)=%b/%b/%h dmem(req/ready/addr)=%b/%b/%h",
               debug_fetch_pc, retire_count,
               imem_req, imem_gnt, imem_addr,
               dmem_req, dmem_ready, dmem_addr);
    end

endmodule

`default_nettype wire
