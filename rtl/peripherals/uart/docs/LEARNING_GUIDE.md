# Hướng dẫn làm chủ project

Tài liệu này mô tả cách suy luận về thiết kế, không chỉ cách chạy nó. Nên mở
song song RTL và testbench tương ứng khi đọc.

## 1. Mô hình tinh thần

Hãy tách project thành bốn lớp:

```text
Lớp vật lý     : uart_rx_i / uart_tx_o, idle=1
Lớp symbol     : baud tick, start/data/stop, majority vote
Lớp byte       : tx_data/rx_data + framing/overrun
Lớp luồng      : ready/valid + FIFO + backpressure
```

Một bug ở lớp dưới thường biểu hiện ở lớp trên. Ví dụ tick sai làm bit sai độ
dài; bit sai độ dài làm majority vote trượt; kết quả cuối cùng có thể chỉ hiện
ra như framing error hoặc byte sai.

## 2. Theo một byte ở đường TX

Ví dụ application gửi `8'hA5` (`1010_0101`):

1. Application đặt `tx_data=A5`, `tx_valid=1`.
2. Khi `tx_ready=1`, TX FIFO chốt byte tại cạnh lên.
3. FIFO bật `read_valid`; `uart_tx` chấp nhận byte khi core idle.
4. `uart_tx` chốt byte vào `data_reg`, kéo `uart_tx_o=0` ngay tại cạnh đó.
5. Baud counter đếm đủ một bit rồi chuyển sang `data_reg[0]`.
6. Các bit phát theo thứ tự D0..D7: `1,0,1,0,0,1,0,1`.
7. Sau D7, output chuyển high cho stop bit.
8. Hết stop bit, FSM về IDLE và `tx_done` pulse một clock.
9. Nếu FIFO còn byte, handshake byte tiếp theo xảy ra ở một cạnh sau đó.

Các invariant nên nhìn trên waveform:

- `uart_tx_o` chỉ đổi ở cạnh lên `clk`;
- mỗi symbol dài đúng `floor(CLOCK_FREQ/BAUD_RATE)` clock;
- `tx_done` chỉ xuất hiện sau một stop bit hoàn chỉnh;
- `tx_busy` không hạ giữa các byte còn nằm trong FIFO.

## 3. Theo một byte ở đường RX

1. `uart_rx_i` đi qua hai flip-flop để giảm rủi ro metastability.
2. Mức low khi IDLE tạo một start candidate và restart pha sample counter.
3. RX lấy ba mẫu quanh tâm start bit.
4. Majority high nghĩa là false start; FSM bỏ candidate và về IDLE.
5. Majority low xác nhận start; FSM nhận D0..D7, mỗi bit bằng majority ba mẫu.
6. Stop bit được lấy mẫu tương tự.
7. Byte và cờ framing được đưa vào output slot của `uart_rx`.
8. RX FIFO handshake với slot này và lưu `{framing_error, data}` cùng nhau.
9. Application đọc đầu FIFO bằng `rx_valid && rx_ready`.

Nếu stop bit low, byte vẫn được xuất với `framing_error=1`. FSM sau đó chờ một
mức high đã đồng bộ trước khi re-arm. Đây là lý do BREAK dài chỉ tạo một event.

## 4. Hiểu backpressure và overrun

`valid` mô tả “producer đang có dữ liệu”; `ready` mô tả “consumer có thể nhận”.
Không bên nào được suy diễn transfer nếu chỉ một tín hiệu bằng 1.

Ở RX có hai tầng chứa dữ liệu:

```text
uart_rx output slot (1 byte) -> RX FIFO (RX_FIFO_DEPTH byte)
```

Khi application dừng đọc, FIFO đầy trước, sau đó output slot của RX bị giữ.
Nếu một frame nữa hoàn tất lúc cả hai đều chưa giải phóng, frame mới nhất bị
drop và `rx_overrun_error` pulse. Byte cũ luôn được bảo toàn.

Ở TX, application chỉ được coi byte đã gửi vào core sau handshake với FIFO.
Một pulse `tx_valid` khi `tx_ready=0` không phải giao dịch và sẽ mất nếu
application không giữ lại.

## 5. Reset và CDC

Nút nhấn không cùng pha với clock. `reset_sync` cho phép reset assert ngay nhưng
dịch hai bit `1` qua hai flip-flop khi nhả reset. Vì vậy logic nội bộ không thoát
reset giữa chu kỳ.

