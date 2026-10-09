# Tư duy thiết kế từng module và testbench

Tài liệu này giải thích **contract trước, code sau**. Khi đọc RTL, hãy luôn hỏi:
đầu vào nào hợp lệ, kết quả xuất hiện ở chu kỳ nào, stage nào sở hữu side effect,
và điều gì xảy ra ở góc biên.

Cấu trúc file hiện tại và đặc tả thanh ghi/timing được tập trung tại
[dac_ta_core_bus_ngoai_vi.md](dac_ta_core_bus_ngoai_vi.md). Các module con của
core được nhóm trong `if`, `id`, `ex`, `mem`, `wb`, `pipeline`, `control`, `common`.

## 1. `rv32_defs.vh`

Đây là nguồn duy nhất của các mã điều khiển ALU, immediate, operand source,
write-back và opcode. Việc dùng chung tránh lỗi decoder phát một mã nhưng ALU
hiểu theo bảng khác. Header chỉ chứa macro có độ rộng tường minh; nó không tạo
hardware.

## 2. `rv32_decoder`

Decoder là logic tổ hợp. Tư duy an toàn là bắt đầu mỗi lần đánh giá bằng trạng
thái `illegal=1`, toàn bộ side effect bằng 0; chỉ một encoding đã được chứng minh
hợp lệ mới mở `reg_write`, `load`, `store` hoặc control flow.

Decode hai lớp:

- opcode chọn họ lệnh;
- `funct3/funct7` phân biệt phép cụ thể và loại encoding reserved.

`uses_rs1/uses_rs2` là metadata cho pipeline, không phải ISA-visible state.
Testbench decoder đi qua đủ 40 lệnh baseline và các encoding dễ nhầm như M
extension, shift-immediate có funct7 sai, FENCE.I và Zicsr.

## 3. `rv32_imm_gen`

Immediate không nằm liên tục trong instruction đối với S/B/J. Module chỉ ghép
bit và mở rộng dấu; nó không cần biết mnemonic.

- I: `[31:20]`.
- S: `[31:25]` + `[11:7]`.
- B: `[31],[7],[30:25],[11:8],0`.
- U: `[31:12]` + 12 bit 0.
- J: `[31],[19:12],[20],[30:21],0`.

Default trả 0 để không suy diễn latch. Testbench dùng vector literal độc lập cho
biên dương/âm và bit bị đảo vị trí, thay vì sao chép y nguyên biểu thức RTL làm
reference model.

## 4. `rv32_regfile`

Mảng chỉ lưu x1..x31; x0 được tạo trực tiếp bằng hằng 0. Hai cổng đọc là tổ hợp,
cổng ghi ở cạnh lên. Reset đồng bộ xóa mảng để mô phỏng/tích hợp xác định.

Write-through bypass ưu tiên sau x0: nếu WB đang ghi đúng địa chỉ ID đọc, dữ liệu
mới đi thẳng ra cổng đọc. Đây không thay thế forwarding EX/MEM; nó chỉ giải quyết
khoảng cách WB→ID.

Trade-off FPGA: reset 31×32 bit và hai read port bất đồng bộ thường dùng flip-flop
và mux thay vì block RAM. Nếu tối ưu tài nguyên sau này, có thể thiết kế register
file RAM nhân đôi/đọc đồng bộ, nhưng timing pipeline và TB phải đổi theo.

Testbench dùng scoreboard, quét địa chỉ, overwrite, x0, hai cổng, bypass riêng và
đồng thời, reset thắng write, pattern biên và timeout.

## 5. `rv32_alu`

ALU không phát cờ carry/overflow vì RV32I dùng số học modulo 2^32. Điểm dễ sai:

- SRA và SLT phải cast `$signed`;
- SRL/SLTU giữ diễn giải unsigned;
- shift amount chỉ lấy 5 bit thấp;
- mã không hợp lệ phải có output xác định.

