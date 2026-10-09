# RV32I QNN SoC cho DE10-Lite

Dự án gồm một core RISC-V **RV32I 32 bit, pipeline 5 tầng, in-order,
single-issue** và một SoC phục vụ bài toán ước lượng trạng thái sạc pin (SOC).
Thiết kế nhắm tới MAX 10 trên kit DE10-Lite, Quartus Prime Lite 20.1 và
ModelSim Intel FPGA Edition 20.1.

Ý tưởng ứng dụng được chuyển thể từ bài báo đính kèm: lấy cửa sổ 20 mẫu với
4 đặc trưng/mẫu, suy luận mạng fully-connected 80–16–8–1 đã lượng tử hóa. Dự án
không sao chép nền tảng Arty Z7/VexRiscv của bài báo; CPU, bus, ngoại vi và bộ
gia tốc ở đây được thiết kế cho DE10-Lite.

> **Giai đoạn hiện tại: CORE BASELINE FROZEN.** Core đã qua 195 lượt ISA test;
> firmware 20 mẫu và driver **INA228** đã kiểm tra end-to-end trên RTL.
> ModelSim 78/78; Icarus 32/32; Fmax sau tách module 54,61 MHz. Chưa thử board thật.
> Xem [báo cáo freeze/ISA/firmware](docs/bao_cao_freeze_isa_soc_vi.md) và
> [cấu hình INA228](docs/firmware_ina228_vi.md).

Core được tổ chức thành các tầng xử lý, ba module thanh ghi giữa tầng và hai
module hàng đợi của IF. Bắt đầu đọc tại [kiến trúc pipeline](docs/kien_truc_rv32i_vi.md)
và [hướng dẫn đọc RTL](docs/doc_hieu_core_vi.md). [Mục lục tài liệu](docs/README.md)
dẫn tới thiết kế SoC, đặc tả tích hợp và kết quả kiểm chứng.
Phần xác minh phần cứng còn chờ theo
[biên bản kiểm chứng board](docs/kiem_chung_board_vi.md).

## Khối đã có

- Core RV32I đủ 40 instruction base, pipeline `IF → ID → EX → MEM → WB`.
- Forwarding EX/MEM và MEM/WB, stall load-use, flush branch/jump.
- Bus Harvard: instruction dùng `req/gnt` + `rvalid/err` tách pha, data dùng
  `req/ready/err`; cả hai chấp nhận memory wait-state.
- Precise trap tại WB cho cause 0, 1, 2, 3, 4, 5, 6, 7 và 11.
- ROM chương trình 32 KiB hai cổng, SRAM 8 KiB, GPIO, UART TX/RX có FIFO, I²C master có timeout/phục hồi bus,
  timer 64 bit và bộ gia tốc QNN 80–16–8–1.
- QNN dùng feature/weight/activation INT8, accumulator/bias INT32, ReLU,
  requantize dịch bit và output 0..1000 (0,1 %SOC/LSB).
- Top DE10-Lite, pin assignment, SDC 50 MHz và cấu hình NativeLink.
- 32 testbench RTL, 46 lượt stress bổ sung; bộ ISA riêng có 40 chương trình
  upstream RV32UI và 25 chương trình exception/corner, mỗi chương trình 3 lịch chờ.

Không nằm trong phạm vi core hiện tại: extension M/A/C, CSR, interrupt,
Zicsr, Zifencei, cache và MMU.

## Cấu trúc pipeline

`rtl/core/rv32_core.v` chỉ nối dây giữa các tầng và bộ điều khiển. Ba module
trong `rtl/core/pipeline/` giữ ID/EX, EX/MEM, MEM/WB; khối cập nhật thanh ghi
không còn nằm chung trong top. Số tầng và thời điểm chốt vẫn giữ nguyên:

| Thư mục | Module tầng | Chức năng |
|---|---|---|
| `rtl/core/if/` | `rv32_if_stage` | Request/response fetch, FIFO 2 entry, bỏ response sai đường |
| `rtl/core/id/` | `rv32_id_stage` | Decoder, immediate và register file |
| `rtl/core/ex/` | `rv32_ex_stage` | Forwarding, ALU, branch/jump, alignment |
| `rtl/core/mem/` | `rv32_mem_stage` | Load/store, wait-state và access fault |
| `rtl/core/wb/` | `rv32_wb_stage` | Commit thanh ghi, trace và trap/halt |
| `rtl/core/pipeline/` | `rv32_id_ex_reg`, `rv32_ex_mem_reg`, `rv32_mem_wb_reg` | Giữ, nhận hoặc hủy dữ liệu tại từng ranh giới pipeline |

Trong IF, `rv32_if_request_queue` giữ PC/cờ hủy của yêu cầu đã nhận nhưng
chưa có đáp ứng; `rv32_if_fifo` giữ lệnh/ngoại lệ chờ ID. `rv32_if_stage`
quản lý PC, yêu cầu chờ grant và giới hạn chung hai chỗ đệm.

