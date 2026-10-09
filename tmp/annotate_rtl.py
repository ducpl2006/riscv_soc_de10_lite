"""One-off, comment-only RTL documentation pass; retain a baseline for verification."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'tmp/rtl_comments_before.json'

def entries(text):
    return dict(line.split('|', 1) for line in text.strip().splitlines())

COMMON = entries('''
clk|Clock hệ thống; mạch tuần tự cập nhật tại cạnh lên.
rst|Reset tích cực cao; xóa trạng thái tại cạnh lên, đồng thời chặn giao dịch mới.
instr|Mã lệnh RV32I 32 bit của lệnh đang xét.
pc|Địa chỉ byte của lệnh đang xét, dùng cho đích nhánh và trace/trap.
pc4|PC + 4 của lệnh đang xét; địa chỉ trở về cho JAL/JALR.
valid|1: tầng đang chứa một lệnh; 0: bubble, không được tạo tác dụng phụ.
exc_valid|1: lệnh đã mang ngoại lệ; chặn thực thi/ghi kết quả thông thường.
exc_cause|Mã nguyên nhân ngoại lệ; chỉ có nghĩa khi exc_valid=1.
rs1_addr|Chỉ số thanh ghi nguồn rs1 (0..31); không phải địa chỉ bộ nhớ.
rs2_addr|Chỉ số thanh ghi nguồn rs2 (0..31); không phải địa chỉ bộ nhớ.
rd_addr|Chỉ số thanh ghi đích rd (0..31); ghi x0 bị bỏ qua tại commit.
rs1_data|Giá trị toán hạng nguồn rs1, rộng 32 bit.
rs2_data|Giá trị toán hạng nguồn rs2, rộng 32 bit.
rs1_value|Giá trị rs1 sau chọn forwarding, dùng cho ALU/so sánh nhánh.
rs2_value|Giá trị rs2 sau forwarding, dùng cho ALU/nhánh và dữ liệu store.
imm|Immediate 32 bit: mở rộng dấu I/S/B/J; dạng U có 12 bit thấp bằng 0.
imm_type|Chọn dạng immediate theo RV32_IMM_* trong rv32_defs.vh.
alu_op|Mã phép toán nội bộ RV32_ALU_* trong rv32_defs.vh.
alu_result|Kết quả ALU 32 bit; với load/store là địa chỉ byte hiệu dụng.
op_a_sel|Chọn toán hạng A: RV32_OP_A_RS1 / PC / ZERO.
op_b_imm|1: ALU lấy immediate làm B; 0: lấy giá trị rs2.
reg_write|Yêu cầu ghi rd; còn phải kiểm tra valid, ngoại lệ và rd khác x0.
wb_sel|Chọn nguồn ghi về: RV32_WB_ALU / LOAD / PC4.
wb_data|Dữ liệu 32 bit đã chọn để ghi về thanh ghi đích.
branch|1: lệnh nhánh có điều kiện; chưa có nghĩa là nhánh được lấy.
jal|1: lệnh JAL, nhảy tới PC + immediate và ghi PC+4 vào rd.
jalr|1: lệnh JALR; đích rs1 + immediate phải xóa bit 0.
load|1: lệnh đọc bộ nhớ; cỡ đọc và mở rộng dấu do funct3 quyết định.
store|1: lệnh ghi bộ nhớ; cỡ ghi do funct3 quyết định.
funct3|Trường instr[14:12], chọn điều kiện nhánh hoặc cỡ/kiểu load-store.
uses_rs1|1: lệnh thực sự đọc rs1; dùng để tránh báo hazard giả.
uses_rs2|1: lệnh thực sự đọc rs2; dùng để tránh báo hazard giả.
fence|1: FENCE hợp lệ; thực hiện như NOP trong core in-order hiện tại.
ecall|1: lệnh ECALL; ID tạo ngoại lệ cause 11.
ebreak|1: lệnh EBREAK; ID tạo ngoại lệ breakpoint, cause 3.
illegal|1: mã lệnh không hỗ trợ/không hợp lệ; các tác dụng phụ bị vô hiệu.
decode_exc|Ngoại lệ do giải mã: illegal, EBREAK hoặc ECALL; chưa xét valid tầng.
any_exc|Có lỗi fetch đi kèm hoặc lỗi giải mã mới tại ID.
any_exc_cause|Cause đưa sang EX; lỗi fetch có ưu tiên hơn lỗi giải mã.
halted|Core đã dừng do trap; giữ mức 1 đến reset.
wb_regfile_we|Cho phép commit rd tại cạnh lên; đã chặn reset, lỗi, halt và x0.
wb_trap_event|Lệnh lỗi hợp lệ tại WB; sự kiện chốt trap và hủy các lệnh trẻ hơn.
mem_fault_raw|Lỗi data bus tại cạnh req && ready; chưa qua điều khiển pipeline.
ex_fault_raw|Lỗi căn chỉnh tại EX; đã xét valid/ngoại lệ, chưa xét MEM stall.
mem_fault_event|Lỗi MEM được đưa tới điều khiển để loại các lệnh trẻ hơn.
ex_fault_event|Lỗi EX được xử lý khi MEM không stall và không có lỗi già hơn.
ex_redirect_event|Nhánh/jump hợp lệ đổi PC; hủy lệnh trẻ và đáp ứng fetch sai đường.
id_exception_event|Ngoại lệ ID được xử lý sau khi loại các sự kiện ưu tiên ở MEM/EX.
load_use_stall|Dừng ID và chèn bubble vào EX vì dữ liệu load chưa sẵn sàng.
stall_load_use|Hazard load-use thô giữa ID và EX; bộ điều khiển phân xử stall/flush.
ifid_consumed|Xác nhận lấy đầu FIFO IF/ID tại cạnh lên; chỉ phát khi ID được tiến.
control_target|Đích nhánh/jump từ ALU; JALR đã xóa bit 0.
control_taken|Yêu cầu nhảy/nhánh lấy; bộ điều khiển còn phải xét valid và ngoại lệ.
target_misaligned|Đích nhánh/jump đang lấy không chia hết cho 4; cần cause 0.
forward_rs1_sel|Chọn rs1: 00=ID/EX, 01=WB, 10=MEM; không forward load sớm từ MEM.
forward_rs2_sel|Chọn rs2: 00=ID/EX, 01=WB, 10=MEM; MEM ưu tiên hơn WB.
forward_rs1|Chọn rs1: 00=ID/EX, 01=WB, 10=MEM; rd=x0 không được forward.
forward_rs2|Chọn rs2: 00=ID/EX, 01=WB, 10=MEM; rd=x0 không được forward.
imem_req|Yêu cầu lấy lệnh; giữ mức 1 cùng địa chỉ tới cạnh req && gnt.
imem_addr|Địa chỉ byte lấy lệnh, căn 4; giữ ổn định khi req && !gnt.
imem_gnt|Memory nhận yêu cầu tại cạnh req && gnt; chưa phải dữ liệu trả về.
imem_rvalid|Có đáp ứng cho yêu cầu đã grant trước đó; không có rready.
imem_rdata|Word lệnh trả về; chỉ dùng khi rvalid=1 và err=0.
imem_err|Lỗi lấy lệnh; chỉ xét cùng rvalid, tạo cause 1 nếu đúng đường.
dmem_req|Yêu cầu load/store; giữ nguyên payload tới cạnh req && ready.
dmem_we|1: ghi, 0: đọc; bằng 0 khi không có yêu cầu dữ liệu.
dmem_addr|Địa chỉ byte đã căn xuống biên 4 byte; LSU xử lý byte lane riêng.
dmem_wdata|Dữ liệu store đã đặt vào đúng byte lane của word 32 bit.
dmem_wstrb|Bit n cho phép ghi byte [8*n +: 8]; bằng 0 khi không ghi.
dmem_rdata|Word đọc từ bus; chỉ dùng khi req && ready && !we && !err.
dmem_ready|Hoàn tất giao dịch tại cạnh req && ready, kể cả khi err=1.
dmem_err|Lỗi data bus; chỉ có nghĩa khi req && ready, sinh cause 5/7.
debug_fetch_pc|PC cho yêu cầu fetch mới; không phải PC retire hay địa chỉ đang giữ chờ grant.
trap_valid|Ngoại lệ đã commit tại WB; giữ 1 cùng metadata trap đến reset.
trap_cause|Mã ngoại lệ đã chốt; có nghĩa khi trap_valid=1.
trap_pc|PC của lệnh gây trap; có nghĩa khi trap_valid=1.
trap_instr|Mã lệnh gây trap; bằng 0 nếu lỗi fetch không có mã lệnh hợp lệ.
retire_valid|Có lệnh hoàn tất thành công ở cạnh vừa qua; có thể cao nhiều chu kỳ liên tiếp.
retire_pc|PC của lệnh vừa hoàn tất; chỉ dùng khi retire_valid=1.
retire_instr|Mã lệnh vừa hoàn tất; chỉ dùng khi retire_valid=1.
retire_rd_we|Lệnh retire có ghi rd khác x0; chỉ xét khi retire_valid=1.
retire_rd_addr|Chỉ số rd đã ghi; chỉ dùng khi retire_valid && retire_rd_we.
retire_rd_data|Giá trị đã ghi vào rd; chỉ dùng khi retire_valid && retire_rd_we.
req|Yêu cầu truy cập slave; master giữ payload đến cạnh req && ready.
we|1: yêu cầu ghi, 0: đọc; chỉ có ý nghĩa khi req=1.
addr|Offset địa chỉ byte trong vùng thanh ghi của ngoại vi.
wdata|Dữ liệu ghi 32 bit; chỉ các byte được wstrb chọn mới được cập nhật.
wstrb|Bit n chọn byte [8*n +: 8]; không chọn byte nào vẫn phải kiểm tra quyền/địa chỉ.
rdata|Dữ liệu đọc; master chỉ sử dụng khi req && ready && !we && !err.
ready|Hoàn tất giao dịch tại cạnh req && ready; có thể kèm err.
err|Lỗi địa chỉ/quyền truy cập; master chỉ xét khi req && ready.
switches|Mức của 10 switch đã đồng bộ với clk_i tại lớp board.
leds|Giá trị thanh ghi GPIO 10 bit; lớp board quyết định ánh xạ ra LED vật lý.
uart_tx|Đường UART phát 8N1, LSB trước; mức rảnh là 1.
i2c_scl|Mức SCL thực tế đã đồng bộ; dùng để phát hiện clock stretching.
i2c_sda|Mức SDA thực tế đã đồng bộ; dùng để nhận dữ liệu/ACK và kiểm tra bus.
i2c_scl_drive_low|1: yêu cầu kéo SCL xuống 0; 0: nhả chân ở high-Z qua lớp board.
i2c_sda_drive_low|1: yêu cầu kéo SDA xuống 0; 0: nhả chân để điện trở pull-up kéo cao.
scl|Mức SCL thực tế đã đồng bộ; FSM chờ khi thiết bị giữ SCL thấp.
sda|Mức SDA thực tế đã đồng bộ; lấy mẫu bit dữ liệu/ACK từ thiết bị.
scl_drive_low|1: kéo SCL thấp; 0: nhả high-Z, không chủ động lái mức cao.
sda_drive_low|1: kéo SDA thấp; 0: nhả high-Z, cần điện trở pull-up.
qnn_busy|1: accelerator đang suy luận; 0: rảnh.
qnn_done|Cờ hoàn tất, giữ tới start mới, lệnh clear-done hoặc reset.
qnn_result|Kết quả suy luận gần nhất, 0..1000; mỗi đơn vị bằng 0,1 %SOC.
slave_req|Bit SOC_SLAVE_* chọn slave; tối đa một bit bằng 1, reset/idle bằng 0.
slave_rdata|Lane n dùng [n*32 +: 32]; response phải khớp lane request được chọn.
slave_ready|Bit n báo hoàn tất từ slave n; chỉ lane được chọn được trả về master.
slave_err|Bit n báo lỗi từ slave n; chỉ xét cùng ready của chính lane đó.
''')

PARAMS = entries('''
RESET_VECTOR|PC khởi động (địa chỉ byte); nên căn 4, lệch hàng sẽ tạo trap tại IF.
CLOCK_HZ|Tần số clk_i tính bằng Hz, dùng tính bộ chia UART/I2C.
BAUD|Tốc độ UART, bit/giây; bộ chia làm tròn theo CLOCK_HZ.
I2C_HZ|Tần số SCL mục tiêu tính bằng Hz; cần CLOCK_HZ >= 4*I2C_HZ.
ROM_WORDS|Dung lượng ROM theo số word 32 bit; số byte bằng ROM_WORDS*4.
RAM_WORDS|Dung lượng SRAM theo số word 32 bit; số byte bằng RAM_WORDS*4.
WORDS|Số phần tử lưu trữ; mỗi phần tử có độ rộng dữ liệu của module.
WIDTH|Số bit của mỗi phần tử lưu trữ, không phải số byte.
ADDR_WIDTH|Số bit địa chỉ phần tử; phải đủ biểu diễn các chỉ số 0..WORDS-1.
BYTE_COUNT|Số byte lane ghi, mỗi lane 8 bit; cấu hình phải khớp WIDTH.
USE_INIT_FILE|Khác 0: mô phỏng nạp HEX; backend Quartus dùng INIT_FILE trực tiếp.
INIT_FILE|Đường dẫn file khởi tạo ROM; HEX cho mô phỏng, MIF/HEX phù hợp backend tổng hợp.
USE_ROM_INIT_FILE|Chuyển cờ nạp ROM tới wrapper; mô phỏng bật nạp file khi khác 0.
ROM_INIT_FILE|File khởi tạo ROM chương trình, chuyển tới soc_rom_dp.
USE_INIT_FILES|Khác 0: nạp trọng số/bias từ file; 0: dùng dữ liệu khởi tạo mặc định/testbench.
USE_QNN_INIT_FILES|Chuyển cờ nạp các file model xuống QNN accelerator.
L1_SHIFT|Số bit dịch phải số học sau MAC lớp 1, trước ReLU/bão hòa INT8.
L2_SHIFT|Số bit dịch phải số học sau MAC lớp 2, trước ReLU/bão hòa INT8.
OUT_SHIFT|Số bit dịch phải số học đầu ra trước khi chặn về 0..1000.
L1_WEIGHT_FILE|File trọng số INT8 lớp 1, thứ tự neuron*80 + feature.
L1_BIAS_FILE|File HEX bias INT32 cho 16 neuron lớp 1.
L2_WEIGHT_FILE|File trọng số INT8 lớp 2, thứ tự neuron*16 + đầu vào.
L2_BIAS_FILE|File HEX bias INT32 cho 8 neuron lớp 2.
OUT_WEIGHT_FILE|File HEX 8 trọng số INT8 của neuron đầu ra.
OUT_BIAS_FILE|File HEX một bias INT32 của neuron đầu ra.
''')

SPECIFIC = {
'soc_bus': entries('''
rst|Reset tích cực cao: decoder tổ hợp khóa request và response ngay khi rst=1.
addr|Địa chỉ byte toàn cục của CPU, phải căn 4; decoder chọn ROM/RAM/MMIO.
selected|Chỉ số slave đã giải mã; -1 nghĩa là địa chỉ/quyền truy cập không hợp lệ.
'''),
'rv32_lsu': entries('''
addr|Địa chỉ byte hiệu dụng rs1+immediate, chưa căn word; dùng bit thấp chọn lane.
funct3|000=byte, 001=halfword, 010=word; load 100/101 mở rộng zero.
load_en|Cho phép xử lý load; phải loại trừ với store_en cho một lệnh hợp lệ.
store_en|Cho phép tạo dữ liệu/strobe store; không phát strobe nếu lệch hàng.
store_data|Giá trị rs2; lấy 8/16/32 bit thấp theo cỡ store.
load_data_i|Word 32 bit tại địa chỉ căn word; byte địa chỉ thấp nằm ở bit [7:0].
load_data_o|Kết quả load đã chọn lane và mở rộng dấu/zero lên 32 bit.
mem_addr|Địa chỉ byte căn word: xóa addr_i[1:0]; không phải chỉ số word.
mem_wdata|Dữ liệu store đã dịch tới đúng byte lane little-endian.
mem_wstrb|Bit n chọn byte n; bằng 0 nếu không store hoặc store lệch hàng.
misaligned|Truy cập halfword/word lệch hàng; byte không cần căn hàng.
lane_shift|Số bit dịch chọn byte lane, bằng addr_i[1:0]*8 (0/8/16/24).
load_shifted|Word đọc đã dịch phải để byte cần đọc nằm ở bit [7:0].
'''),
'rv32_alu': entries('''
operand_a|Toán hạng A 32 bit; SLT/SRA diễn giải dấu theo phép toán.
operand_b|Toán hạng B 32 bit; phép dịch chỉ dùng 5 bit thấp.
result|Kết quả tổ hợp 32 bit; ADD/SUB modulo 2^32, mã dự phòng trả 0.
shift_amount|Số bit dịch 0..31, lấy từ operand_b_i[4:0].
'''),
'rv32_branch_unit': entries('''
branch_en|Cho phép so sánh cho lệnh branch hợp lệ; bằng 0 thì không lấy nhánh.
funct3|000 BEQ, 001 BNE, 100 BLT, 101 BGE, 110 BLTU, 111 BGEU.
rs1_data|Toán hạng so sánh rs1 đã forwarding tại EX.
rs2_data|Toán hạng so sánh rs2 đã forwarding tại EX.
branch_taken|1 khi branch_en=1 và điều kiện đúng; không tính địa chỉ đích.
'''),
'rv32_ex_stage': entries('''
rs1_data|Giá trị rs1 chốt trong ID/EX, trước mux forwarding.
rs2_data|Giá trị rs2 chốt trong ID/EX, trước mux forwarding.
fault_raw|Lỗi căn chỉnh khi valid && !exc_valid; cần phân xử với MEM trước khi xử lý.
fault_cause|Cause 0/4/6 cho đích nhảy/load/store lệch hàng; chỉ dùng khi fault_raw=1.
mem_forward_data|Kết quả sớm từ EX/MEM: PC+4 cho jump, ALU cho các lệnh khác.
ex_operand_a|Toán hạng A thực tế vào ALU sau chọn rs1/PC/0.
ex_operand_b|Toán hạng B thực tế vào ALU sau chọn immediate/rs2.
ex_branch_taken|Kết quả so sánh branch đã khóa bởi valid và không có ngoại lệ.
ex_lsu_misaligned|LSU kiểm tra địa chỉ load/store tại EX trước khi phát data bus.
'''),
'rv32_mem_stage': entries('''
rst|Reset tích cực cao; logic tổ hợp chặn phát dmem_req khi reset.
stall|1 khi req && !ready: core phải giữ EX/MEM và payload bus.
fault_raw|Giao dịch dữ liệu kết thúc có lỗi: dmem_req && dmem_ready && dmem_err.
store_data|Giá trị rs2 đã forwarding, chốt ở EX/MEM để tạo dữ liệu store.
mem_lsu_addr|Địa chỉ byte đã căn word đưa lên dmem_addr.
mem_lsu_wdata|Dữ liệu store sau đặt vào đúng byte lane.
mem_lsu_wstrb|Byte-enable do LSU sinh; chỉ đưa lên bus khi dmem_we=1.
mem_load_data|Dữ liệu load đã căn lane và mở rộng dấu/zero để ghi rd.
dmem_fire|Giao dịch hoàn tất tại cạnh lên khi req && ready, kể cả giao dịch lỗi.
'''),
'rv32_regfile': entries('''
rd_we|Yêu cầu ghi rd tại cạnh lên; module còn chặn reset và rd=x0.
rd_data|Dữ liệu ghi rd; đồng thời là nguồn bypass tới cổng đọc trùng địa chỉ.
rs1_data|Dữ liệu đọc tổ hợp rs1: ưu tiên x0=0, rồi bypass WB, rồi mảng thanh ghi.
rs2_data|Dữ liệu đọc tổ hợp rs2: ưu tiên x0=0, rồi bypass WB, rồi mảng thanh ghi.
write_valid|Ghi hợp lệ sau khi loại reset và x0; cũng bật bypass write-through.
registers|31 thanh ghi x1..x31; x0 là hằng 0 nên không có phần tử lưu trữ.
reset_index|Chỉ số vòng lặp xóa x1..x31 khi reset.
'''),
'soc_ram': entries('''
addr|Offset byte tính từ RAM_BASE, phải căn 4 và nhỏ hơn WORDS*4.
pending_q|Đã chụp request, đang chờ dữ liệu storage để đăng ký response.
pending_err_q|Lỗi range/alignment của request đã chụp, giữ tới response.
valid_addr|Địa chỉ nằm trong dung lượng SRAM và chia hết cho 4.
accept|Chụp request khi rảnh; khác với handshake hoàn tất req && ready.
ram_enable|Cho storage hoạt động khi chụp request có địa chỉ hợp lệ.
ram_q|Word storage đọc ở cạnh chụp; khi ghi, trả word cũ trước cập nhật.
value|Số phần tử cần tính ceil(log2) để chọn độ rộng địa chỉ storage.
temporary|Biến tạm dịch phải value-1 trong hàm clog2.
'''),
'soc_rom_dp': entries('''
i_req|Yêu cầu đọc instruction; nhận tại cạnh i_req && i_gnt.
i_addr|Offset byte instruction trong ROM, căn 4 và nhỏ hơn WORDS*4.
i_gnt|Cho phép nhận request mới mỗi chu kỳ ngoài reset; không phải response valid.
i_rdata|Word lệnh cho request trước đó; bằng 0 khi không valid hoặc có lỗi.
i_rvalid|Đáp ứng instruction; core lấy mẫu sớm nhất một cạnh sau grant.
i_err|Lỗi range/alignment instruction, chỉ có nghĩa khi i_rvalid=1.
d_req|Yêu cầu đọc cổng data; giữ cùng địa chỉ tới cạnh d_req && d_ready.
d_addr|Offset byte cổng data trong ROM, căn 4 và nhỏ hơn WORDS*4.
d_rdata|Word đọc cổng data; chỉ dùng tại d_req && d_ready && !d_err.
d_ready|Hoàn tất data ở N+2 nếu chụp nội bộ tại N; nhận tiếp sớm nhất N+3.
d_err|Lỗi range/alignment cổng data; có nghĩa khi d_req && d_ready.
i_rom_q|Dữ liệu storage cổng instruction, chốt tại cạnh nhận request.
d_rom_q|Dữ liệu storage cổng data, chuyển sang response khi pending.
d_pending_q|Đã chụp request data, đang đợi để đăng ký response.
i_valid_q|Metadata cho instruction đã grant; đồng hành với dữ liệu ROM.
i_err_q|Lỗi địa chỉ của instruction đã grant, đồng hành với i_valid_q.
d_pending_err_q|Lỗi địa chỉ data đã chụp, giữ đến lúc phát d_ready.
i_valid_addr|Địa chỉ instruction trong ROM và chia hết cho 4.
d_valid_addr|Địa chỉ data trong ROM và chia hết cho 4.
value|Số phần tử cần tính ceil(log2) để chọn độ rộng địa chỉ storage.
temporary|Biến tạm dịch phải value-1 trong hàm clog2.
'''),
'soc_gpio': entries('''
addr|Offset byte MMIO: 0x0 LED đọc/ghi, 0x4 SWITCH chỉ đọc.
leds_q|Thanh ghi 10 LED; cập nhật riêng byte thấp và hai bit cao theo wstrb.
'''),
'soc_uart_tx': entries('''
addr|Offset byte MMIO: 0x0 DATA để ghi byte phát, 0x4 STATUS chỉ đọc.
ready|Ghi DATA byte thấp phải chờ nếu busy; truy cập lỗi vẫn hoàn tất để báo err.
tx|Tín hiệu UART nối tiếp 8N1; mức 1 khi rảnh, phát bit thấp trước.
busy|1 khi đang phát khung UART gồm start + 8 bit dữ liệu + stop.
busy_q|Trạng thái đang phát khung; khóa nhận byte mới đến hết stop bit.
tx_shift_q|Khung 10 bit {stop, data[7:0], start}; bit 0 được phát trước.
bit_count_q|Số bit còn phải phát, từ 10 về 0; gồm cả start và stop.
baud_count_q|Bộ đếm lùi số chu kỳ clock còn lại của bit UART hiện tại.
valid_addr|Chỉ DATA=0x0 và STATUS=0x4 là địa chỉ thanh ghi hợp lệ.
data_write|Yêu cầu ghi DATA có chọn byte thấp; chỉ phát khi đồng thời ready.
'''),
'soc_timer': entries('''
addr|Offset byte MMIO: 0x0/4 TIME_LO/HI chỉ đọc, 0x8/C CMP_LO/HI đọc/ghi.
irq|1 khi time>=compare ngoài reset; compare toàn bit 1 tắt IRQ; SoC chưa nối IRQ vào CPU.
time_q|Bộ đếm 64 bit tăng mỗi clock; reset về 0, đơn vị là chu kỳ clk_i.
compare_q|Mốc so sánh 64 bit cho IRQ; toàn bit 1 là giá trị vô hiệu hóa.
snapshot_hi_q|32 bit cao của time được chụp khi đọc TIME_LO, tránh dữ liệu rách.
snapshot_valid_q|Đã có snapshot từ lần đọc TIME_LO; TIME_HI dùng nó đến lần chụp mới/reset.
'''),
'soc_i2c_master': entries('''
addr|Offset byte MMIO: DATA=0x0, CMD=0x4, STATUS=0x8, DIVIDER=0xC.
ready|Ghi DATA/CMD byte thấp chờ khi busy; đọc trạng thái và truy cập lỗi không chờ.
busy|1 khi FSM đang thực hiện lệnh truyền/nhận một byte và START/STOP tùy chọn.
state_q|Trạng thái FSM tạo START, 8 bit dữ liệu, ACK/NACK và STOP.
divider_q|Bộ đếm lùi cho nửa chu kỳ SCL; được giữ/nạp lại khi bus kéo dài pha chờ.
tx_data_q|Byte DATA đã ghi, phát MSB trước khi thực hiện lệnh write.
rx_data_q|Byte nhận được; phần mềm đọc qua DATA sau lệnh read.
bit_index_q|Chỉ số bit đang truyền/nhận, đếm từ 7 xuống 0 (MSB trước).
command_read_q|Lệnh đã chốt: 1 nhận byte, 0 phát tx_data_q.
command_stop_q|Lệnh đã chốt: tạo STOP sau byte/ACK khi bằng 1.
command_nack_q|Lệnh read đã chốt: 1 gửi NACK, 0 gửi ACK sau byte nhận.
busy_q|FSM đang chạy; chặn ghi DATA/CMD byte thấp cho đến khi hoàn tất.
done_q|Cờ hoàn tất giữ đến lệnh clear-done, execute mới hoặc reset.
ack_error_q|Thiết bị không ACK byte đã phát; xóa khi execute mới hoặc reset.
valid_addr|Kiểm tra đúng một trong bốn offset DATA/CMD/STATUS/DIVIDER.
cmd_write|Yêu cầu ghi byte thấp CMD; chỉ xử lý khi bus ready.
data_write|Yêu cầu ghi byte thấp DATA; chỉ cập nhật tx_data_q khi ready và không lỗi.
tick|Bộ chia hết thời gian nửa chu kỳ; FSM được tiến nếu không chờ bus.
wait_scl|Đang muốn SCL cao nhưng chân thực tế còn thấp (clock stretching).
wait_bus|Chờ SDA được nhả cao trước khi phát START.
'''),
'qnn_soc_accelerator': entries('''
bus_req|Yêu cầu MMIO từ decoder; lớp SoC khóa request trong reset.
bus_we|1: ghi thanh ghi/feature, 0: đọc; xét khi bus_req=1.
bus_addr|Offset byte 12 bit trong page QNN; feature ở 0x100..0x23C, bước 4 byte.
bus_wdata|Dữ liệu ghi; CONTROL và mỗi feature chỉ sử dụng byte thấp.
bus_wstrb|Byte-enable; bit 0 cho phép cập nhật CONTROL hoặc feature INT8.
bus_rdata|Dữ liệu MMIO; feature INT8 được mở rộng dấu lên 32 bit khi đọc.
bus_ready|Bằng bus_req: MMIO hoàn tất ngay, không chờ suy luận kết thúc.
bus_err|Địa chỉ/quyền truy cập MMIO không hợp lệ; khác với trạng thái busy.
busy|1: đang suy luận; start/ghi feature khi busy bị bỏ qua, không tạo wait-state.
done|Cờ hoàn tất giữ đến start mới, clear-done hoặc reset.
result|Kết quả gần nhất 0..1000, đơn vị 0,1 %SOC; cập nhật khi suy luận xong.
feature_mem|80 feature INT8 có dấu; mỗi phần tử chiếm byte thấp của một word MMIO.
l1_activation|16 đầu ra lớp 1 sau dịch phải, ReLU và bão hòa 0..127.
l2_activation|8 đầu ra lớp 2 sau dịch phải, ReLU và bão hòa 0..127.
l1_biases|16 bias INT32 có dấu, giá trị khởi đầu accumulator từng neuron lớp 1.
l2_biases|8 bias INT32 có dấu, giá trị khởi đầu accumulator từng neuron lớp 2.
out_weights|8 trọng số INT8 có dấu nối lớp 2 tới đầu ra.
out_biases|Một bias INT32 có dấu của neuron đầu ra.
state_q|FSM lần lượt fetch trọng số, MAC, lưu activation và hoàn tất output.
input_index_q|Chỉ số đầu vào đang MAC: 0..79 ở L1, 0..15 ở L2, 0..7 ở output.
neuron_index_q|Chỉ số neuron đang tính: 0..15 ở L1 hoặc 0..7 ở L2.
accumulator_q|Tổng bias và các tích INT8*INT8, tích lũy có dấu 32 bit.
busy_q|Đang chạy suy luận; dùng khóa start/ghi feature trong thời gian tính.
done_q|Cờ suy luận hoàn tất, giữ đến khi phần mềm xóa hoặc khởi động lần mới.
result_q|Kết quả đã chặn về 0..1000; giữ kết quả cũ trong lần suy luận tiếp theo.
cycle_count_q|Số chu kỳ suy luận đang chạy/gần nhất; xóa khi nhận start.
l1_weight_addr_full|Chỉ số tuyến tính neuron*80 + input trước khi thu gọn độ rộng địa chỉ.
l2_weight_addr_full|Chỉ số tuyến tính neuron*16 + input trước khi thu gọn độ rộng địa chỉ.
l1_weight_addr|Địa chỉ phần tử ROM L1 (0..1279 trong pha L1), không phải địa chỉ byte CPU.
l2_weight_addr|Địa chỉ phần tử ROM L2 (0..127 trong pha L2), không phải địa chỉ byte CPU.
l1_weight_raw|8 bit trọng số trả từ ROM L1 sau cạnh fetch.
l2_weight_raw|8 bit trọng số trả từ ROM L2 sau cạnh fetch.
l1_weight_q|Diễn giải trọng số L1 là số có dấu; đây là wire, không thêm thanh ghi.
l2_weight_q|Diễn giải trọng số L2 là số có dấu; đây là wire, không thêm thanh ghi.
init_index|Chỉ số vòng lặp khởi tạo feature, activation và model mặc định.
value|Giá trị INT32 có dấu đưa vào hàm bão hòa/chặn kết quả.
shifted|Biến tạm có dấu dùng so sánh giới hạn; hàm output áp dụng OUT_SHIFT trước.
'''),
'de10_lite_top': entries('''
MAX10_CLK1_50|Clock 50 MHz từ oscillator trên board; nguồn clock chung của SoC.
KEY|Nút nhấn active-low: KEY[0] reset, KEY[1] hiện không sử dụng.
SW|10 switch vật lý bất đồng bộ; đi qua hai tầng FF trước khi vào SoC.
LEDR|[7:0] GPIO LED, [8] QNN busy, [9] trap; bit 1 làm sáng LED tương ứng.
GPIO|[0] SCL, [1] SDA: chân hai chiều open-drain, cần pull-up.
UART_TX|Chân phát UART 8N1 115200 baud, nối header PIN_V9 theo QSF.
reset_sync_q|Chuỗi 3 FF: assert reset bất đồng bộ, nhả đồng bộ sau ba cạnh clock.
switch_meta_q|Tầng FF thứ nhất nhận SW bất đồng bộ; không dùng trực tiếp trong SoC.
switch_sync_q|Tầng FF thứ hai đưa mức SW đã đồng bộ vào SoC.
i2c_meta_q|Tầng FF thứ nhất nhận mức SCL/SDA thực tế từ pad.
i2c_sync_q|Tầng FF thứ hai; [0] SCL và [1] SDA đưa vào I2C master.
rst|Reset nội bộ active-high lấy từ tầng cuối chuỗi reset_sync_q.
soc_leds|10 bit LED từ GPIO peripheral; board chỉ dùng [7:0] cho LED GPIO.
i2c_scl_low|Yêu cầu kéo chân SCL thấp; bằng 0 thì nhả chân high-Z.
i2c_sda_low|Yêu cầu kéo chân SDA thấp; bằng 0 thì nhả chân high-Z.
'''),
}

MEMORY = entries('''
en|Cho phép đọc tại cạnh lên; output giữ giá trị cũ khi en=0.
addr|Chỉ số phần tử 0..WORDS-1 (địa chỉ word/entry), không phải địa chỉ byte CPU.
we|Cho phép ghi tại cạnh lên khi en=1; chỉ cập nhật byteena đã chọn.
byteena|Bit n cho phép ghi 8 bit data_i[n*8 +: 8].
data|Dữ liệu ghi storage; lấy mẫu tại cạnh en && we cùng địa chỉ và byteena.
q|Dữ liệu đọc xuất hiện sau cạnh en; RAM read-during-write trả dữ liệu cũ.
ram_q|Dữ liệu trả về từ primitive altsyncram, nối tới output wrapper.
rom_q|Dữ liệu trả về từ primitive ROM, nối tới output wrapper.
q_q|Thanh ghi dữ liệu đọc của backend mô phỏng; giữ khi en=0.
mem|Mảng lưu trữ backend mô phỏng; primitive Intel thay thế khi tổng hợp.
byte_index|Chỉ số vòng lặp cập nhật từng byte lane được byteena cho phép.
index|Chỉ số vòng lặp khởi tạo ROM mô phỏng về 0 trước khi nạp file.
''')
for module in ('intel_sync_ram_1p', 'intel_sync_rom_1p', 'intel_sync_rom_2p'):
    SPECIFIC[module] = MEMORY.copy()
for lane in ('a', 'b'):
    SPECIFIC['intel_sync_rom_2p'].update({
        f'{lane}_en': f'Cho phép đọc cổng {lane.upper()} tại cạnh lên; độc lập với cổng còn lại.',
        f'{lane}_addr': f'Chỉ số phần tử ROM cổng {lane.upper()}, không phải địa chỉ byte CPU.',
        f'{lane}_q': f'Dữ liệu đọc cổng {lane.upper()} sau cạnh enable; giữ khi không enable.',
        f'rom_{lane}_q': f'Dữ liệu primitive ROM cổng {lane.upper()}, nối ra wrapper.',
    })

SPECIFIC['rv32_if_stage'] = entries('''
front_stop_q|Dừng tạo request mới do ngoại lệ/halt; redirect hợp lệ có thể cho fetch chạy lại.
fetch_pc_q|PC cho request mới; tăng 4 khi phát request mới hoặc nạp đích redirect.
req_hold_valid_q|Đã phát request nhưng chưa grant; phải giữ req/địa chỉ tới khi nhận.
req_hold_pc_q|PC của request đang chờ grant; không đổi khi có redirect.
req_hold_kill_q|Request chờ grant thuộc đường bị hủy; vẫn phải grant rồi bỏ response.
req_count_q|Số request đã grant còn chờ response (0..2), theo thứ tự nhận.
req_pc0_q|PC của request đã grant lâu nhất, ứng với response kế tiếp.
req_pc1_q|PC của request đã grant thứ hai nếu req_count_q=2.
req_kill0_q|Đánh dấu bỏ response của request đầu; dùng giải phóng credit dù sai đường.
req_kill1_q|Đánh dấu bỏ response của request thứ hai; giữ qua nhiều lần redirect.
fifo_count_q|Số lệnh/ngoại lệ đã nhận đang nằm trong FIFO IF/ID (0..2).
fifo_pc0_q|PC đầu FIFO, đưa sang ID khi ifid_valid=1.
fifo_pc1_q|PC phần tử thứ hai trong FIFO, có nghĩa khi fifo_count_q=2.
fifo_instr0_q|Mã lệnh đầu FIFO; bằng 0 cho phần tử fetch fault.
fifo_instr1_q|Mã lệnh thứ hai trong FIFO, có nghĩa khi fifo_count_q=2.
fifo_exc0_q|Đầu FIFO mang ngoại lệ fetch thay vì lệnh bình thường.
fifo_exc1_q|Phần tử FIFO thứ hai mang ngoại lệ fetch.
fifo_cause0_q|Cause đầu FIFO; chỉ xét khi fifo_exc0_q=1 và FIFO không rỗng.
fifo_cause1_q|Cause phần tử thứ hai; chỉ xét khi fifo_exc1_q=1 và có phần tử đó.
external_flush_event|Có sự kiện pipeline cần xóa FIFO và hủy request fetch cũ.
stop_event|Sự kiện dừng fetch vì lỗi/halt; redirect đơn thuần không thuộc nhóm này.
fifo_pop|ID lấy một phần tử hợp lệ khỏi FIFO tại cạnh lên.
frontend_used|Tổng credit đã chiếm: FIFO + request đã grant + request đang giữ.
issue_has_credit|Còn chỗ cho response mới, hoặc ID đang giải phóng một chỗ cùng cạnh.
new_request_valid|Được tạo request mới: còn credit, PC căn hàng và frontend không bị chặn.
request_accept|Handshake instruction req && gnt tại cạnh lên.
request_capture_hold|Request mới chưa được grant; cần chốt PC để giữ payload ổn định.
request_pc|PC gắn với request hiện tại: PC đang giữ nếu có, ngược lại fetch_pc_q.
request_kill|Request hiện tại đã bị hủy khi còn chờ grant.
request_live|Request chưa bị hủy và không gặp flush ở chu kỳ hiện tại.
response_pop|Response đến và có metadata request đang chờ; lấy metadata đầu hàng đợi.
response_live|Response đúng đường, không bị flush/stop; được đưa vào FIFO.
response_push|Có response đúng đường để đẩy lệnh hoặc fetch fault vào FIFO.
local_misaligned_push|Tạo phần tử cause 0 cho PC fetch lệch hàng mà không phát memory request.
fifo_push|Thêm một phần tử từ response hoặc lỗi PC cục bộ vào FIFO.
push_pc|PC gắn với phần tử mới đưa vào FIFO.
push_instr|Word lệnh mới; bằng 0 nếu lỗi fetch hoặc lỗi PC cục bộ.
push_exc|Cờ ngoại lệ của phần tử mới; chỉ có nghĩa khi fifo_push=1.
push_cause|Cause 0 cho PC lệch hàng, cause 1 cho lỗi truy cập instruction.
fetch_exception_event|Response đúng đường báo lỗi; dừng phát request trẻ hơn.
''')

EXTRA = entries('''
opcode|Trường instr[6:0], xác định nhóm lệnh chính.
funct7|Trường instr[31:25], phân biệt phép toán và kiểm tra encoding hợp lệ.
id_decode_exc_cause|Cause do giải mã; chỉ dùng nếu decode_exc=1 và không có fetch fault.
load_use_stall_raw|Hazard load-use trước khi phân xử với stall MEM và flush do lỗi/redirect.
id_can_advance|Cho phép ID tiến khi không halt, trap, stall hoặc sự kiện MEM/EX ưu tiên.
''')

def describe(module, name):
    local = SPECIFIC.get(module, {})
    base = re.sub(r'_(?:i|o)$', '', name)
    for key in (name, base):
        if key in local:
            return local[key]
    if name.endswith('_unused'):
        return 'Đầu ra phụ không sử dụng tại tầng này; nối tên riêng để thể hiện chủ đích.'
    for key in (name, base):
        if key in EXTRA:
            return EXTRA[key]
        if key in COMMON:
            return COMMON[key]
    # Prefixes here are architectural stage/registered-boundary names, not guesses.
    clean = re.sub(r'_q$', '', base)
    if clean in COMMON:
        return COMMON[clean]
    for prefix, stage in [('ifid_', 'IF/ID'), ('idex_', 'ID/EX'),
                          ('exmem_', 'EX/MEM'), ('memwb_', 'MEM/WB'),
                          ('id_', 'ID'), ('ex_', 'EX'), ('mem_', 'MEM'), ('wb_', 'WB')]:
        if clean.startswith(prefix) and clean[len(prefix):] in COMMON:
            return stage + ': ' + COMMON[clean[len(prefix):]]
    if clean == 'mem_stall':
        return 'MEM đang chờ data ready; giữ các tầng phía trước, WB cũ vẫn hoàn tất một lần.'
    return None

DECL = re.compile(r'^(\s*)(?:(?:\(\*.*?\*\))\s*)?'
                  r'(input|output|inout|wire|reg|integer|parameter)\s+'
                  r'(?:(?:wire|reg|signed|integer)\s+)*'
                  r'(?:\[[^\]]+\]\s*)?([A-Za-z_]\w*)')

def code_tokens(text):
    # Preserve strings exactly (including // in paths), remove only real comments.
    pieces = re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[^\s]', text)
    return [p for p in pieces if not p.startswith(('//', '/*'))]

def main():
    files = sorted((ROOT / 'rtl').rglob('*.v'))
    if BASELINE.exists():
        raise RuntimeError('Baseline exists; inspect before attempting another annotation pass')
    before = {str(p.relative_to(ROOT)): p.read_bytes().decode('utf-8') for p in files}
    after = {}
    missing_ports = []
    missing_vars = []
    total = 0
    for p in files:
        key = str(p.relative_to(ROOT))
        lines = []
        for line in before[key].splitlines(keepends=True):
            m = DECL.match(line)
            if m and '//' not in line:
                indent, kind, name = m.groups()
                if kind == 'parameter':
                    comment = PARAMS.get(name, PARAMS.get(name.removeprefix('QNN_')))
                else:
                    comment = describe(p.stem, name)
                if comment:
                    # Own line keeps long identifiers/widths readable and does not split syntax.
                    ending = '\r\n' if line.endswith('\r\n') else '\n'
                    lines.append(indent + '// ' + comment + ending)
                    total += 1
                elif kind in ('input', 'output', 'inout', 'parameter'):
                    missing_ports.append(f'{p.stem}.{name}')
                else:
                    missing_vars.append(f'{p.stem}.{name}')
            lines.append(line)
        after[key] = ''.join(lines)
        assert code_tokens(before[key]) == code_tokens(after[key]), key
    if missing_ports:
        print('MISSING REQUIRED COMMENTS:', *missing_ports, sep='\n')
        return
    BASELINE.write_text(json.dumps(before, ensure_ascii=False, indent=2), encoding='utf-8')
    for key, value in after.items():
        (ROOT / key).write_bytes(value.encode('utf-8'))
    print(f'Annotated {total} declarations in {len(files)} RTL modules; code tokens unchanged.')
    print('Internal declarations left for manual review:', *missing_vars, sep='\n')

if __name__ == '__main__':
    if '--verify' in sys.argv:
        before = json.loads(BASELINE.read_text(encoding='utf-8'))
        port_count = 0
        parameter_count = 0
        for key, original in before.items():
            current = (ROOT / key).read_text(encoding='utf-8')
            assert code_tokens(original) == code_tokens(current), key
            # Comments carrying synthesis directives must also remain exactly intact.
            directives = r'//[^\n]*(?:synthesis|synopsys|translate_off|translate_on)[^\n]*'
            assert re.findall(directives, original) == re.findall(directives, current), key
            previous = ''
            for line in current.splitlines():
                match = DECL.match(line)
                if match and match[2] in ('input', 'output', 'inout', 'parameter'):
                    assert previous.lstrip().startswith('//') or '//' in line, (key, line)
                    if match[2] == 'parameter':
                        parameter_count += 1
                    else:
                        port_count += 1
                previous = line
        print(f'PASS: {len(before)} RTL files retain identical non-comment code and synthesis directives.')
        print(f'PASS: {port_count} input/output/inout declarations (including function inputs) and '
              f'{parameter_count} parameters have adjacent comments.')
    else:
        main()
