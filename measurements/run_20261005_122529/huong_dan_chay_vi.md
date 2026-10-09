# Chạy project từ kiểm thử đến DE10-Lite — 05/10/2026

Đã hoàn tất kiểm thử, build mới và nạp thành công DE10-Lite qua `USB-Blaster [USB-0]`, chip `10M50DAF484@1`, JTAG ID `0x031050DD`. Quartus Programmer báo `Configuration succeeded`, 0 lỗi và 0 cảnh báo lúc 12:32:58 ngày 05/10/2026 theo Windows. Người dùng xác nhận LEDR[2], LEDR[3], LEDR[9] sáng, LEDR[8] tắt và KEY[0] chạy lại đúng. Chưa thu UART thật. USB-UART chưa được phát hiện; COM3 là Intel Active Management Technology SOL, không phải adapter UART đã xác nhận. Các log ban đầu ghi không có JTAG; log `jtag_debug.log` và `program.log` ghi kết nối/nạp thành công sau khi người dùng cắm board.

| Bước | Kết quả mới của lần chạy |
|---|---|
| Freeze audit | PASS, 20 file core nguyên vẹn |
| Icarus RTL toàn bộ | PASS 32/32 |
| ModelSim All + Stress | PASS 78/78 |
| ISA | PASS 195/195 |
| Firmware C và RTL | PASS 2 nhóm host + 9 kịch bản RTL |
| Đối chiếu core trước/sau tách module | PASS 22/22; 36.545 lần so sánh |
| ROM/model board, POR và KEY tại 50 MHz | PASS, UART OK, QNN 12, LED 0x20C |
| Quartus full compile | Thành công, 0 lỗi, 14 cảnh báo |
| Timing ba corner | Setup +1,687; hold +0,112; recovery +17,162; removal +1,030 ns |
| Fmax slow 85°C | 54,61 MHz; clock sử dụng 50 MHz |
| Nạp FPGA | PASS, configuration succeeded, 0 lỗi/0 cảnh báo |
| LED/reset phần cứng | PASS, người dùng xác nhận LED đúng và KEY[0] chạy lại |
| UART và INA228 phần cứng | Chưa thu dữ liệu |

ROM `firmware/build/boot.hex` và `boot.mif`, toàn bộ nguồn trong manifest đều giữ nguyên checksum. Firmware kiểm thử được build tại `firmware/build/verify_*`, ảnh simulation tại `tb/soc/firmware_assets`. Không train hoặc cài model mới. Snapshot nguồn và log nằm trong thư mục này.

SOF mới: `riscv_soc.sof` trong thư mục báo cáo này, bản gốc `quartus/output_files/riscv_soc.sof`.

SHA256: `6c9d103d173a53ec0135bedd85e385543094c9ee7234e4837f6b3f996587b934`

## Nạp demo baseline

1. Cấp nguồn DE10-Lite và nối cổng USB-Blaster vào đúng máy Windows này bằng cáp có truyền dữ liệu.
2. Trong PowerShell, kiểm tra:

```powershell
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_pgm.exe' -l
& 'C:\intelFPGA_lite\20.1\quartus\bin64\jtagconfig.exe'
```

Phải nhận cable và chip 10M50. Nếu Windows không thấy thiết bị USB mới, kiểm tra cáp/cổng/nguồn trước. Nếu Windows thấy USB-Blaster nhưng báo lỗi driver, dùng driver có sẵn trong `C:\intelFPGA_lite\20.1\quartus\drivers\usb-blaster`.

3. Chạy script trong thư mục báo cáo; thay `<ten-cable>` bằng đúng cable được liệt kê:

```powershell
.\program_demo.ps1 -Cable '<ten-cable>'
```

Script xác minh SHA256 và chip 10M50, lưu log nạp. Nạp SOF qua JTAG là cấu hình chạy thử; mất khi tắt nguồn, không ghi flash.

4. Kết quả mong đợi sau boot: LEDR[2], LEDR[3], LEDR[9] sáng; LEDR[8] tắt. QNN trả 12 với model đang cài. LEDR[9] sáng vì EBREAK kết thúc demo, cause=3 tại PC=0x48. Nhấn/nhả KEY[0] để chạy lại.

5. Để xem UART, nối GND chung và FPGA TX (tín hiệu UART_TX, pad PIN_V9, GPIO[2]) sang RX của adapter USB-UART 3,3 V. Xác nhận số chân vật lý trên header theo sơ đồ đúng revision board; GPIO[2] là tên tín hiệu, không phải pin số 2 trên header. Chọn đúng COM của adapter, 115200 baud, 8N1, tắt flow control. Mở terminal trước khi nhấn KEY[0]; nhận đúng hai byte `OK`, không có newline. USB-Blaster dùng JTAG, không tạo luồng UART của SoC.

## Thử INA228 thật

