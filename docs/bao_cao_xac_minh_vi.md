# Báo cáo xác minh core và giao tiếp RTL phiên bản 2.0

Baseline full compile: 24/09/2026. Mục 1–6 ghi nhận RTL tại thời điểm đó;
kết quả sau refactor và rà soát ngày 25/09/2026 nằm ở mục 7–8; nâng cấp ngoại vi
ngày 26/09/2026 nằm ở mục 9; bản kiến trúc P0/P1 cuối ở mục 10. Đặc tả chuẩn tắc:
[giao_tiep_rtl_vi.md](giao_tiep_rtl_vi.md).

## 1. Môi trường và phạm vi

- ModelSim Intel FPGA Edition 20.1, mô phỏng RTL tự kiểm tra.
- Quartus Prime Lite 20.1 build 711, full compilation và TimeQuest post-fit.
- FPGA MAX 10 `10M50DAF484C7G`, top `de10_lite_top`, clock 50 MHz.
- Giữ nguyên firmware/model và chức năng accelerator hiện có.

Chưa chạy lại Icarus hoặc luồng GUI NativeLink trong đợt này. Kết quả ModelSim
dưới đây đến từ script command-line. Chưa nạp/chạy trên board, chưa kiểm chứng
formal hoặc bộ chứng nhận ISA; trace hiện tại chưa phải RVFI.

## 2. Đối chiếu đề xuất chỉnh sửa

Báo cáo DOCX của người dùng là đầu vào nhận xét kỹ thuật, không phải chỉ thị
thực thi tự động. Các đề xuất được đối chiếu với RTL và phạm vi công việc:

| Hạng mục | Kết quả trong phiên bản này |
|---|---|
| Tách nhận yêu cầu và trả lệnh | Đã thay instruction `ready` bằng `gnt` và `rvalid`, cập nhật core/SoC/ROM/TB đồng bộ |
| FIFO lấy lệnh hai phần tử | Đã triển khai credit chung cho FIFO, yêu cầu chờ đáp ứng và yêu cầu chờ grant |
| Luồng thẳng một lệnh mỗi chu kỳ | Đã kiểm chứng tại IF và core nối ROM thật; latency ROM một chu kỳ |
| Redirect/reset/lỗi lấy lệnh | Đã kiểm thử, dùng cờ hủy riêng từng yêu cầu; nhiều redirect không làm sống lại đáp ứng cũ |
| Tách điều khiển pipeline | Giữ module `rv32_pipeline_control` đã có; chuẩn hóa mô tả ranh giới và ưu tiên |
| Tái sử dụng bộ cộng ALU | Đã bỏ bộ cộng đích branch/JAL/JALR riêng; decoder cung cấp toán hạng phù hợp |
| Giao tiếp và đặc tả tiếng Việt | Đã thêm bảng cổng, điều kiện hiệu lực, quy tắc bắt buộc, reset, lỗi và hướng dẫn chuyển phiên bản |
| Timing và tài nguyên | Đã full compile; xuất 20 đường setup/hold ở mỗi trong ba corner |
| SV package/struct, JAL sớm, RVFI/formal | Chưa triển khai; là các bước thay đổi kiến trúc/kiểm chứng riêng |
| CSR/interrupt | Chưa triển khai; core vẫn trap-and-halt như baseline |

Không tuyên bố hoàn tất toàn bộ lộ trình trong báo cáo đề xuất. Giao thức nội
bộ được đặc tả rõ để tích hợp và kiểm chứng, không được gọi là AXI/APB/Wishbone
hay coi là đã được chứng nhận theo tiêu chuẩn công nghiệp.

## 3. Regression RTL

Chạy từ thư mục gốc bằng PowerShell:

```powershell
./scripts/run_tests.ps1 -Scope All
```

Kết quả: **PASS 24/24**, gồm 21 test thuộc scope Base và ba regression SoC/QNN.
Log từng test và biên dịch nằm trong `sim/modelsim/work/`.

