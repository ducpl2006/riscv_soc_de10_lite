# Kiểm chứng DE10-Lite + INA228 trên phần cứng

Cập nhật 2026-09-28. **Chưa xác minh trên board.** Đây là quy trình và biểu mẫu
thu bằng chứng; các tiêu chí bên dưới chưa phải kết quả đo.

Kiểm tra kết nối trên máy ngày 2026-09-28: `quartus_pgm -l` trả
`No JTAG hardware available`. Windows liệt kê `COM3`; chưa xác nhận thiết bị này
là USB-UART của DE10-Lite. Không nạp FPGA và chưa thu waveform phần cứng.

## 1. Chốt cấu hình của một lần đo

Mỗi lần đo dùng một thư mục riêng `measurements/<ngay-gio>/`. Lưu bản sao QSF,
SDC, cấu hình firmware, manifest model, lệnh build, log compile/timing, SHA256
của `.sof`, ELF và ảnh ROM thực sự dùng. Không suy ra nội dung `.sof` chỉ từ tên
file hoặc thời gian sửa. Nếu chưa có Git, lưu snapshot source và checksum.

| Trường | Giá trị cần ghi |
|---|---|
| Board, revision, số nhận dạng | Chưa xác nhận |
| JTAG cable/device chain | Chưa phát hiện |
| USB-UART, COM, mức logic | COM3 có xuất hiện, thiết bị chưa xác nhận |
| INA228 module, nguồn, sơ đồ nối dây | Chưa xác nhận |
| Địa chỉ I²C 7 bit / strap địa chỉ | Chưa xác nhận; không dùng giá trị fixture |
| Shunt µΩ, sai số, CURRENT_LSB nA/count, ADC range | Chưa xác nhận |
| Chiều IN+/IN− và chiều dòng | Đối chiếu quy ước model: dương khi sạc |
| Nguồn nhiệt độ pin / calibration | Chưa có driver nguồn thật |
| Oscilloscope / logic analyzer / đồng hồ | Ghi model, cấu hình, độ chính xác |
| Firmware mode, ROM/SOF SHA256, model ID | Ghi đúng artifact nạp |

`firmware/include/board_config.h` hiện để địa chỉ, shunt và CURRENT_LSB bằng 0.
Đây là dấu hiệu chưa cấu hình. Giá trị 0x40/10 mΩ trong test là fixture, không
phải kết quả xác định module thật. DIETEMP không thay thế nhiệt độ pin.

## 2. Chân và reset

Bảng sau được trích từ `quartus/riscv_soc.qsf` và `rtl/board/de10_lite_top.v`.
Đây là cấu hình source, **chưa phải xác nhận đấu dây**. Tra sơ đồ đúng revision
board để đổi tên pad FPGA/tín hiệu GPIO sang số chân vật lý trên đầu nối.

| Tín hiệu | Pad trong QSF | Chức năng cần đo |
|---|---|---|
| MAX10_CLK1_50 | PIN_P11 | Clock 50 MHz |
| KEY[0] | PIN_B8 | Reset nhấn mức thấp |
| GPIO[0] | PIN_V10 | SCL, open-drain |
| GPIO[1] | PIN_W10 | SDA, open-drain |
| UART_TX | PIN_V9 | TX từ FPGA sang RX adapter |
| UART_RX | PIN_W9 | RX FPGA nhận TX adapter |
| LEDR[8] | PIN_A11 | QNN busy |
| LEDR[9] | PIN_B11 | Trap valid |

Chỉ số tín hiệu GPIO[2]/GPIO[3] không phải số chân đầu nối. Xác nhận chung GND,
mức logic UART 3.3 V và nguồn/pull-up I²C đúng module trước khi nối. QSF bật weak
pull-up nhưng không chứng minh rise time hoặc thay việc kiểm tra pull-up ngoài.

Sau cấu hình, POR giữ 1024 clock rồi nhả qua 3 tầng đồng bộ. KEY assert bất đồng
bộ ở reset controller; các state SoC được reset theo clock. Ghi capture power-up
và nhấn/nhả KEY giữa giao dịch, đối chiếu `tb_rv32_reset_controller` cùng trace
boot. Để quan sát chính xác `rst` nội bộ cần SignalTap hoặc bản đo riêng; UART
boot lặp lại chỉ chứng minh hành vi khởi động, không đo trực tiếp độ trễ reset.

## 3. Phân biệt ảnh firmware

| Ảnh | Trạng thái / hành vi mong đợi |
|---|---|
| `firmware/build/boot.*` | Baseline Quartus hiện tham chiếu; demo CPU/QNN, phát `OK`, rồi EBREAK |
| `firmware/build/verify_board/boot.*` | Bản build kiểm thử firmware C; chưa tự được đưa vào Quartus |
| `tb/soc/firmware_assets/fake.hex` và `ina228.hex` | Dành cho simulation, có nhiệt độ pin giả được khai báo |

Demo kết thúc EBREAK có thể làm LEDR[9] bật đúng thiết kế. Không lấy “LED trap
luôn tắt” làm tiêu chí chung. Testbench SoC dùng model vàng riêng và kết quả 84;
không áp kết quả đó cho `.sof` dùng model trong `firmware/model`.

Build firmware board riêng trong Linux/WSL:

