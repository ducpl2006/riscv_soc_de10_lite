# Project Quartus

`uart_loopback.qpf`/`.qsf` định nghĩa project MAX 10 có thực thể top-level là
`uart_loopback_top`. `uart_loopback.sdc` ràng buộc clock 50 MHz và hai đường vào
bất đồng bộ.

Chạy Analysis & Synthesis từ thư mục gốc của project bằng lệnh:

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/run_quartus_analysis.ps1
```

Các vị trí chân vật lý chủ ý không được suy đoán. Trước khi chạy fitter hoặc
nạp FPGA:

1. Điền `pins.qsf` với chân clock, nút nhấn, LED và hai GPIO theo template gán
   chân cùng schematic DE10-Lite chính thức.
2. Xác nhận USB-UART bên ngoài dùng logic 3,3 V, nối TX-sang-RX, RX-sang-TX và
   chung mass. Không nối trực tiếp tín hiệu mức điện áp RS-232 vào GPIO FPGA.
3. Chạy Analysis & Synthesis trước, kiểm tra cảnh báo CDC/timing, rồi chỉ chạy
   fitter sau khi đã có đủ vị trí chân và chuẩn I/O.