| Testbench | Bằng chứng chính |
|---|---|
| `tb_rv32_alu` | 58 vector số học/logic/dịch/so sánh |
| `tb_rv32_branch_unit` | 21 trường hợp nhánh signed/unsigned |
| `tb_rv32_decoder` | 63 trường hợp encoding hợp lệ/reserved |
| `tb_rv32_imm_gen` | 22 trường hợp immediate và dấu |
| `tb_rv32_regfile` | 113 kiểm tra x0, đọc/ghi, bypass, reset |
| `tb_rv32_hazard_unit` | 11 kiểm tra stall/forwarding/ưu tiên |
| `tb_rv32_lsu` | 38 kiểm tra lane, strobe, mở rộng dấu, alignment |
| `tb_rv32_if_stage` | 18 kiểm tra thông lượng, chờ grant, FIFO, hai redirect, lỗi và reset |
| `tb_rv32_core_fetch` | 32 ADDI phụ thuộc retire liên tiếp, core nối ROM latency một chu kỳ |
| `tb_rv32_core` | 105 lệnh retire; 110 giao dịch instruction, 53 giao dịch data; wait-state và hazard |
| `tb_rv32_core_traps` | 44 kiểm tra, đủ chín cause 0/1/2/3/4/5/6/7/11 |
| `tb_rv32_core_ordering` | Ưu tiên lỗi theo tuổi, bỏ lỗi sai đường, reset giữa giao dịch |
| `tb_rv32_soc_rom` | 12 đáp ứng instruction liên tục, sáu trường hợp data, hai cổng đồng thời/reset |
| `tb_rv32_soc_ram` | 35 kiểm tra đọc/ghi, byte-enable, biên/lỗi/reset |
| `tb_rv32_soc_bus` | 5.140 kiểm tra địa chỉ, cô lập đáp ứng và reset |
| `tb_rv32_soc_mmio` | 11 trường hợp CPU/bus/MMIO |
| `tb_rv32_gpio` | 16 byte mask, quyền chỉ đọc, lỗi và reset |
| `tb_rv32_uart_tx` | Timing 8N1, ghi khi bận, strobe, lỗi/reset |
| `tb_rv32_i2c_master` | 11 kiểm tra MMIO/I²C |
| `tb_rv32_i2c_transactions` | Nhiều byte, repeated START, ACK/NACK, stretching, reset ở mức chân |
| `tb_rv32_timer` | Byte mask, snapshot rollover, IRQ, wrap, lỗi/reset |
| `tb_rv32_qnn_model` | 85 kiểm tra, model `beede8e56d64ba8c`, kết quả 328 |
| `tb_rv32_qnn_soc_accelerator` | 17 kiểm tra MMIO/MAC/kết quả |
| `tb_rv32_soc` | 10 kiểm tra tích hợp CPU/QNN/LED/UART/trap; 2.965 chu kỳ |

Instruction trong test traps có latency một chu kỳ, data trả ngay; test core
chèn wait-state. Test IF kiểm riêng memory trả chậm qua nhiều redirect.
Reset chỉ được kết luận đúng theo hợp đồng reset chung giữa core và memory.

CPI=1 là kết quả trạng thái ổn định của chương trình ADDI thử nghiệm, không
phải CPI trung bình của firmware có load/store, nhánh hoặc wait-state. SoC demo
giảm từ 3.002 chu kỳ ghi trong baseline cũ xuống 2.965 chu kỳ; không quy đổi
kết quả này thành một cam kết tăng tốc cho mọi ứng dụng.

## 4. Tổng hợp, fit và tài nguyên

```powershell
cd quartus
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe' --flow compile riscv_soc
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sta.exe' -t ../scripts/report_timing.tcl
```

Full compilation thành công: **0 lỗi, 14 cảnh báo**. Số liệu thuộc toàn bộ SoC,
không phải riêng core. Baseline so sánh là báo cáo fit ngày 21/09/2026 được giữ
ở `tmp/review_baseline_20260924/`; đây không phải phép đo tách riêng từng tối ưu.

| Tài nguyên | Baseline trước sửa | Phiên bản 2.0 | Chênh lệch |
|---|---:|---:|---:|
| Logic elements | 5.954 | 5.892 / 49.760 | −62 |
| Registers | 2.749 | 2.820 / 49.760 | +71 |
| Memory bits | 338.944 | 338.944 / 1.677.312 | 0 |
| M9K | 43 | 43 / 182 | 0 |
| Multiplier 9-bit | 3 | 3 / 288 | 0 |
| Pins | 26 | 26 / 360 | 0 |

