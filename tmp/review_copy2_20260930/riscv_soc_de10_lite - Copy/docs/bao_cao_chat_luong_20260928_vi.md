# Chuẩn hóa RTL và cập nhật tài liệu — 2026-09-28

Đã chuẩn hóa các đoạn RTL dồn dòng ngoài core, cập nhật tài liệu SoC theo INA228
và chạy lại regression. **Chưa kiểm chứng phần cứng**; chưa nạp board hoặc đo
UART/I²C. Core frozen và ảnh ROM baseline giữ nguyên.

## Thay đổi

- `rtl/peripherals/uart/soc_uart.v`: một port/connection mỗi dòng; phân biệt các
  nhóm decode, handshake, side effect, latch lỗi và readback bằng bố cục/chú thích.
- `rtl/peripherals/uart/uart_rx.v`: mở rộng từng nhánh FSM và từng phép gán;
  tách rõ synchronizer, xung sự kiện và chuyển trạng thái.
- `rtl/peripherals/uart/uart_rx_fifo.v`: mở rộng reset/push/pop/occupancy, giữ
  nguyên quy tắc push+pop và overflow.
- GPIO, timer và top board: tách các phép gán/kết nối dồn dòng. I²C: làm rõ
  các nhóm decode/handshake/side effect, sửa chú thích cảm biến thành INA228.
- Chú thích top board phân biệt chỉ số tín hiệu GPIO với số chân vật lý đầu nối.
- [Tài liệu SoC](soc_qnn_de10_lite_vi.md): bỏ mô tả INA219 lỗi thời, cập nhật UART
  RX, pipeline firmware, toolchain, tình trạng model và phân biệt ROM baseline
  với ảnh firmware C. Không lấy die temperature làm nhiệt độ pin.
- [Biên bản board](kiem_chung_board_vi.md): ghi bảng pad từ QSF, điều kiện đầu
  vào, artifact cần chốt, tiêu chí và bằng chứng đo; các bước đo đều còn CHỜ.

Các sửa RTL chỉ thay whitespace và comment. Đối chiếu chuỗi token (giữ nguyên
string literal/operator, bỏ comment/whitespace) PASS ở cả 7 file; không thay
biểu thức logic, thứ tự phép gán hoặc cấu trúc điều khiển. Snapshot trước sửa và
script đối chiếu ở `tmp/quality_review_20260928/`.

## Lỗi chọn source được phát hiện khi chạy regression

Script cũ quét đệ quy toàn bộ `rtl/`, lấy cả project UART độc lập trong
`rtl/peripherals/uart/rtl/`. Module `uart_rx` của project đó khác module UART
SoC nhưng trùng tên; Icarus báo `uart_rx has already been declared` trước khi
chạy test. Đây là lỗi chọn source, không phải lỗi do format RTL.

`scripts/soc_rtl_sources.py` lấy 31 source từ các assignment VERILOG_FILE hoặc
SYSTEMVERILOG_FILE trong `quartus/riscv_soc.qsf`. Hai runner Python dùng chung
hàm này; runner PowerShell dùng cùng danh sách QSF, kiểm tra file và bản ghi
trùng. Parser hỗ trợ đường dẫn literal, có hoặc không có dấu nháy kép; không
thực thi Tcl. Nếu đổi QSF sang biểu thức Tcl cần cập nhật cách đọc tương ứng.

Không xóa project UART độc lập và không bớt test SoC. Bộ 6 test của project UART
độc lập vẫn có runner riêng; nó không thuộc 78 lượt regression SoC bên dưới.

## Kết quả chạy lại

| Kiểm tra | Kết quả | Bằng chứng |
|---|---|---|
| Core freeze | PASS, 15 file nguyên SHA256 | [integrity.log](../tmp/quality_review_20260928/integrity.log) |
| Token RTL / boot baseline | 7/7 file token giống nhau; `boot.hex/mif` nguyên SHA256 | [integrity.log](../tmp/quality_review_20260928/integrity.log) |
| ModelSim All + Stress | PASS 78/78 | [modelsim.log](../tmp/quality_review_20260928/modelsim.log) |
| Icarus All | PASS 32/32 | [icarus.log](../tmp/quality_review_20260928/icarus.log) |
| ISA upstream + local | PASS 195/195 | [isa.log](../tmp/quality_review_20260928/isa.log) |
| Firmware RTL + host C | PASS 9/9 và 2 nhóm host | [firmware.log](../tmp/quality_review_20260928/firmware.log) |
| JTAG | `No JTAG hardware available` | [jtag.log](../tmp/quality_review_20260928/jtag.log) |

Các bộ có ca giao nhau, không cộng các số thành số lượng test độc lập.
Các runner giữ nguyên testbench và stress parameters. Lệnh tái chạy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
```

```bash
python3 scripts/check_core_freeze.py
python3 scripts/run_firmware_tests.py
python3 scripts/run_tests.py --scope all
python3 scripts/run_isa.py
```

Không chạy lại Quartus timing trong đợt chỉ đổi bố cục/comment này; thông số
54,86 MHz và setup/hold/recovery/removal trong báo cáo freeze vẫn là **kết quả
baseline ngày 2026-09-27**, không phải phép đo mới. Firmware C mới cũng chưa
được đưa vào ROM Quartus. Không thay manifest core để hợp thức hóa thay đổi.

## Phần còn chờ trên board

Windows có COM3 nhưng chưa xác nhận là adapter nối board. Chưa phát hiện JTAG,
chưa xác nhận địa chỉ/shunt/calibration INA228 và nguồn nhiệt độ pin. Vì thế chưa
thể đo giao thức hoặc đối chiếu giá trị với dụng cụ. Biên bản nêu rõ ảnh chẩn
đoán/trace còn cần cho UART RX và raw/feature, không gán PASS cho các mục này.
Chỉ nâng tuyên bố xác minh phần cứng sau khi có capture và log cho đúng ảnh nạp.