Testbench so trực tiếp với reference expression và phủ zero, wraparound, signed
extrema, mọi shift amount, so sánh hai chiều và mã reserved.

## 6. `rv32_branch_unit`

Module chỉ trả lời “taken hay không”, không tính target. Tách comparator khỏi
PC adder giúp contract nhỏ và dễ kiểm chứng. BEQ/BNE so bit; BLT/BGE dùng signed;
BLTU/BGEU dùng unsigned. Khi `branch_en=0` hoặc funct3 reserved, output bằng 0.

Testbench phủ taken/not-taken cho sáu loại, equality, min/max signed và khác biệt
signed-vs-unsigned.

## 7. `rv32_lsu`

LSU là bộ chuyển đổi giữa địa chỉ byte của ISA và bus word 32 bit:

1. lấy `addr[1:0]` làm lane;
2. căn địa chỉ bus xuống 4 byte;
3. dịch store data và tạo strobe;
4. dịch read word về bit thấp;
5. sign/zero extend theo funct3.

Misaligned được báo riêng. Store misaligned có strobe 0; load misaligned trả 0,
nhưng core phải dùng `misaligned_o` để trap, không được coi dữ liệu 0 là kết quả
hợp lệ.

Testbench quét bốn byte lane, hai halfword lane, signed/unsigned extension,
alignment và funct3 reserved.

## 8. `rv32_hazard_unit`

Hazard unit có hai nhiệm vụ độc lập:

- so rd của load ở EX với nguồn thật sự của lệnh ID để phát stall;
- so nguồn của lệnh EX với rd tại MEM/WB để chọn forwarding.

MEM được ưu tiên hơn WB vì gần hiện tại hơn. Load tại MEM không được forward qua
đường kết quả ALU; consumer đã được stall và nhận load từ WB. x0 bị loại khỏi
mọi phép so hazard.

Testbench tạo từng ma trận match/no-match, valid/write-enable, x0, source unused,
MEM-vs-WB priority và load tại MEM.

## 9. `rv32_core`

`rv32_core` chỉ kết nối năm tầng, ba module thanh ghi giữa tầng và
`rv32_pipeline_control`. Các dây `*_q` tại top cho phép theo dõi trạng thái
do module con giữ. Bộ điều khiển phân xử sự kiện theo tuổi lệnh.

| Module giữ trạng thái | Trách nhiệm |
|---|---|
| `rv32_id_ex_reg` | Chốt kết quả ID, chèn rỗng khi load-use, xóa khi có sự kiện già hơn; chốt lại toán hạng sau chuyển tiếp khi MEM chờ |
| `rv32_ex_mem_reg` | Chốt kết quả EX và ngoại lệ, giữ khi MEM chờ, xóa lệnh trẻ khi MEM lỗi |
| `rv32_mem_wb_reg` | Chốt kết quả/ngoại lệ MEM; xóa valid khi MEM chờ để WB cũ chỉ hoàn tất một lần |
| `rv32_if_stage` | Giữ PC, trạng thái dừng và yêu cầu chờ grant; điều phối chỗ đệm, yêu cầu và đáp ứng |
| `rv32_if_request_queue` | Giữ PC/cờ hủy của tối đa hai yêu cầu đã grant, chờ đáp ứng; hủy thắng phép ghi cờ khi thêm/lấy, còn số lượng và PC vẫn cập nhật |
| `rv32_if_fifo` | Giữ tối đa hai lệnh/ngoại lệ chờ ID; flush chỉ xóa số phần tử |

Ba module `*_reg` nằm trong `pipeline`, hai bộ đệm IF nằm trong `if`.
Việc chia module giữ nguyên các cạnh chốt và số tầng. Ba quy tắc quan
trọng nhất trong mã:

1. WB là nơi duy nhất commit register/retire/trap; store thực hiện tại MEM.
2. Khi MEM stall, EX/MEM giữ nguyên, ID/EX chỉ chốt lại hai toán hạng sau
   chuyển tiếp; MEM/WB cũ phải xóa valid sau commit để không retire lặp.
