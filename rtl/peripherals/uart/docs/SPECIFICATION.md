# Đặc tả UART core

## 1. Phạm vi

Thiết kế hỗ trợ UART full-duplex cấu hình cố định 8N1:

- mức idle/mark: `1`;
- start bit: `0`;
- 8 data bit, truyền LSB trước;
- không parity;
- một stop bit: `1`;
- TX và RX dùng chung clock hệ thống nhưng hoạt động độc lập;
- không tạo clock mới, chỉ dùng tick như clock-enable.

Parity, số data bit khác 8, nhiều stop bit, hardware flow control và auto-baud
không thuộc phạm vi hiện tại.

## 2. Tham số

| Tham số | Mặc định | Điều kiện |
| --- | ---: | --- |
| `CLOCK_FREQ` | 50,000,000 | số nguyên dương |
| `BAUD_RATE` | 115,200 | số nguyên dương, không lớn hơn clock |
| `OVERSAMPLE` | 16 | số nguyên `>= 4` |
| `TX_FIFO_DEPTH` | 16 | số nguyên `>= 1` |
| `RX_FIFO_DEPTH` | 16 | số nguyên `>= 1` |

Đối với RX phải có `BAUD_RATE <= CLOCK_FREQ / OVERSAMPLE`. Các biểu thức tham
số dùng kiểu `integer` 32-bit của Verilog; không dùng các giá trị có tích
`BAUD_RATE * OVERSAMPLE` vượt miền số nguyên có dấu 32-bit.

## 3. Tạo tick và sai số baud

`uart_baud_gen` dùng bộ chia nguyên:

```text
CLKS_PER_TICK = floor(CLOCK_FREQ / REQUESTED_RATE)
actual_tick_rate = CLOCK_FREQ / CLKS_PER_TICK
```

Tick là pulse tổ hợp một chu kỳ đếm, chỉ được dùng làm clock-enable tại cạnh
lên của `clk`. `restart` có ưu tiên hơn `enable` và đưa pha đếm về đầu.
`enable=0` giữ counter ở 0. Trong reset, `tick=0`.

Với cấu hình mặc định:

| Đường | Bộ chia | Tốc độ hiệu dụng | Sai số so với 115200 |
| --- | ---: | ---: | ---: |
| TX | 434 | 115207.37 baud | +0.0064% |
| RX sample | 27 | 1,851,851.85 sample/s | +0.4694% |
| RX theo bit (`/16`) | 432 clock/bit | 115740.74 baud | +0.4694% |

RX lấy mẫu giữa bit nên sai lệch nhỏ này được hấp thụ trong frame 8N1 mặc định.
Khi đổi clock/baud, người tích hợp phải tính lại sai số; project không tự bảo
đảm một cấu hình tùy ý nằm trong tolerance của thiết bị đối diện.

## 4. Giao thức ready/valid

Mọi stream tuân theo cùng một hợp đồng:

1. Transfer tại cạnh lên duy nhất khi `valid=1` và `ready=1`.
2. Producer được phép bật `valid` trước khi thấy `ready`.
3. Khi `valid=1, ready=0`, producer phải giữ `valid` và payload ổn định.
4. Consumer được phép giữ `ready=1` trước khi có dữ liệu.
5. Trong reset, các tín hiệu `ready` và `valid` của core bằng 0.

### TX application interface

| Tín hiệu | Hướng | Ý nghĩa |
| --- | --- | --- |
| `tx_data[7:0]` | vào | byte cần phát |
| `tx_valid` | vào | byte TX hợp lệ |
| `tx_ready` | ra | TX FIFO còn chỗ |
| `tx_busy` | ra | có byte trong FIFO hoặc serializer đang chạy |
| `tx_done` | ra | pulse một clock ở cuối stop bit của mỗi byte |

### RX application interface

| Tín hiệu | Hướng | Ý nghĩa |
| --- | --- | --- |
| `rx_data[7:0]` | ra | byte ở đầu RX FIFO |
| `rx_valid` | ra | `rx_data` và error bit hợp lệ |
| `rx_ready` | vào | application chấp nhận byte |
| `rx_framing_error` | ra | stop bit của chính byte này không hợp lệ |
| `rx_overrun_error` | ra | pulse một clock; frame mới nhất vừa bị loại |