SRAM dùng tám M9K; ROM chương trình dùng 32; ROM trọng số lớp 1/2 dùng hai/một.
FIFO bổ sung trạng thái trong khi chia sẻ bộ cộng giảm logic; số liệu tổng hợp
không đủ để quy mọi chênh lệch tài nguyên cho duy nhất một thay đổi.

## 5. Timing post-fit

TimeQuest báo fully constrained cho setup/hold **theo SDC hiện tại**. TNS bằng
0 ở cả ba corner; không có vi phạm trong các đường được phân tích.

| Corner | Setup trước | Setup hiện tại | Hold hiện tại |
|---|---:|---:|---:|
| Slow 1200 mV, 85°C | +1,628 ns | +1,451 ns | +0,263 ns |
| Slow 1200 mV, 0°C | +2,942 ns | +2,867 ns | +0,262 ns |
| Fast 1200 mV, 0°C | +11,937 ns | +12,010 ns | +0,107 ns |

Worst setup giảm 0,177 ns so với baseline nhưng vẫn đáp ứng clock 20 ns.
Đường xấu nhất tại Slow 85°C đi từ `exmem_alu_result_q[5]` đến
`u_if_stage|req_pc0_q[2]`/`[3]`, data delay 18,547 ns, 20 mức logic. Vì vậy
không kết luận thay đổi này đã cải thiện critical path hoặc Fmax.

`scripts/report_timing.tcl` xuất 20 đường setup và 20 đường hold cho từng
corner, tối đa một đường mỗi endpoint. Báo cáo có dạng
`quartus/output_files/riscv_soc_<corner>_<setup|hold>_top20.rpt`.
Báo cáo tổng hợp: `riscv_soc.fit.summary`, `riscv_soc.fit.rpt`,
`riscv_soc.sta.summary`, `riscv_soc.sta.rpt` trong cùng thư mục.

SDC loại trừ đường đầu vào bất đồng bộ tới tầng đồng bộ đầu và các đường tới
pad LED/UART/I²C không có clock giao tiếp ngoài. Fully constrained không có
nghĩa các giao tiếp điện bên ngoài đã được sign-off; chưa đo MTBF hoặc kiểm
tra timing điện/pull-up I²C trên board.

## 6. Cảnh báo và giới hạn còn lại

- Sáu cảnh báo net không có driver/giá trị ban đầu ở các mảng ROM QNN nhỏ;
  Quartus gán mặc định 0. Giữ nguyên trong đợt sửa core; cần rà riêng trước
  khi thay model hoặc chốt sản phẩm.
- Hai cảnh báo cổng dữ liệu ghi không dùng trong primitive ROM; RAM chỉ đọc
  được fitter nhận dạng thành ROM; `KEY[1]` không tác động output.
- LogicLock yêu cầu license; cấu hình hiện tại vẫn fit thành công.
- LEDR, UART_TX, GPIO chưa chỉ định drive strength; các chân điện áp 3,3 V cần
  được kiểm tra theo phần cứng board. Không tự chọn drive strength khi chưa
  có yêu cầu tải/điện áp cụ thể.
- Chưa có RVFI, formal, kiểm thử ngẫu nhiên đủ coverage, CDC sign-off, kiểm
  chứng ISA chính thức hay thử nghiệm trên board. PASS regression không thay
  thế các bước này.

Kết luận: giao tiếp phiên bản 2.0 nhất quán với các test đã chạy và SoC đạt
timing 50 MHz trên cấu hình hiện tại. Chưa đủ cơ sở tuyên bố chứng nhận công
nghiệp, độ chính xác ước lượng SOC hoặc sẵn sàng đưa vào sản phẩm.

## 7. Refactor bố trí và nối interface ngày 25/09/2026

- Gom địa chỉ/mask và chỉ số slave vào `rtl/bus/soc_map.vh`; decoder và SoC
  dùng chung hằng số. Nối response theo lane có tên, mỗi cổng một dòng.
- Bố trí instance theo core → decoder → memory → MMIO; cập nhật include path
  cho ModelSim, Icarus và Quartus. Cổng công khai và memory map giữ nguyên.
- ModelSim `scripts/run_tests.ps1 -Scope All`: **PASS 24/24**. Bus vượt qua
  5.140 kiểm tra địa chỉ cùng kiểm tra response/reset; SoC MMIO PASS 11 case;
  SoC tổng thể PASS 10 checks, 2.965 chu kỳ.