3. Lỗi MEM chặn EX/ID; lỗi hoặc đổi hướng tại EX chặn ID. Ưu tiên reset,
   trap WB, giữ và xóa nằm trong từng module giữ trạng thái, được liệt kê
   tại [giao tiếp nội bộ pipeline](giao_tiep_rtl_vi.md#5-giao-tiếp-nội-bộ-pipeline).

Hai instance LSU được dùng có chủ đích: instance tại EX chỉ kiểm alignment sớm;
instance tại MEM định dạng transaction/read data từ các giá trị đã chốt EX/MEM.

Integration test dùng instruction encoder trong testbench để tạo chương trình
không phụ thuộc compiler. Memory model chèn wait-state, scoreboard theo dõi
retirement/signature, đồng thời assertion kiểm request ổn định khi stalled.

## 10. Cách đọc một testbench

Mỗi testbench có bốn lớp:

1. DUT và clock/reset model.
2. Task/function tạo stimulus hoặc encoding.
3. Checker dùng so sánh case-inequality (`!==`) để bắt cả X/Z.
4. Manifest cuối test, `$fatal` khi sai và một timeout độc lập.

Không nên chỉ nhìn dòng `PASS`. Hãy đối chiếu danh sách case với contract module:
một testbench tốt phải có normal case, boundary, invalid/reserved và timing case.

## 11. Nguyên tắc khi mở rộng

- Thêm control bit phải cập nhật đồng thời defs, decoder, pipeline registers và TB.
- Side effect mới phải được gắn `valid` và bị khóa bởi exception/flush.
- Không sửa hazard bằng delay trong testbench; timing phải được biểu diễn bằng
  stage register, forwarding hoặc stall trong RTL.
- Mỗi bug integration nên được thu nhỏ thành một unit/directed regression trước
  khi sửa RTL để tránh tái phát.

## 12. Các module SoC và QNN

### `intel_sync_rom_1p`, `intel_sync_rom_2p`, `soc_rom_dp`, `soc_ram`

Các wrapper ROM tách backend mô phỏng khỏi backend tổng hợp: ModelSim dùng mảng
Verilog để testbench nạp vector trực tiếp; Quartus dùng `altsyncram` để khóa ánh
xạ vào M9K. `soc_rom_dp` tách grant và response ở cổng lấy lệnh, đạt một word
mỗi chu kỳ với latency một chu kỳ; cổng data vẫn dùng req/ready.
`soc_ram` hỗ trợ byte-enable và dùng chỉ số địa chỉ đúng độ rộng vật lý; nếu dùng
nguyên `addr[31:2]`, Quartus 20.1 có thể trải SRAM thành hàng chục nghìn FF/ALUT.

### `soc_gpio`, `soc_uart_tx`, `soc_timer`

Đây là các slave MMIO nhỏ. Mỗi module tự kiểm tra offset hợp lệ và byte strobe.
UART giữ `busy` cho đủ start + 8 data + stop bit. Timer cung cấp snapshot 64 bit;
firmware chỉ cần phần thấp cho chu kỳ 10 giây ngắn hơn thời gian wrap.

### `soc_i2c_master`

FSM tách mỗi bit thành pha kéo SCL thấp và pha nhả SCL cao. Khi nhả, FSM quan
sát `scl_i`, vì vậy slave được phép clock-stretch. Output là điều khiển open-drain,
không bao giờ chủ động lái mức 1. Testbench kiểm tra cả waveform chân và contract
MMIO, kể cả CMD wait-state khi busy.

### `qnn_soc_accelerator`

FSM tuần tự tái sử dụng MAC cho ba lớp. Lớp 1/2 xen kẽ FETCH và MAC để đáp ứng
ROM đồng bộ; STORE thực hiện ReLU, dịch và saturate. Testbench dùng trọng số thưa
để kết quả có thể tính độc lập bằng tay, đồng thời kiểm tra bảo vệ feature khi
busy và cờ done sticky.

### `rv32_soc` và `de10_lite_top`

`rv32_soc` chỉ làm tích hợp logic: nối core, `soc_bus` và slave. Decode vùng
địa chỉ và mux response nằm trong `rtl/bus/soc_bus.v`, có test độc lập.
`de10_lite_top` chỉ làm tích hợp vật lý: reset synchronizer, open-drain,
LED debug và pin board. Việc giữ hai lớp riêng giúp test SoC không phụ thuộc pad
primitive hay pin assignment.

## 13. Test ngoại lệ chuyên biệt

`tb_rv32_core_traps` dùng instruction latency một chu kỳ và data zero-wait,
bổ sung cho integration test có wait-state. Mỗi lần reset, testbench đưa đúng
một instruction gây cause 0, 1,
2, 3, 4, 5, 6, 7 hoặc 11, rồi kiểm tra `{cause, pc, instr}`, trạng thái halt
sticky và không có retire sai. Hai kiểu memory timing cùng tồn tại để tránh việc
core chỉ vô tình đúng với một loại slave.

`tb_rv32_core_ordering` bổ sung lỗi MEM thắng nhánh trẻ hơn, fetch lỗi sai đường
bị drain/bỏ và reset giữa store stalled. `tb_rv32_soc_mmio` đưa instruction
thật qua core và bus để kiểm access fault, vùng reserved, ghi RO và GPIO byte
lane. Các unit test GPIO/UART/timer/I²C và ROM/SRAM kiểm riêng timing, strobe,
reset; test I²C transaction dùng mô hình target theo chân, không đọc FSM DUT.

## 14. Kiểm thử giao tiếp lấy lệnh phiên bản 2.0

`tb_rv32_if_stage` kiểm tra luồng liên tục, thiếu grant, FIFO đầy, redirect khi
còn đáp ứng, hai lần redirect liên tiếp, lỗi lấy lệnh, giữ yêu cầu sai đường
chưa grant và reset khi còn giao dịch. Checker yêu cầu PC đúng thứ tự và
không có bubble bắt buộc trong luồng thẳng.

`tb_rv32_core_fetch` nối core với `soc_rom_dp` thật, chạy 32 lệnh ADDI phụ thuộc
liên tiếp rồi EBREAK. Scoreboard kiểm PC, thanh ghi, dữ liệu và khoảng cách
retirement đúng một chu kỳ sau khi pipeline đầy. Đây là phép đo CPI trạng thái
ổn định của chương trình thử, không phải CPI cho mọi chương trình.

`tb_rv32_soc_rom` kiểm latency instruction chính xác một chu kỳ, truy cập liên
tục, lỗi range/alignment, hai cổng hoạt động đồng thời và reset giao dịch chờ.
Quy tắc tích hợp chuẩn tắc nằm tại [giao_tiep_rtl_vi.md](giao_tiep_rtl_vi.md).

## 15. FIFO UART và phục hồi I²C (26/09/2026)

`tb_rv32_uart_fifo` kiểm tra waveform theo thứ tự byte đã được bus nhận,
FIFO đầy, push/pop cùng cạnh, wrap con trỏ, byte-enable, lỗi MMIO và reset.
Chế độ stress dùng divisor 1/7 và depth 1/3 ngoài mặc định divisor 4/depth 4.
`tb_rv32_uart_tx` tiếp tục kiểm tra chế độ tương thích `FIFO_DEPTH=0`.

`tb_rv32_i2c_recovery` kiểm tra SCL/SDA kẹt, timeout trả lỗi cho DATA/CMD
đang chờ, không thực hiện lệnh muộn, phục hồi tối đa 9 xung, chờ chân SCL/SDA
thực tế, short stretch, khoảng giữ bus giữa byte, strobes và reset. Chạy cùng
các cấu hình HALF_DIV/SYNC_INPUTS của stress I²C thông thường.

`tb_rv32_soc_mmio` có thêm chương trình kiểm tra lỗi timeout đi qua bus tới
trap CPU cause 7 tại đúng PC và không thực hiện store trẻ hơn.

## 16. P0/P1: registered bus, POR, UART RX

`tb_rv32_soc_bus` giữ quét 5 page và biên ROM/RAM, thêm wait 0/1/2/ngẫu nhiên,
error, request liên tiếp không hạ req, payload stability, one-hot, response đã
chốt, reset và đếm giao dịch slave để phát hiện duplicate/lost transaction.
Offset chưa định nghĩa nay được chuyển tới slave; `tb_rv32_soc_mmio` kiểm tra
fault và không alias trong page tại mức CPU, tổng 20 case.

`tb_rv32_core_bus_wait` ghép core thật với registered bus, kiểm WB operand còn
đúng qua memory stall, store forwarding, load-use, read/write RAM và MMIO tại
wait 0/1/2/ngẫu nhiên. Đợt P0/P1 này không sửa RTL core.

`tb_rv32_reset_controller` kiểm POR không cần cạnh KEY, POR_CYCLES=1/5,
release đồng bộ, state timer/QNN/UART/core sau POR và boot/reboot.

`tb_rv32_uart_rx` phát waveform 8N1, back-to-back, false start, framing/break,
overrun, W1C/byte-enable, reset giữa frame, 64 pattern và lệch baud ±3% ở
divisor 100. Stress thêm divisor 8/9, FIFO depth 1/3. `tb_rv32_uart_rx_fifo`
kiểm pop/push đồng thời ở full/empty, kể cả depth 1. `tb_rv32_soc_uart_rx`
kiểm pad → RX → FIFO → registered bus → CPU load → GPIO, pop đúng một lần.

QNN test giờ giữ feature write pending khi busy, xác nhận snapshot không đổi,
result vẫn 84 và feature mới được cập nhật sau handshake. Expectation cũ
“success nhưng bỏ write” được thay bằng contract đúng, không bỏ test đó.

## 17. Mốc đóng băng core, ISA và firmware INA228 ngày 27/09/2026

`scripts/run_isa.py` build 40 chương trình RV32UI upstream qua adapter trap-and-halt
và 25 chương trình exception/corner riêng; mỗi chương trình chạy 3 lịch chờ trên
`tb/core/isa/isa_core_harness.sv`. Tổng 195/195; không đưa harness cần plusargs này
vào cơ chế tự khám phá testbench mặc định. Danh sách đầy đủ ở `isa_verification_vi.md`.

`tb_rv32_firmware_e2e` chạy firmware C đã biên dịch: mặc định 25 mẫu giả, cửa sổ
20 mẫu tạo 6 kết quả. Scoreboard so 480 feature, kết quả QNN và byte chân UART.
Stress thêm `SENSOR_MODE=2`, `FAULT_MODE=0..7`, dùng target INA228 ở mức chân.
Các fixture trong `tb/soc/firmware_assets` được rebuild bằng
`scripts/run_firmware_tests.py`; không thay ảnh ROM board mặc định.

`tb/firmware/test_pipeline_ina228.c` kiểm vòng đệm, thiếu/gap mẫu, saturation,
signed quantization, ID/calibration/range/độ rộng register và đường lỗi driver.
Chạy host C bằng cùng script firmware, độc lập RTL.

Tại mốc này, ModelSim All+Stress có 32 testbench và 46 cấu hình kiểm thử tăng
cường = 78 lượt; Icarus mặc định 32 lượt. Đây là số liệu của mốc đóng băng,
không phải kết quả xác minh cho mỗi lần tách module về sau. Core SHA256 kiểm
bằng `scripts/check_core_freeze.py`.