SOF hiện tại là demo CPU/QNN, chưa đọc cảm biến. Không dùng địa chỉ 0x40 và shunt 10 mΩ của fixture simulation làm thông số module thật. Cần xác nhận revision module, địa chỉ I²C 7 bit, shunt µΩ, CURRENT_LSB nA/count, ADC range và chiều dòng. Chân I²C là GPIO[0]/PIN_V10 (SCL), GPIO[1]/PIN_W10 (SDA), open-drain; xác nhận pin vật lý, nguồn, pull-up và chung GND theo phần cứng thực tế.

Firmware board mặc định hiện thiếu cấu hình và báo `INA228` rồi `CONFIG_REQUIRED`. Build firmware riêng, giữ baseline ROM:

```bash
python3 scripts/build_firmware.py --output-dir firmware/build/board_review
```

Sau khi có thông số thật, truyền các `--define BOARD_...=<gia-tri>` và chọn ROM mới trong project đo riêng, rồi full compile/timing trước khi nạp. `read_cell_temperature()` hiện chưa có nguồn đo nhiệt độ pin; INA228 DIETEMP là nhiệt độ die. Khi thiếu nhiệt độ pin, firmware phải báo `CELL_TEMP_REQUIRED`, chưa thể xác minh SOC toàn luồng trên pin thật. Chi tiết quy trình đo: `docs/kiem_chung_board_vi.md`.

## Chạy lại các bước trên máy

Từ thư mục gốc project trong WSL:

```bash
python3 scripts/check_core_freeze.py
python3 scripts/run_firmware_tests.py
python3 scripts/run_tests.py --scope all
python3 scripts/run_isa.py
python3 scripts/check_core_module_equivalence.py --label <nhan-moi>
python3 measurements/run_20261005_122529/run_board_smoke.py
```

PowerShell từ thư mục gốc:

```powershell
.\scripts\run_tests.ps1 -Scope All -Stress
Set-Location quartus
& 'C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe' --flow compile riscv_soc
```

`run_board_smoke.py` chỉ tạo bản top mô phỏng trong thư mục kết quả: chuyển MIF sang HEX tương đương, kiểm tra khớp dữ liệu, giữ nguyên RTL source. Test dùng clock 50 MHz và decoder UART 434 clock/bit, kiểm tra cả POR và reset KEY với đúng ROM/model board. Đây là mô phỏng behavioral, chưa thay thế kết quả đo trên FPGA.

## Đấu USB-UART vào JP1

Đối chiếu manual Terasic, hình 3-18 trang 30 và QSF của project:

| USB-UART TTL 3,3 V | Header JP1 trên DE10-Lite |
|---|---|
| RXD | Pin 3: GPIO[2], PIN_V9, UART_TX FPGA |
| TXD (tùy chọn; demo chỉ phát OK) | Pin 4: GPIO[3], PIN_W9, UART_RX FPGA |
| GND | Pin 12 hoặc 30: GND |
| VCC/5V/3V3 | Không nối; kit dùng nguồn riêng/USB-Blaster |

Để thu demo chỉ cần RXD và GND. Xác định pin 1 bằng dấu trên PCB và hình manual trước khi đếm: các cặp là 1–2, 3–4, 5–6, ...; GPIO[2] là pin vật lý 3. Giữ mức tín hiệu UART 3,3 V. Nếu ngắt nguồn để đấu dây, cần nạp lại SOF khi bật nguồn.

Nguồn: Terasic DE10-Lite User Manual (bản lưu tại FPGA Academy), hình 3-18/trang 30: https://fpgacademy.org/Downloads/DE10_Lite_User_Manual.pdf#page=31

Cắm USB-UART vào máy, xác nhận COM mới trong Device Manager. Mở terminal 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control, rồi nhấn/nhả KEY[0]. Nhận `OK` (4F 4B), không có newline. Hoặc dùng script ghi bằng chứng trong thư mục này:

```powershell
.\capture_uart.ps1 -PortName COMx -Seconds 30
```

Thay COMx bằng đúng COM adapter; sau khi script báo capture started, nhấn/nhả KEY[0]. Script lưu uart_raw.bin và uart_capture.log. COM3 hiện là Intel AMT SOL và bị script từ chối để tránh chọn nhầm thiết bị.

## Nạp lại và UART phần cứng lúc 12:57 ngày 05/10/2026

Đã nạp lại cùng SOF baseline thành công, 0 lỗi/0 cảnh báo. Mở COM7 CH340 trước khi nạp, thu chính xác `4F 4B` (`OK`) ở 115200 8N1: PASS. Log và bytes gốc lưu tại `reload_20261005_125728/`. Các log lần thu trước không nhận byte vẫn giữ nguyên. COM7 đã đóng sau thu; người dùng sẽ tự dùng PuTTY. Mở PuTTY Serial COM7, 115200, 8N1, flow control None rồi nhấn/nhả KEY[0] để phát lại `OK`.