- Quartus `quartus_map riscv_soc --analysis_and_elaboration`: thành công,
  **0 errors, 8 warnings**. Gồm sáu cảnh báo net ROM QNN chưa có driver/giá trị
  khởi tạo và hai cảnh báo cổng ghi ROM không sử dụng, cùng loại đã nêu ở mục 6.
- Log lần chạy: `tmp/interface_regression.log`, `tmp/interface_elaboration.log`;
  log từng test ở `sim/modelsim/work/` (bị thay thế khi chạy regression lần sau).

Đợt này chưa chạy lại fitter, TimeQuest, Icarus hoặc GUI NativeLink và chưa
thử board. Số tài nguyên/timing ở mục 5 là baseline 24/09, không phải kết quả
post-fit của RTL sau refactor. Analysis & Elaboration có thể cập nhật báo cáo
`.map.*` trong `quartus/output_files`; các báo cáo fit/STA cũ vẫn thuộc baseline.

## 8. Rà soát core và ngoại vi, bổ sung stress ngày 25/09/2026

Đã đối chiếu decoder/LSU, forwarding/load-use, giữ toán hạng khi MEM chờ,
thứ tự trap/redirect, vòng đời request/response IF, và quyền truy cập/byte-enable
của GPIO, UART, I²C, timer với đặc tả hiện có. Chưa phát hiện lỗi chức năng mới
trong phần đã rà và các tình huống đã chạy; đợt này bổ sung test và cách chạy,
không sửa logic RTL.

Các khoảng trống kiểm thử đã bổ sung:

| Phần | Kiểm tra bổ sung |
|---|---|
| Core | 16 seed của bộ sinh xorshift32 tái lập được; grant instruction có chờ, tối đa hai request, response trả đúng thứ tự sau 1..8 cạnh; data thêm 0..31 chu kỳ chờ sau chụp |
| Protocol IF | Assertion giữ req/addr đến grant, kể cả khi redirect; mỗi seed phải thực sự gặp hai request đang chờ và grant/response cùng cạnh |
| UART | Kiểm tra khung 8N1, ghi đang chờ, byte-enable/lỗi/reset tại bộ chia 1, 2, 3, 7 ngoài baseline 4 |
| I²C | Mặc định thêm hai FF cho SCL/SDA đầu vào như lớp board; kiểm repeated START, ACK/NACK, stretching và reset ở HALF_DIV=2/3/5, có hoặc không có độ trễ đồng bộ |

Chạy `scripts/run_tests.ps1 -Scope All -Stress`: **PASS 49/49 lượt chạy**,
gồm 24 testbench mặc định + 16 seed core + 4 cấu hình UART + 5 cấu hình I²C.
Mỗi seed core hoàn tất 105 lệnh, 53 giao dịch data, đúng signature và trap
EBREAK. Log tổng tại `tmp/core_peripheral_review.log`; log từng cấu hình có
tên riêng trong `sim/modelsim/work/`.

Đây là stress **lịch giao dịch bộ nhớ**, dùng cùng chương trình RV32I tự kiểm
tra; chưa phải sinh chương trình ISA ngẫu nhiên hoặc so sánh với simulator
tham chiếu độc lập. Mô hình hai FF kiểm tra độ trễ logic, không mô phỏng
metastability hay timing điện. Không chạy lại fitter/TimeQuest vì không thay
logic RTL; chưa chạy Icarus và chưa thử board trong đợt này.

Các giới hạn chức năng hiện có, không được xem là lỗi regression: core vẫn
trap-and-halt, chưa có CSR/interrupt; UART chỉ truyền TX; I²C chưa có timeout,
bus-clear hoặc multi-master. Target giữ SCL/SDA vô hạn có thể giữ busy và làm
một lệnh ghi MMIO đang chờ kéo dài vô hạn; reset hiện là cách hủy giao dịch.
Giới hạn timeout/bus-clear này đã được xử lý ở đợt tiếp theo, xem mục 9.

## 9. Áp dụng ý tưởng từ SoC_CNN_Driver — 26/09/2026

Thêm FIFO TX vào UART và watchdog/phục hồi bus I²C; giữ offset MMIO và giao
thức native bus. Driver C có tên bit, kiểm tra lỗi mới, thử recovery một lần
và bỏ mẫu lỗi. Chi tiết đối chiếu source tham khảo, thay đổi và giới hạn nằm
trong [báo cáo áp dụng](hoc_hoi_soc_cnn_driver_vi.md).

