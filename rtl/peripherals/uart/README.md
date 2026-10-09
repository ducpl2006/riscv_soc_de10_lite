# UART 8N1 cho FPGA

Project cung cấp một UART full-duplex có FIFO, một top-level loopback cho
DE10-Lite và bộ test tự động. RTL dùng Verilog-2001, một miền clock duy nhất và
clock-enable; không tạo clock dẫn xuất bên trong thiết kế.

Mỗi module RTL có khối `ĐẶC TẢ` bằng tiếng Việt ngay trong source, mô tả tham
số, giao thức, reset, timing và các trường hợp lỗi của chính module đó.

## Bắt đầu nhanh

Yêu cầu: ModelSim/Questa. Script tự tìm bản ModelSim đi kèm Intel FPGA; cũng có
thể truyền trực tiếp thư mục chứa `vlog.exe`.

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/run_tests.ps1

# Hoặc:
powershell -ExecutionPolicy Bypass -File ./scripts/run_tests.ps1 `
  -ModelSimBin C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem
```

Một lần chạy hợp lệ phải kết thúc bằng `ALL TESTS PASSED (6/6)`. Script không
chỉ dựa vào exit code của simulator mà còn kiểm tra marker PASS/FAIL của từng
testbench.

## Kiến trúc

```text
Ứng dụng TX -> TX FIFO -> uart_tx -> uart_tx_o
uart_rx_i -> 2FF sync -> uart_rx -> RX FIFO -> Ứng dụng RX
```

Các module chính:

| File | Trách nhiệm |
| --- | --- |
| `rtl/uart_top.v` | UART full-duplex tái sử dụng, có FIFO TX/RX |
| `rtl/uart_tx.v` | Serializer UART 8N1, LSB trước |
| `rtl/uart_rx.v` | Receiver oversampling, majority vote, framing/overrun |
| `rtl/sync_fifo.v` | FIFO một clock với giao thức ready/valid |
| `rtl/uart_baud_gen.v` | Clock-enable tick theo bộ chia nguyên |
| `rtl/uart_rx_sync.v` | Đồng bộ hai flip-flop cho chân RX bất đồng bộ |
| `rtl/reset_sync.v` | Assert reset bất đồng bộ, deassert đồng bộ |
| `rtl/uart_loopback_top.v` | Demo DE10-Lite: nhận byte hợp lệ rồi phát lại |

## Quy tắc giao tiếp quan trọng

- Một transfer xảy ra tại cạnh lên khi `valid && ready` cùng bằng 1.
- Producer phải giữ `valid` và dữ liệu ổn định trong lúc `ready=0`.
- `rst_n` của các core phải được nhả đồng bộ; dùng `reset_sync` cho nút nhấn.
- Frame 8N1: idle=1, start=0, 8 data bit LSB trước, stop=1.
- `rx_framing_error` đi cùng byte qua RX FIFO.
- `rx_overrun_error` là pulse một clock và byte mới nhất bị loại.
- Sau bad stop/BREAK, RX chờ đường truyền trở lại mức high rồi mới nhận frame
  kế tiếp; một khoảng BREAK liên tục không tạo vô hạn frame lỗi.

## Cấu hình mặc định

- Clock: 50 MHz
- Baud: 115200
- RX oversampling: 16
- FIFO TX/RX: 16 entry

Bộ chia baud dùng phép chia nguyên. Sai số thực tế và miền tham số hợp lệ được
ghi rõ trong [đặc tả](docs/SPECIFICATION.md).

## Chạy trên DE10-Lite

Project Quartus nằm trong `quartus/`. Pin vật lý không được tự đoán: hãy điền
`quartus/pins.qsf` theo schematic và đúng hai chân GPIO bạn thực sự nối. Xem
[hướng dẫn Quartus](quartus/README.md) trước khi fit/program.

Chạy riêng Analysis & Synthesis (không fitter/programmer):

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/run_quartus_analysis.ps1
```

LED của demo loopback:

| LED | Ý nghĩa |
| --- | --- |
| `LEDR[0]` | TX đang bận hoặc còn dữ liệu chờ |
| `LEDR[1]` | RX FIFO đang có byte |
| `LEDR[2]` | Đã từng có framing error (sticky) |
| `LEDR[3]` | Đã từng có receive overrun (sticky) |

`KEY[0]` là reset active-low. Các LED lỗi chỉ xóa bằng reset.

## Lộ trình đọc project

1. Đọc handshake và timing trong [đặc tả](docs/SPECIFICATION.md).
2. Đi theo từng byte trong [hướng dẫn làm chủ](docs/LEARNING_GUIDE.md).
3. Đọc `uart_baud_gen`, sau đó `uart_tx` để theo một frame phát.
4. Đọc `uart_rx_sync` và FSM trong `uart_rx` để hiểu sampling/majority vote.
5. Đọc `sync_fifo`, rồi `uart_top` để thấy cách ghép luồng dữ liệu.
6. Đọc các testbench tương ứng; mỗi test là một ví dụ sử dụng executable.
7. Xem [báo cáo thay đổi](docs/CHANGE_REPORT.md) để biết vấn đề ban đầu và lý
   do của từng chỉnh sửa.
