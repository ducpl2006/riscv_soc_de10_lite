# Báo cáo rà soát và chỉnh sửa

Ngày rà soát: 2026-09-18.

## Chuẩn hóa chú thích và đặc tả nội tuyến

- Chuyển toàn bộ câu chú thích tiếng Anh trong RTL, testbench, script và file
  cấu hình Quartus sang tiếng Việt; giữ nguyên tên tín hiệu và thuật ngữ chuẩn
  cần thiết để tra cứu datasheet/tool.
- Bổ sung khối `ĐẶC TẢ` ngay đầu từng module RTL, bao gồm:
  - miền tham số hợp lệ và công thức timing;
  - quy tắc ready/valid, điều kiện giữ ổn định payload;
  - trạng thái output trong reset;
  - hành vi framing error, overrun và BREAK;
  - đặc tính FIFO show-ahead, ghi/đọc đồng thời và quay vòng con trỏ;
  - yêu cầu CDC/reset và ràng buộc phần cứng của top-level.
- Đây là thay đổi tài liệu trong code, không thay đổi logic RTL hay interface.

## Trạng thái ban đầu

- `uart_baud_gen` tham chiếu nhầm `CLK_FREQ` thay vì `CLOCK_FREQ`.
- `tick` được khai báo `reg` nhưng lại drive bằng continuous assignment;
  ModelSim chấp nhận nhưng Quartus dừng với Error 10219.
- `sync_fifo.v`, `uart_top.v` và `tb_sync_fifo.v` rỗng.
- Không có README, đặc tả, lệnh test chung, project Quartus hoặc constraint.
- RX có thể tự nhận lặp nhiều frame lỗi khi đường truyền giữ low (BREAK).
- Miền tham số không được kiểm tra; một số cấu hình tạo phép chia 0/underflow.
- Testbench in PASS/FAIL nhưng simulator vẫn thường trả exit code 0; hai VCD
  system task cũng gây cảnh báo portability trên ModelSim lint.

## Thay đổi chức năng

| Khu vực | Thay đổi | Lý do |
| --- | --- | --- |
| Baud generator | sửa tên tham số, `tick` thành net, gate reset, kiểm tra tham số | build được trên Quartus và tránh cấu hình vô nghĩa |
| TX | `tx_ready=0` trong reset | không tạo handshake giả khi core đang reset |
| RX | thêm `WAIT_IDLE` sau bad stop/BREAK | một BREAK chỉ sinh một event và có quy tắc phục hồi rõ |
| RX | tách nhánh false-start khỏi end-of-bit | bỏ phụ thuộc vào “last nonblocking assignment wins” |
| CDC/reset | thêm thuộc tính synchronizer | bảo toàn ý đồ CDC trong synthesis |
| FIFO | hoàn thiện FIFO ready/valid, depth tùy ý | buffer burst và tách application khỏi serializer |
| `uart_top` | ghép RX/TX với FIFO độc lập | tạo core full-duplex tái sử dụng được |
| Loopback | chuyển sang dùng `uart_top` | demo chính kiểm tra đúng kiến trúc hoàn chỉnh |

## Thay đổi verification và vận hành

- Hoàn thiện `tb_sync_fifo` và thêm `tb_uart_top`.
- Mở rộng test RX cho BREAK/recovery và sửa khoảng nghỉ sau bad stop.
- Chuẩn hóa marker `TEST_RESULT` cho mọi testbench.
- Thêm `scripts/run_tests.ps1`; script compile lint, chạy sáu top và tự trả lỗi
  nếu thiếu PASS marker hoặc xuất hiện FAIL marker.
- Guard VCD bằng define `DUMP_VCD` để mặc định không phụ thuộc system task.
- Thêm project Quartus, SDC và template pin cục bộ.
- Thêm README và đặc tả hành vi/timing/giao thức.

## Quyết định có chủ ý

- Vẫn dùng bộ chia nguyên thay vì phase accumulator để RTL nhỏ và dễ học; sai
  số được tính và công khai trong đặc tả.
- FIFO dùng combinational show-ahead read. Đây là lựa chọn phù hợp FIFO nhỏ;
  với FIFO rất sâu hoặc mục tiêu RAM block bắt buộc, nên đổi sang registered
  synchronous-read architecture.
- Không gán pin vật lý DE10-Lite trong repository vì hai chân GPIO phụ thuộc
  dây nối thực tế. `pins.qsf` buộc người tích hợp xác nhận pin và
  I/O voltage trước khi program.

## Verification cuối cùng

### ModelSim Intel FPGA Edition 20.1

- Compile `-lint -pedanticerrors`: **0 lỗi, 0 cảnh báo**.
- **6/6 testbench PASS**:
  - baud generator: 9 nhóm test;
  - FIFO: 7 nhóm test, gồm `DEPTH=3` và `DEPTH=1`;
  - TX: 5 nhóm test;
  - RX: 9 nhóm test;
  - `uart_top`: FIFO TX/RX và error metadata;
  - loopback: 7 nhóm test.

### Quartus Prime Lite 20.1

- Analysis & Synthesis cho `uart_loopback_top`: **0 lỗi, thành công**.
- Kết quả sau synthesis: 270 logic cell và 17 RAM segment (có thể thay đổi theo
  phiên bản/tool setting).
- 11 warning còn lại đều đã được phân loại:
  - 2 warning pass-through logic khi Quartus map FIFO show-ahead vào RAM;
  - 6 LED chưa dùng được buộc hằng 0;
  - `KEY[1]` được giữ trong board-style port nhưng chưa dùng;
  - các warning cha/tổng hợp tương ứng.
- Full fitter, TimeQuest và file programming chưa chạy vì pin vật lý cố ý để
  trống cho đến khi người dùng chốt chân GPIO thực tế trong `quartus/pins.qsf`.