| Kiểm chứng | Kết quả |
|---|---|
| ModelSim All + Stress | **PASS 59/59 lượt**, 26 testbench |
| UART FIFO | Độ sâu 1/3/4, divisor 1/4/7; waveform, wrap, push/pop, backpressure, strobes, reset |
| I²C recovery | HALF_DIV 2/3/5, có/không hai FF; SCL/SDA stuck, timeout, 9 xung, STOP, pending DATA/CMD, reset |
| SoC MMIO | 12 case; thêm timeout → bus error → precise store fault cause 7, chặn store trẻ hơn |
| Quartus full compile | Thành công, 0 errors / 14 warnings |
| Fitter | 6.074 LE (12%), 2.888 registers, 338.944 memory bits, 3 multiplier 9-bit |
| TimeQuest 50 MHz | Worst setup +1,750 ns, hold +0,119 ns; setup/hold fully constrained |
| Firmware C | Host GCC kiểm tra cú pháp với `-Wall -Wextra -Werror`, thành công |

So với baseline mục 5 (5.892 LE / 2.820 registers), toàn top tăng 182 LE và
68 registers; memory bit và số multiplier không đổi. Đây là tổng tài nguyên
toàn SoC, không phải benchmark hiệu năng CPU. Các báo cáo trong
`quartus/output_files/` đã được cập nhật sang bản build mới.

14 cảnh báo thuộc các nhóm đã có: cổng/đầu vào ROM QNN không dùng, KEY[1]
không sử dụng, RAM suy luận thành ROM, LogicLock license và các yêu cầu pin/I/O.
Không còn hai cảnh báo truncation con trỏ UART xuất hiện ở lượt build thử.

Log cuối: `tmp/adopt_reference_regression.log` và
`tmp/adopt_reference_quartus.log`; log mô phỏng từng cấu hình nằm dưới
`sim/modelsim/work/`. Chưa thử board/Icarus/NativeLink GUI. Chưa cross-build
firmware RISC-V do WSL bị chặn và yêu cầu chạy ngoài sandbox bị hủy; chưa thay
ảnh ROM demo. Core vẫn RV32I trap-and-halt, UART chỉ TX, không có CSR/IRQ hay
lọc glitch I²C. `TIMEOUT_CYCLES=0` chủ động tắt watchdog nên không có bảo đảm
giới hạn thời gian chờ chân bus trong cấu hình đó.

## 10. Registered bus, POR, UART RX và MMIO page — P0/P1

Chốt ngày 27/09/2026; đầy đủ file thay đổi, protocol impact, kết quả và giới hạn
tại [báo cáo kiến trúc P0/P1](bao_cao_kien_truc_p0_p1_vi.md).

- Sửa QNN feature/START busy: chờ tới handshake, không silent loss.
- Request/response data bus có register; payload slave dùng bản đã chốt.
- POR 1024 clock cộng 3 clock nhả đồng bộ, không cần nhấn KEY khi bật board.
- UART RX 8N1/FIFO/W1C lỗi; page MMIO 4 KiB, offset slave 12 bit; GPIO 8 LED.
- Core RTL giữ nguyên từng byte, kiểm bằng hash baseline.
- ModelSim All+Stress: **PASS 69/69**, 31 testbench; SoC MMIO 20 case.
- Quartus full compile/fit: **0 errors, 14 warnings**; 6.353 LE, 3.184 registers,
  338.944 memory bits, 3 multiplier 9-bit.
- 50 MHz PASS: worst setup **+1,772 ns**, hold **+0,097 ns**. Fmax **54,86 MHz**
  so với **54,79 MHz** trước P0/P1; chưa đạt mục tiêu khuyến nghị >60 MHz.
- UART TX/I²C/timer/QNN model/fetch/trap không regression; test mới kiểm
  forwarding operand qua wait-state và UART RX pad→CPU→GPIO, đúng một lần pop.

Log cuối: `tmp/p0p1_final_regression.log`, `tmp/p0p1_quartus.log`,
`tmp/p0p1_timing_corners.log`. Báo cáo trong `quartus/output_files/` đã cập nhật
sang bản này, thay thế báo cáo build mục 9. Chưa thử board, GUI NativeLink,
Icarus hay cross-build firmware RISC-V trong đợt P0/P1.