`rx_data` và `rx_framing_error` chỉ có ý nghĩa khi `rx_valid=1`. Chúng ổn định
trong toàn bộ thời gian `rx_valid=1, rx_ready=0`.

## 5. UART TX

TX không có queue bên trong; queue nằm ở `uart_top`. Khi core TX nhận một
handshake, nó chốt byte và phát lần lượt start, D0..D7, stop. Mỗi symbol tồn
tại đúng `CLKS_PER_TICK` clock. `uart_tx_o` được đăng ký và giữ high khi idle
hoặc reset. Request đưa trực tiếp vào `uart_tx` trong lúc `tx_ready=0` phải được
giữ đến khi ready; `uart_top` giải quyết việc này bằng FIFO.

## 6. UART RX

Chân RX đi qua synchronizer hai flip-flop. Sau khi phát hiện mức low ở idle,
RX tạo `OVERSAMPLE` tick cho mỗi bit. Ba mẫu gần tâm được lấy tại counter:

```text
OVERSAMPLE/2 - 2
OVERSAMPLE/2 - 1
OVERSAMPLE/2
```

Giá trị bit là majority vote của ba mẫu. Start bit có majority high là false
start và bị bỏ. Stop bit có majority low vẫn xuất byte nhưng gắn
`framing_error=1`.

Sau framing error, FSM vào `WAIT_IDLE`: sample tick dừng và receiver chỉ re-arm
sau khi tín hiệu đã đồng bộ trở lại high. Vì vậy một BREAK low liên tục tạo tối
đa một frame lỗi trước khi đường truyền phục hồi.

Core RX có một output slot. Nếu frame mới hoàn tất khi slot cũ vẫn valid và
không được consume, frame mới bị loại và `overrun_error` pulse đúng một clock.
Trong `uart_top`, RX FIFO thường consume slot này ngay; overrun chỉ xảy ra sau
khi FIFO đầy, slot core bị giữ, rồi có thêm frame đến.

## 7. FIFO đồng bộ

`sync_fifo` là FIFO một clock, show-ahead:

- `read_data` phản ánh entry đầu khi `read_valid=1`;
- `read_data` là don't-care khi empty;
- push là `write_valid && write_ready`;
- pop là `read_valid && read_ready`;
- push và pop cùng cạnh được hỗ trợ, occupancy không đổi;
- pointer wrap tường minh nên depth không cần là lũy thừa của hai;
- khi full, `write_ready=0` (không có fall-through/bypass tại full).

Memory không reset; validity hoàn toàn do occupancy quản lý. Điều này tránh
reset một mảng lớn và giúp synthesis suy ra memory tốt hơn.

## 8. Reset và CDC

`reset_sync` nhận reset active-low bất đồng bộ, assert ngay và deassert sau hai
cạnh clock. Tất cả core còn lại yêu cầu `rst_n` đã được deassert đồng bộ.

`uart_rx_sync` là synchronizer 2FF riêng cho tín hiệu một bit. Không dùng cấu
trúc này để truyền bus nhiều bit. Các thanh ghi synchronizer có thuộc tính để
Quartus nhận diện; SDC cắt timing từ pin bất đồng bộ đến stage đầu.

## 9. Demo loopback

`uart_loopback_top` dùng `uart_top` và nối stream RX sang stream TX:

- byte hợp lệ được enqueue để phát lại;
- byte có framing error được consume nhưng không echo;
- framing/overrun được latch lên LED đến lần reset sau;
- FIFO hấp thụ burst ngắn và loại bỏ coupling trực tiếp giữa tốc độ RX/TX.

## 10. Tiêu chí verification

Suite tự động kiểm tra:

- period/restart/disable/reset của baud tick;
- FIFO reset, full/empty, ordering, wrap và push/pop đồng thời;
- frame TX, thứ tự bit, handshake, busy/done và reset;
- RX frame hợp lệ, false start, majority sampling, framing error, BREAK recovery,
  overrun, backpressure và frame liên tiếp;
- `uart_top`: FIFO TX nhiều byte, FIFO RX nhiều byte và alignment của error bit;
- loopback: dữ liệu phổ biến, frame liên tiếp và drop bad frame.