`rtl/core/control/` chứa hazard và điều khiển stall/flush; `common/` chứa LSU
dùng chung. Bus được tách tại `rtl/bus/soc_bus.v`. Testbench được nhóm theo
cùng cấu trúc dưới `tb/`. Chi tiết giao tiếp và timing nằm trong
[đặc tả tích hợp RTL 3.0](docs/giao_tiep_rtl_vi.md) (handshake core giữ nguyên).

Địa chỉ và tên lane bus được khai báo chung trong `rtl/bus/soc_map.vh`.
`rtl/soc/rv32_soc.v` bố trí theo luồng core → decoder → memory → MMIO,
nối response bằng tên lane để dễ kiểm tra và mở rộng. Xem sơ đồ và quy ước
nối dây ở mục 4.4 của đặc tả giao tiếp.

## Memory map

| Vùng | Địa chỉ | Chức năng |
|---|---:|---|
| ROM | `0x0000_0000..0x0000_7FFF` | instruction và dữ liệu chỉ đọc |
| SRAM | `0x1000_0000..0x1000_1FFF` | stack/data 8 KiB |
| GPIO | `0x2000_0000` | LED và switch |
| UART TX/RX | `0x2000_1000` | serial 8N1 115200 baud, FIFO và cờ lỗi RX |
| I²C | `0x2000_2000` | master byte-oriented, firmware driver INA228 |
| QNN | `0x2000_3000` | feature buffer, control, status, result |
| Timer | `0x2000_4000` | bộ đếm thời gian 64 bit |

Mỗi MMIO có page 4 KiB; slave nhận offset 12 bit, offset chưa định nghĩa trả
fault và không mirror thanh ghi. Data bus chốt cả request và response, một
transaction outstanding. GPIO phần mềm có 8 LED; LED[8:9] là debug.
Chi tiết quyền đọc/ghi, byte-enable và UART RX xem đặc tả.

## Môi trường Ubuntu / WSL

