# Báo cáo hoàn thiện kiến trúc P0/P1

Chốt báo cáo: 27/09/2026. Triển khai theo bản yêu cầu người dùng đính kèm;
target MAX10 10M50DAF484C7G, 50 MHz, RV32I, Quartus/ModelSim 20.1.

**Kết quả:** xử lý QNN busy-write, đăng ký request/response data bus, thêm POR,
UART RX/FIFO, MMIO page 4 KiB và GPIO phần mềm 8 LED. Regression **69/69 PASS**,
full compile/fit thành công, timing **50 MHz PASS**. Fmax cuối **54,86 MHz**;
mục tiêu khuyến nghị trên 60 MHz chưa đạt.

## 1. Baseline, phạm vi và tính tương thích

Backup trước sửa: `tmp/architecture_p0p1_before_20260926.zip`, 93 file source,
test, cấu hình, tài liệu và báo cáo. Hash gốc tại
`tmp/architecture_p0p1_before_manifest.json`. Toàn bộ file RTL dưới `rtl/core/`
được kiểm tra giữ nguyên từng byte: không đổi ISA, pipeline, forwarding,
load-use, LSU, trap-and-halt, fetch credit hay xử lý wrong-path.

Không thêm AXI/AHB/Wishbone, cache/MMU, DMA, RV32M/C, CSR hay interrupt vào CPU.
Timer snapshot/compare/irq_o và I²C open-drain/timeout/recovery giữ nguyên logic
chức năng; chỉ mở rộng offset ngoại vi từ 4 lên 12 bit để tránh alias.

Những thay đổi contract có chủ đích:

- Data bus có clock và payload store, thêm thanh ghi request/response. Core
  vẫn giữ request tới `req && ready`. Slave zero-wait: chụp tại N, commit tại
  N+1, CPU hoàn tất tại N+2; request kế sớm nhất chụp N+3. Một outstanding,
  không phải bus cho nhiều transaction pipeline đồng thời. RAM/ROM giữ latency
  nội bộ; CPU nhận đáp ứng sau 4 clock tính từ cạnh bus chụp request.
- QNN feature write lane0 và CONTROL.START lúc busy phải chờ. Test cũ từng
  chấp nhận “bỏ write khi busy” được sửa để kiểm đúng handshake và dữ liệu.
- Mỗi MMIO nhận page 4 KiB, giữ nguyên base; slave nhận đủ offset 12 bit,
  offset chưa định nghĩa vẫn fault. Ghi RO fault kể cả zero-strobe.
- GPIO mặc định 8 bit đúng LEDR[7:0]; LEDR[8]=QNN_BUSY, LEDR[9]=CPU_TRAP.
  Module GPIO vẫn cấu hình được width 10 và có test riêng giữ coverage cũ.
- SoC thêm `uart_rx_i`; test/tích hợp không dùng RX phải nối idle=1. STATUS
  UART thêm bit RX, reset từ `0x01` thành `0x09`; hai bit TX giữ ý nghĩa cũ.
  `soc_uart_tx` và test TX/FIFO trước đây giữ nguyên.

## 2. Thay đổi từng file RTL và cấu hình