RX cũng bất đồng bộ. `uart_rx_sync` chỉ giải quyết một bit; không sao chép mô
hình 2FF này cho một bus nhiều bit vì từng bit có thể ổn định ở chu kỳ khác nhau.

Khi debug reset, kiểm tra theo thứ tự:

1. `KEY[0]` có thực sự xuống low không;
2. `rst_n` nội bộ có xuống ngay không;
3. khi KEY lên high, `rst_n` có chờ đủ hai cạnh clock không;
4. `tx_ready/read_valid/write_ready` có bị gate đúng trong reset không.

## 6. Cách đọc testbench

Mỗi testbench có ba vai trò:

- driver tạo stimulus ở cạnh xuống để tránh race với DUT;
- monitor lấy mẫu giữa bit hoặc tại handshake;
- scoreboard/report so sánh độc lập với thanh ghi nội bộ DUT.

Thứ tự nên đọc:

1. các `localparam` để biết timing;
2. instance DUT để biết interface;
3. task driver;
4. task checker;
5. khối `initial` để thấy test scenario;
6. watchdog và `TEST_RESULT` để hiểu điều kiện hoàn thành.

Khi thêm test mới, luôn đảm bảo FAIL tạo marker `TEST_RESULT: FAIL:`; script CI
không tin riêng exit code của `$finish`.

## 7. Quy trình debug thực tế

Nếu test RX sai byte, quan sát theo thứ tự:

```text
uart_rx_i
-> uart_rx_sync
-> state / sample_tick / sample_count
-> sample_a / sample_b
-> data_reg / bit_index
-> rx_valid / rx_ready / rx_data
```

Nếu TX sai frame:

```text
tx_valid / tx_ready / tx_data
-> TX FIFO read_valid/read_ready/read_data
-> uart_tx state / baud_tick / bit_index
-> uart_tx_o / tx_done
```

Build VCD khi cần bằng cách thêm define `DUMP_VCD` vào lệnh compile ModelSim.
Mặc định VCD tắt để lint và batch test không phụ thuộc system task của một
simulator cụ thể.

## 8. Thay đổi project một cách an toàn

### Đổi baud hoặc clock

1. Đổi `CLOCK_FREQ`/`BAUD_RATE` ở top.
2. Tính cả TX divider và RX sample divider theo công thức trong đặc tả.
3. Kiểm tra sai số phần trăm ở cả hai hướng.
4. Chạy toàn bộ test; thêm test với parameter mới nếu đó là cấu hình sản phẩm.
5. Cập nhật SDC nếu clock vật lý thay đổi.

### Đổi độ sâu FIFO

Chỉ đổi `TX_FIFO_DEPTH`/`RX_FIFO_DEPTH`. Depth không cần là power-of-two. Với
FIFO lớn, xem báo cáo inference RAM và timing vì show-ahead read là tổ hợp.

### Ghép với application logic

- TX: application là producer, giữ payload đến handshake.
- RX: application là consumer, có thể giữ `rx_ready=1` liên tục nếu luôn nhận.
- Xử lý `rx_framing_error` cùng cạnh với byte, không đọc nó như sticky flag.
- Nếu cần thống kê overrun, latch hoặc đếm pulse `rx_overrun_error` bên ngoài.

### Thêm parity

Đây không phải thay đổi một dòng. Cần đồng thời sửa state/bit timing của TX,
state/majority/error metadata của RX, độ rộng payload RX FIFO, interface top,
đặc tả và tất cả monitor testbench. Giữ compatibility bằng parameter rõ ràng
hoặc tạo module mới trước khi thay API hiện tại.

## 9. Bài tập để tự kiểm chứng mức độ làm chủ

1. Giải thích vì sao RX mặc định dùng 432 clock/bit còn TX dùng 434 nhưng vẫn
   nhận đúng một frame.
2. Vẽ timeline ready/valid khi RX FIFO full và application bắt đầu đọc lại.
3. Thêm test inject một glitch chỉ trúng một trong ba sample, rồi glitch trúng
   hai sample; dự đoán kết quả trước khi chạy.
4. Thêm counter số byte TX hoàn tất dựa trên `tx_done`.
5. Chọn pin thật, chạy fitter/TimeQuest và giải thích từng warning còn lại.