```bash
python3 scripts/build_firmware.py --prefix riscv64-unknown-elf- --output-dir firmware/build/board_review
```

Truyền các `--define BOARD_...=<gia-tri-da-xac-nhan>` sau khi đã có thông số thật;
giữ `FIRMWARE_SENSOR_MODE=0`. Mặc định bản này phải in `INA228` rồi
`CONFIG_REQUIRED` và kết thúc nếu cấu hình còn thiếu. Khi cảm biến hợp lệ nhưng
thiếu nhiệt độ pin, phải báo `CELL_TEMP_REQUIRED` khi đủ cửa sổ, không in `SOC=`.

Dùng project/revision đo riêng để chọn ROM mới, kiểm tra đường dẫn INIT_FILE thực
sự ở compile report và lưu ảnh `.sof` tương ứng. Không chép đè `boot.*` baseline
hoặc coi một lần build firmware là đã cập nhật `.sof`. Chạy fitter và xác nhận
setup/hold/recovery/removal đạt ở các corner cho ảnh đo trước khi nạp.

## 4. Trình tự đo và tiêu chí đạt

| Bước | Thao tác / đối chiếu | Bằng chứng bắt buộc | Trạng thái |
|---|---|---|---|
| Kết nối | Nhận đúng cable và chip trong JTAG; nhận đúng USB-UART | Log enumerate, ảnh nhận dạng/dây nối | CHỜ |
| Chân/reset | Đối chiếu QSF với sơ đồ và probe; boot lại qua POR/KEY, kể cả giữa giao dịch | Bảng nối dây, capture reset/boot; trace nội bộ nếu đo rst | CHỜ |
| UART TX | Đo idle, start, 8 bit LSB-first, stop; baud mục tiêu 115200, khoảng 8,68 µs/bit | Capture gốc, decoder và UART raw log; so với bytes firmware đã chọn | CHỜ |
| UART RX | Chạy firmware chẩn đoán riêng để đọc/echo RX; kiểm tra thứ tự byte và cờ lỗi | Image hash, dữ liệu gửi/nhận, kết quả so sánh | CHỜ |
| I²C | Đo idle, START/repeated START/STOP, ACK/NACK, thứ tự byte; SCL mục tiêu 100 kHz | Capture SCL/SDA gốc và bảng decoder; đối chiếu giao dịch driver/RTL | CHỜ |
| INA228 | Đọc ID, cấu hình/calibration, raw VBUS/CURRENT/VSHUNT/DIETEMP | Log raw + cấu hình thực; không chỉ ảnh terminal `SOC=` | CHỜ |
| Giá trị đo | So mV/mA với đồng hồ ở nhiều điểm, đúng dấu dòng; ghi riêng die và cell temperature | Bảng raw → firmware → dụng cụ đo → sai số, dải chấp nhận có căn cứ | CHỜ |
| QNN độc lập | Nạp vector vàng và đúng model; so kết quả nguyên và CYCLES | Vector/model hash, kết quả reference và board | CHỜ |
| Toàn luồng | Thu >=20 mẫu hợp lệ, dt thực, 80 feature oldest-first; so quantize và kết quả QNN | Mẫu raw, feature, integer reference, UART và dấu thời gian cùng lần đo | CHỜ |
| Lỗi/phục hồi | Ngắt cảm biến hoặc gây NACK có kiểm soát, reset giữa giao dịch; không xuất kết quả từ cửa sổ lỗi | Capture, timeout/recovery log, reset cửa sổ và lần hoạt động lại | CHỜ |

Firmware `main.c` hiện không có chế độ echo RX hoặc xuất đầy đủ raw/feature;
các bước đó cần ảnh chẩn đoán riêng hay SignalTap trước khi có thể đánh dấu đạt.
Chưa có nguồn nhiệt độ pin thật thì bước toàn luồng còn chặn dù UART/I²C đã đạt.
Capture logic analyzer xác minh giao thức; dùng oscilloscope khi cần đo mức điện
áp, rise/fall time. Ghi sample rate/timebase và căn cứ chọn dung sai đo.

Đối chiếu simulation bằng test tương ứng: `tb_rv32_uart_rx`,
`tb_rv32_i2c_transactions`, `tb_rv32_i2c_recovery`, `tb_rv32_firmware_e2e` và
`tb_rv32_qnn_model`. Lưu trace và log simulation riêng khỏi capture board.
Testbench dùng clock/timing rút gọn nên so thứ tự giao dịch, byte và số chu kỳ
theo cấu hình; không áp thời gian tuyệt đối của simulation lên capture 50 MHz.

## 5. Biên bản kết quả mỗi phép đo

Ghi: người đo, thời gian, artifact/hash, cấu hình dụng cụ, điều kiện đầu vào,
giá trị mong đợi, giá trị đo, dung sai/căn cứ, PASS/FAIL, đường dẫn capture và
log. Với một lỗi, lưu cả lần lỗi lẫn lần đo lại sau sửa; không thay log lỗi bằng
log đạt. Cần đủ bằng chứng UART + I²C + reset + firmware/model đúng ảnh mới công
bố đã xác minh tích hợp phần cứng cho phạm vi đó. Độ chính xác SOC trên pin thật
cần đánh giá riêng với dữ liệu tham chiếu; demo chạy không chứng minh điều này.