| File | Thay đổi và lý do | Ảnh hưởng protocol / timing |
|---|---|---|
| `rtl/accelerator/qnn_soc_accelerator.v` | Ghi chỉ khi handshake; feature/START chờ busy, chặn reset, sửa chú thích | Không silent loss; giữ snapshot QNN, thêm wait-state có nghĩa |
| `rtl/bus/soc_bus.v` | Request register, ACCESS, response register; chọn một slave | Cắt đường tổ hợp từ payload CPU qua slave quay về CPU; tăng latency data |
| `rtl/bus/soc_map.vh` | Tất cả MMIO là page 4 KiB | Decoder dùng phần địa chỉ page, offset do slave kiểm tra |
| `rtl/soc/rv32_soc.v` | Slave dùng payload đã chốt; nối wrapper UART RX/TX, offset 12 bit, GPIO width | Handshake CPU/IF không đổi; interface tích hợp thay đổi như mục 1 |
| `rtl/board/reset_controller.v` (mới) | POR_CYCLES và chuỗi nhả reset đồng bộ | Khởi động xác định; POR mặc định 1024+3 clock, KEY assert async/release sync |
| `rtl/board/de10_lite_top.v` | Nối POR, UART_RX và 8 GPIO LED | Thêm chân RX; I²C vẫn chỉ lái 0/Z, không thay đường dữ liệu core |
| `rtl/peripherals/soc_gpio.v` | GPIO_LED_WIDTH=8; cập nhật các bit có thực theo strobe, offset 12 bit | Thanh ghi đọc đúng số LED phần mềm; không mirror page |
| `rtl/peripherals/soc_i2c_master.v` | Offset 12 bit, header contract | FSM/timeout/recovery giữ nguyên; offset cao trả fault |
| `rtl/peripherals/soc_timer.v` | Offset 12 bit, header contract | Counter/snapshot/compare/IRQ giữ nguyên; offset cao trả fault |
| `rtl/peripherals/uart/uart_rx.v` (mới) | Đồng bộ 2 FF, nhận giữa bit 8N1, phát valid/lỗi một clock | Tách async pin khỏi bus; cần >=8 clock/bit, không dùng oversampling 16x |
| `rtl/peripherals/uart/uart_rx_fifo.v` (mới) | FIFO logic mặc định 16 byte, pointer wrap bất kỳ depth | Pop/push full cùng cạnh không mất byte; overrun drop-new |
| `rtl/peripherals/uart/soc_uart.v` (mới) | Wrapper TX cũ + RX/FIFO, status/error W1C | RX_DATA pop tại handshake đúng một lần; read empty/write RO/offset sai fault |
| `quartus/riscv_soc.qsf` | Thêm source POR/UART RX và PIN_W9 RX/pull-up | NativeLink có đủ RTL; thêm một pad RX, TX pin giữ nguyên |
| `quartus/riscv_soc.sdc` | False path riêng UART_RX → FF meta đầu tiên | Vẫn kiểm timing FF meta → FF sync và logic nội bộ, không nới clock 50 MHz |
| `firmware/include/soc_map.h` | Tên bit RX/W1C, GPIO width/mask, page size | Firmware có thông tin contract mới; không thay binary ROM demo |
| `scripts/run_tests.ps1` | Stress RX divisor/depth, FIFO depth 1, GPIO width 10 | Thêm coverage; không thay synthesis |
| `scripts/report_bus_timing.tcl` (mới) | Xuất setup/hold/Fmax vào thư mục chỉ định | Chỉ báo cáo post-fit, không sửa constraint. Script report_timing.tcl cũ giữ nguyên |