Dùng Python và compiler RISC-V trên hệ thống, không cần cài toolchain vào repo.
Cài thư viện ML và trình mô phỏng RTL:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends python3-numpy python3-openpyxl iverilog
```

Compiler `riscv64-unknown-elf-gcc` 14.2 đã được dùng với `-march=rv32i -mabi=ilp32`
trong Ubuntu WSL. Ngoài ra có toolchain tại `/opt/riscv32i/bin`.
Script build tự tìm compiler trên `PATH`, hoặc nhận `--prefix`.

Chạy từ thư mục project trong Ubuntu:

```bash
python3 scripts/run_tests.py --scope base
python3 scripts/run_tests.py --scope all
```

Kiểm tra core frozen, ISA và firmware:

```bash
python3 scripts/check_core_freeze.py
python3 scripts/run_isa.py
python3 scripts/run_firmware_tests.py
```

Các công cụ đối chiếu lịch sử `check_core_module_equivalence.py` và
`check_core_readability.py` cần bản sao lưu ZIP tương ứng, được giữ cục bộ và
không đi kèm checkout GitHub. Kiểm tra baseline hiện tại dùng
`check_core_freeze.py`; các lệnh ISA và regression ở trên không cần ZIP lịch sử.

Build firmware board riêng để review; chỉ train lại khi chủ động đổi mô hình:

```bash
python3 scripts/build_firmware.py --output-dir firmware/build/board_review
python3 ml/train_quantize_export.py --repo-root "$PWD" --epochs 150 --train-stride 1 --eval-stride 1
```

Lệnh build sinh ELF, BIN, HEX, MIF trong `firmware/build`, thay ảnh ROM demo bằng
firmware từ `main.c`. Để thử build mà giữ ảnh ROM hiện tại, truyền
`--output-dir /tmp/riscv-firmware-build`. Lệnh train mặc định chỉ ghi
`ml/artifacts`; thêm `--install` khi muốn cài model đã qua kiểm tra vào firmware.

Ubuntu dùng phiên bản NumPy/openpyxl do `apt` quản lý. `ml/requirements.txt`
giữ phiên bản của môi trường Python 3.11 ban đầu để tham chiếu tái lập;
không chạy `pip install` vào Python hệ thống. Khi đổi phiên bản NumPy, kết quả
huấn luyện có thể khác, cần đánh giá lại metric trước khi cài model.

Icarus chạy testbench với mô hình RTL behavioral; kiểm tra tổng hợp, timing và
NativeLink vẫn dùng Quartus/ModelSim đã cài trên Windows như hướng dẫn dưới đây.
Log Ubuntu nằm trong `sim/iverilog/work/`.

Nếu gọi từ PowerShell, `scripts/setup_ml.ps1` và `scripts/train_model.ps1`
chuyển lệnh sang bản Ubuntu/WSL mặc định; không dùng `.tools/python311`.

## Kiểm thử RTL bằng ModelSim

Từ PowerShell tại thư mục repo:

```powershell
./scripts/run_tests.ps1 -Scope Base
# Toàn bộ regression, bao gồm QNN:
./scripts/run_tests.ps1 -Scope All
# Thêm stress core, UART/I2C và firmware INA228 (78 lượt trên 32 testbench):
./scripts/run_tests.ps1 -Scope All -Stress
```

Script tự tìm ModelSim/Questa trên `PATH` hoặc bộ Intel FPGA Lite 20.1, tạo
lại đúng thư viện mô phỏng, compile toàn bộ RTL/testbench và chạy từng test ở
batch mode. Mỗi test phải in `PASS`; lỗi, timeout hoặc thiếu marker đều trả exit
code khác 0.

`-Stress` có 46 lượt bổ sung, gồm 8 kịch bản firmware INA228 và 16 seed thay đổi grant/response instruction và wait-state
data, đồng thời kiểm tra hai request instruction đang chờ và grant/response
cùng cạnh. UART thử bộ chia 1/2/3/7, FIFO sâu 1/3/4; I²C thử bộ chia nửa chu kỳ 2/3/5 với đầu
vào trực tiếp hoặc qua hai tầng FF. Test I²C mặc định dùng hai tầng FF giống
lớp board. Chế độ này hiện nằm trong script ModelSim PowerShell; script Icarus
vẫn chạy bộ test mặc định. Test mới kiểm tra timeout, phục hồi bus, UART RX/overrun/framing/baud mismatch,
POR, forwarding qua registered bus và lỗi MMIO truyền về trap CPU.
Kết quả mới nhất xem [báo cáo freeze/ISA/firmware](docs/bao_cao_freeze_isa_soc_vi.md).

## Quartus và NativeLink

Mở `quartus/riscv_soc.qpf`, hoặc chạy:

```powershell
cd quartus
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe' --flow compile riscv_soc
```

Top-level là `de10_lite_top`. POR tự giữ reset 1024+3 clock sau cấu hình;
`KEY[0]` reset active-low, nhả đồng bộ; `LEDR[7:0]` là GPIO,
`LEDR[8]` báo QNN busy, `LEDR[9]` báo trap. `GPIO[0:1]` lần lượt là I²C SCL/SDA
open-drain và cần pull-up; `UART_TX` dùng `PIN_V9` (GPIO[2]), `UART_RX` dùng `PIN_W9` (GPIO[3]).

NativeLink đã chọn `tb_rv32_soc`. Trong Quartus dùng
**Tools → Run Simulation Tool → RTL Simulation**. Regression command-line vẫn
là nguồn kiểm tra đầy đủ vì scope All chạy 32 testbench thay vì chỉ test SoC.

Kết quả compile lại ngày 27/09/2026 trên Quartus 20.1/10M50DAF484C7G:

- Fitter thành công: 6.353 logic element (13%), 3.184 register;
- 338.944 memory bit (20%), tương ứng 43 M9K (24%);
- 3 multiplier 9-bit (1%);
- timing 50 MHz fully constrained theo SDC hiện tại: worst setup `+1,772 ns`,
  worst hold `+0,097 ns`; Fmax slow 85°C **54,86 MHz**, chưa đạt mục tiêu >60 MHz;
- ModelSim All + Stress: PASS 78/78 lượt trên 32 testbench;
- test core nối ROM: 32 lệnh phụ thuộc retire liên tiếp, CPI=1 khi pipeline đầy.

Các số trên thuộc toàn bộ top SoC với firmware/model đang có, không phải tài
nguyên riêng core. Chưa thử trên board trong đợt này. Báo cáo gốc nằm trong
`quartus/output_files/`. Full compile còn 14 cảnh báo; Icarus PASS 32/32;
GUI NativeLink chưa chạy. Các số Quartus dùng ảnh boot baseline, chưa cài
firmware INA228 mới vào ROM board. Chi tiết trong
[báo cáo freeze/ISA/firmware](docs/bao_cao_freeze_isa_soc_vi.md).

## Tài liệu

Xem [mục lục trong `docs`](docs/README.md) để chọn tài liệu theo chủ đề.

- [Kiến trúc RV32I](docs/kien_truc_rv32i_vi.md): pipeline, forwarding, hazard và precise trap.
- [SoC và QNN](docs/soc_qnn_de10_lite_vi.md): luồng dữ liệu, accelerator và triển khai model.
- [Kiểm chứng ISA](docs/isa_verification_vi.md): coverage, kết quả và lệnh tái lập.
- [Timing FPGA](docs/timing_review_freeze_vi.md): critical path và setup/hold/recovery/removal.
- [Kiểm chứng board](docs/kiem_chung_board_vi.md): cấu hình đo, trình tự và tiêu chí đạt.

## Quy ước mã nguồn

- Verilog/SystemVerilog tương thích Quartus/ModelSim 20.1; chú thích UTF-8.
- Port dùng `_i`/`_o`, register tuần tự dùng `_q`, constant có độ rộng rõ ràng.
- Logic tổ hợp có default, side effect luôn bị khóa bởi valid/fault/flush.
- `default_nettype none` ở đầu và trả lại `wire` ở cuối mỗi source.
- Block memory dùng địa chỉ đúng độ rộng để Quartus suy luận M9K, tránh trải RAM
  thành flip-flop và mux.