Header các module mới/chỉnh sửa mô tả purpose, clock/reset, inputs/outputs,
protocol, latency và error. Không thêm delay mô phỏng vào RTL. POR dùng giá trị
khởi tạo FF được Quartus tổng hợp thành power-up condition, phù hợp MAX10;
xem [Intel MAX 10 Device Handbook](https://www.intel.com/programmable/technical-pdfs/max10-handbook.pdf).

RX dùng PIN_W9 (JP1 GPIO[3]), TX PIN_V9 (JP1 GPIO[2]), theo
[Terasic DE10-Lite User Manual, bảng 3-7](https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/73/DE10_2D00_Lite_5F00_User_5F00_Manual.pdf).

## 3. File test và tài liệu

Mọi file test/tài liệu trong bảng này không ảnh hưởng logic tổng hợp/timing.

| File | Nội dung thay đổi / mục đích |
|---|---|
| `tb/accelerator/tb_rv32_qnn_soc_accelerator.v` | Giữ write khi busy, kiểm không success giả, snapshot và kết quả 84; ghi mới cập nhật khi rảnh |
| `tb/bus/tb_rv32_soc_bus.v` | 5.268 giao dịch địa chỉ/stress, one-hot/stability/registered response, không duplicate/lost, reset |
| `tb/peripherals/tb_rv32_gpio.v` | Kỳ vọng width=8, chạy thêm width=10, thử offset cao không alias |
| `tb/peripherals/tb_rv32_i2c_master.v` | Địa chỉ TB/task 12 bit; giữ test byte/ACK/NACK |
| `tb/peripherals/tb_rv32_i2c_recovery.v` | Địa chỉ TB/task 12 bit; giữ test timeout/recovery/strobes |
| `tb/peripherals/tb_rv32_i2c_transactions.v` | Địa chỉ TB 12 bit; giữ waveform repeated START/stretch/read/write |
| `tb/peripherals/tb_rv32_timer.v` | Địa chỉ TB/task 12 bit; giữ snapshot/rollover/strobes/IRQ |
| `tb/peripherals/tb_rv32_uart_rx.v` (mới) | Waveform RX, flags, MMIO, W1C, overflow, mismatch, reset |
| `tb/peripherals/tb_rv32_uart_rx_fifo.v` (mới) | Pop/push tại full/empty, thứ tự và depth=1/3 |
| `tb/soc/tb_rv32_core_bus_wait.v` (mới) | Core thật + registered bus: WB operand qua stall, forwarding, load-use, RAM/MMIO |
| `tb/soc/tb_rv32_reset_controller.v` (mới) | POR không cần KEY, tham số biên, state SoC và boot/reboot |
| `tb/soc/tb_rv32_soc.v` | Nối RX idle, width LED mới; giữ chương trình và golden result QNN/UART TX |
| `tb/soc/tb_rv32_soc_mmio.v` | 20 case CPU/bus/MMIO, thêm reserved page, RX empty/RO, QNN RO, không alias |
| `tb/soc/tb_rv32_soc_uart_rx.v` (mới) | Pad → RX/FIFO → bus → CPU → GPIO; đúng một lần pop |
| `README.md` | Tính năng, số test, pin và số liệu build cuối |
| `docs/dac_ta_core_bus_ngoai_vi.md` | Đặc tả 3.0: latency bus, MMIO/RX/POR/GPIO/QNN |
| `docs/giao_tiep_rtl_vi.md` | Contract registered bus, timing diagram và migration |
| `docs/module_va_testbench_vi.md` | Chỉ dẫn test mới và phạm vi regression |
| `docs/soc_qnn_de10_lite_vi.md` | Bỏ mô tả sai “START busy bị bỏ qua” |
| `docs/hoc_hoi_soc_cnn_driver_vi.md` | Đánh dấu báo cáo lịch sử, dẫn sang phiên bản hiện tại |
| `docs/bao_cao_xac_minh_vi.md` | Bổ sung kết quả P0/P1 ở mục 10 |
| `docs/bao_cao_kien_truc_p0_p1_vi.md` (mới) | Báo cáo này: quyết định, file, kiểm thử, timing, giới hạn |

## 4. Verification

Lệnh: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress`.
Kết quả cuối: **69/69 PASS**, 31 testbench + 38 lượt stress. Log tổng:
`tmp/p0p1_final_regression.log`; log từng cấu hình ở `sim/modelsim/work/`.

- Core/hazard/LSU/trap/fetch cũ đều PASS; 16 seed timing core vẫn giữ signature.
- Bus mới kiểm wait 0/1/2/3+ và ngẫu nhiên, read/write RAM/MMIO, errors,
  transaction liên tiếp giữ req, ổn định addr/we/wdata/wstrb, one-hot và reset.
- Core + bus: 4 chế độ wait, 6 giao dịch mỗi chương trình, giữ được x1=42,
  x2=x3=43 và x4=x5=86; store side effects đúng số lượng và giá trị.
- QNN: feature cũ giữ 3 khi busy, kết quả 84; feature mới 9 được ghi sau ready.
- UART RX: divisor 8/9/100, FIFO depth 1/3; 64 pattern nhận, +/-3% chu kỳ bit
  ở divisor 100; false-start/framing/break/overrun, back-to-back, W1C/strobes,
  reset đang nhận. SoC test xác nhận CPU poll rồi nhận `0xA6`, ghi GPIO và pop
  đúng một lần qua registered bus.
- UART TX/FIFO cũ, I²C, timer, GPIO, QNN model và full SoC đều PASS.
  Full SoC giữ 10 checks; 2.896 clock đến trap trong chương trình thử.
- POR test không tạo cạnh KEY lúc bật, vẫn reset đúng timer compare, QNN,
  UART/core; sau nhả reset CPU boot và sau KEY reboot được.

Danh sách PASS từng testbench và 38 cấu hình stress có đầy đủ trong log tổng;
không dùng mô phỏng source ZIP tham khảo làm bằng chứng cho RTL mới.

```text
PASS tb_rv32_alu
PASS tb_rv32_branch_unit
PASS tb_rv32_core
PASS tb_rv32_core_bus_wait
PASS tb_rv32_core_fetch
PASS tb_rv32_core_ordering
PASS tb_rv32_core_traps
PASS tb_rv32_decoder
PASS tb_rv32_gpio
PASS tb_rv32_hazard_unit
PASS tb_rv32_i2c_master
PASS tb_rv32_i2c_recovery
PASS tb_rv32_i2c_transactions
PASS tb_rv32_if_stage
PASS tb_rv32_imm_gen
PASS tb_rv32_lsu
PASS tb_rv32_qnn_model
PASS tb_rv32_qnn_soc_accelerator
PASS tb_rv32_regfile
PASS tb_rv32_reset_controller
PASS tb_rv32_soc
PASS tb_rv32_soc_bus
PASS tb_rv32_soc_mmio
PASS tb_rv32_soc_ram
PASS tb_rv32_soc_rom
PASS tb_rv32_soc_uart_rx
PASS tb_rv32_timer
PASS tb_rv32_uart_fifo
PASS tb_rv32_uart_rx
PASS tb_rv32_uart_rx_fifo
PASS tb_rv32_uart_tx
```

## 5. Quartus và timing trước/sau

Giữ nguyên thiết bị, clock constraint 20 ns, firmware/model khởi tạo và
Quartus 20.1. Fmax lấy trực tiếp bảng Fmax Summary slow 1200 mV/85°C;
slack hold là giá trị nhỏ nhất qua cả ba corner, không lấy nhầm một corner.

| Chỉ số | Trước P0/P1 | Sau P0 + POR | P0/P1 cuối |
|---|---:|---:|---:|
| Fmax slow 85°C | 54,79 MHz | 54,10 MHz | **54,86 MHz** |
| Worst setup | +1,750 ns | +1,517 ns | **+1,772 ns** |
| Worst hold | +0,119 ns | +0,103 ns | **+0,097 ns** |
| Logic elements | 6.074 | 6.066 | **6.353 / 49.760 (13%)** |
| Registers | 2.888 | 3.002 | **3.184** |
| Memory bits | 338.944 | 338.944 | **338.944** |
| Multiplier 9-bit | 3 | 3 | **3 / 288** |
| Compile | PASS | PASS | **0 errors / 14 warnings** |

Setup/hold fully constrained theo SDC hiện tại. Recovery/removal cũng có slack
dương. Tài nguyên cuối tăng 279 LE và 296 register so với baseline trước P0/P1;
FIFO RX dùng logic, không thêm memory bit hay multiplier.

**Không kết luận bus mới nâng Fmax đáng kể.** Chênh lệch 54,79 → 54,86 MHz rất
nhỏ và phụ thuộc placement. Mục tiêu mandatory 50 MHz đạt; mục tiêu >60/70 MHz
chưa đạt. Path chậm nhất cuối đi từ `u_core|memwb_exc_valid_q` tới read-enable
ROM instruction `ram_block1a6~porta_re_reg` (setup +1,772 ns), không còn đường
response MMIO tổ hợp xuyên qua slave về IF. Không viết lại fetch/hazard để ép
Fmax khi chưa có thay đổi timing được kiểm chứng riêng.

Log build: `tmp/p0p1_quartus.log`. Báo cáo fitter/STA cuối ở
`quartus/output_files/riscv_soc.fit.summary`, `.sta.summary`, `.sta.rpt`.
Đã chạy script report_timing.tcl cho setup/hold top20 cả ba corner; các file
`riscv_soc_*_top20.rpt` đã cập nhật. Báo cáo đọc nhanh tại
`tmp/p0p1_timing/{setup_paths,hold_paths,fmax}.rpt`. Báo cáo P0 riêng ở
`tmp/p0_{fit,sta}.summary`, `tmp/p0_sta.rpt`, `tmp/p0_timing/`.

14 warnings còn lại thuộc nhóm ROM QNN không dùng cổng ghi, KEY[1] không dùng,
RAM suy luận thành ROM, LogicLock license, I/O assignment và yêu cầu điện
LVTTL. Không còn warning truncation mới hoặc RAM pass-through RX FIFO.

## 6. Known limitations / TODO

- Chưa đạt Fmax >60 MHz. Bước timing tiếp theo nên phân tích riêng đường
  exception/redirect → fetch/ROM, giữ nguyên precise trap và outstanding credit.
- UART RX lấy mẫu giữa bit, không có 16x/majority voting. Các test mismatch
  không thay kiểm tra jitter/nhiễu/tín hiệu điện thực tế. Lỗi RX sticky ở mức
  peripheral, không gắn metadata lỗi cho từng byte; frame lỗi bị loại.
- Chưa thử board hoặc GUI NativeLink. QSF NativeLink đã có đủ source và
  testbench SoC; regression dùng chính ModelSim CLI. Chưa chạy lại Icarus.
- Header C qua kiểm tra `gcc -std=c11 -ffreestanding -Wall -Wextra -Werror
  -fsyntax-only firmware/main.c`; chưa cross-build RISC-V hay đổi ROM demo.
- POR dựa trên power-up FF MAX10/Quartus và clock hoạt động; không thay mạch
  giám sát nguồn/brown-out. Mô phỏng synchronizer không chứng minh metastability.
- Reset toàn hệ thống có thể hủy response đã pending nhưng không rollback
  ghi đã xảy ra tại slave. Bus một outstanding làm tăng latency load/store.
- Chưa có machine-mode CSR/interrupt subsystem, UART IRQ/DMA, multi-master
  I²C hoặc ISA/formal certification. Các phần này thuộc phase sau như yêu cầu.

## 7. Tái lập

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
cd quartus
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe' --flow compile riscv_soc
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sta.exe' -t ../scripts/report_timing.tcl
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sta.exe' -t ../scripts/report_bus_timing.tcl ../tmp/p0p1_timing
```
