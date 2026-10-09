from pathlib import Path
def replace(p,old,new):
    s=p.read_text(encoding='utf-8')
    assert old in s,(p,old[:90])
    p.write_text(s.replace(old,new),encoding='utf-8')
def section(p,start,end,new):
    s=p.read_text(encoding='utf-8');a=s.index(start);b=s.index(end,a)
    p.write_text(s[:a]+new+'\n\n'+s[b:],encoding='utf-8')
p=Path('docs/dac_ta_core_bus_ngoai_vi.md')
replace(p,'Phiên bản 2.1','Phiên bản 3.0')
replace(p,'GPIO, UART **TX 8N1**','GPIO, UART **TX/RX 8N1**')
replace(p,'UART RX, DMA, arbitration','DMA, arbitration')
replace(p,'Firmware và tài liệu','Firmware và tài liệu') if False else None
section(p,'Fabric tổ hợp,','## 4. ROM và SRAM', '''Fabric có thanh ghi request và response, một giao dịch outstanding. Thứ tự lane:
`0 ROM, 1 SRAM, 2 GPIO, 3 UART, 4 I²C, 5 QNN, 6 timer`.
Chỉ một `slave_req` được bật. Trong reset/idle/response không chọn slave.
Tại cạnh N chụp request; slave zero-wait hoàn tất sớm nhất N+1; CPU nhận
response ở N+2. Slave chờ thêm W clock thì CPU hoàn tất ở N+W+2.
Request kế tiếp có thể giữ req liên tục nhưng payload mới chỉ chụp ở N+W+3.
Không chụp lại request cũ ở cạnh trả response. Ready/error/data CPU chỉ lấy từ
response đã chốt, không phụ thuộc trực tiếp slave hiện tại.

Địa chỉ sai, lệch word hoặc ghi ROM trả lỗi đã đăng ký, không chọn slave.
MMIO giải mã `addr[31:12]`; từng peripheral nhận **đủ offset 12 bit** và báo lỗi
cho register chưa định nghĩa. Không mirror thanh ghi ở offset cao.

| Khoảng địa chỉ mặc định | Đích | Quyền |
|---|---|---|
| `0000_0000..0000_7FFF` | ROM 8192 word | Fetch/read |
| `1000_0000..1000_1FFF` | SRAM 2048 word | Read/write |
| `2000_0000..2000_0FFF` | GPIO | Theo thanh ghi |
| `2000_1000..2000_1FFF` | UART TX/RX | Theo thanh ghi |
| `2000_2000..2000_2FFF` | I²C | Theo thanh ghi |
| `2000_3000..2000_3FFF` | QNN | Theo thanh ghi |
| `2000_4000..2000_4FFF` | Timer | Theo thanh ghi |

ROM_WORDS/RAM_WORDS phải dương, vùng nhớ không chồng lấn MMIO. Reset hủy
transaction pending nhưng không rollback side effect đã xảy ra ở slave trước
khi CPU nhận response. Instruction vẫn nối trực tiếp ROM, không qua data bus.
''')
replace(p,'Cổng data ROM và SRAM chụp yêu cầu ở N,','Ở giao tiếp slave, cổng data ROM và SRAM chụp yêu cầu ở N,')
replace(p,'các cổng này không đạt một word mỗi chu kỳ.','các cổng này không đạt một word mỗi chu kỳ. Tính từ cạnh bus chụp request CPU,\nROM/RAM hoàn tất CPU sau 4 clock: bus thêm một cạnh chụp và một cạnh trả response.')
section(p,'## 5. GPIO','## 7. I²C', '''## 5. GPIO (`0x2000_0000`)

| Offset | Thanh ghi | Quyền / reset | Ý nghĩa |
|---|---|---|---|
| `0x000` | LED | RW / 0 | `GPIO_LED_WIDTH` bit thấp, mặc định 8 |
| `0x004` | SWITCH | RO | 10 switch đã đồng bộ |

Slave zero wait. Mỗi lane chỉ cập nhật bit tồn tại; phần vượt độ rộng đọc 0,
ghi bỏ qua như reserved bits. Tham số hỗ trợ 1..32 bit, test cấu hình 8 và 10.
Board cố định `LEDR[7:0]=GPIO`, `LEDR[8]=QNN_BUSY`, `LEDR[9]=CPU_TRAP`.
Header firmware khai báo `GPIO_LED_WIDTH=8`, không coi hai LED debug là GPIO.

## 6. UART TX/RX (`0x2000_1000`)

| Offset | Thanh ghi | Quyền / reset | Ý nghĩa |
|---|---|---|---|
| `0x000` | TX_DATA | RW / đọc 0 | Ghi lane0 nhận một byte vào TX/FIFO |
| `0x004` | STATUS | RO / `0x09` | Bảng bit bên dưới |
| `0x008` | RX_DATA | RO/pop | Đọc một byte `[7:0]`; rỗng trả access fault |
| `0x00C` | ERRORS | RW/W1C / 0 | Đọc lỗi ở `[7:5]`; ghi 1 lane0 xóa bit tương ứng |

| Bit STATUS | Tên | Ý nghĩa |
|---|---|---|
| 0 | TX_READY | Có chỗ nhận byte TX |
| 1 | TX_BUSY | FIFO TX hoặc serializer còn dữ liệu chưa phát hết |
| 2 | RX_VALID | FIFO RX có byte |
| 3 | RX_EMPTY | FIFO RX rỗng |
| 4 | RX_FULL | FIFO RX đầy |
| 5 | RX_OVERRUN | Byte mới bị drop khi FIFO đầy, sticky |
| 6 | RX_FRAMING_ERROR | Stop bit thấp, frame bị loại, sticky |
| 7 | RX_FALSE_START | Start không còn thấp tại giữa bit, sticky |

TX giữ 8N1, FIFO mặc định 4 byte ngoài serializer. `TX_FIFO_DEPTH=0` phục hồi
chế độ không FIFO; module `soc_uart_tx` và test cũ vẫn giữ. TX_DATA lane0 chờ
khi hết chỗ; no-op strobe không chờ. Chờ TX_BUSY=0 để flush, TX_READY không
đồng nghĩa dây đã idle. Reset bỏ FIFO và frame, đưa TX về mức cao.

RX có module `uart_rx`, `uart_rx_fifo`, wrapper `soc_uart`. Đồng bộ hai FF
ngay trong RX; lấy mẫu giữa start, giữa từng bit và giữa stop bằng clock hệ
thống, không dùng bộ chia 16x. Bộ chia là `round(CLOCK_HZ/BAUD)`, cần ít nhất
8 clock/bit. Đã kiểm tra divisor 8/9/100; sai lệch ±3% kiểm tại divisor 100.
Không có majority voting hoặc bảo đảm chống mọi loại glitch.

FIFO RX mặc định 16 byte; hỗ trợ độ sâu không phải lũy thừa 2. Đọc RX_DATA chỉ
pop tại `req && ready && !err`, mỗi transaction đúng một byte. Đầy và pop/push
cùng cạnh không mất byte; nếu không pop thì bỏ byte mới và đặt overrun.
Event lỗi mới thắng clear cùng cạnh. Chỉ ghi lane0 mới xóa ERRORS. STATUS và
RX_DATA là RO, ghi cả zero-strobe vẫn fault. Mọi offset khác, kể cả trong
page 4 KiB, fault. Phần mềm poll RX_VALID trước đọc RX_DATA. Chưa có IRQ UART.

Board: TX=`PIN_V9` (JP1 GPIO[2]), RX=`PIN_W9` (JP1 GPIO[3]), RX có pull-up khi
không nối dây. SDC chỉ bỏ timing từ RX pad tới FF đồng bộ đầu tiên.
''')
# QNN contract bổ sung trước timer.
section_text='''## 7.1. QNN MMIO (`0x2000_3000`)

`CONTROL=0x000`, `STATUS=0x004`, `RESULT=0x008`, `CYCLES=0x00C`,
`CONFIG=0x010`; 80 feature ở `0x100..0x23C`, mỗi feature dùng lane0 của word.
Ghi feature lane0 hoặc CONTROL.START khi busy giữ ready=0 đến QNN rảnh.
Write chỉ xảy ra tại handshake thành công; không báo success rồi bỏ dữ liệu.
No-op strobe, read và CLEAR_DONE không kèm START không chờ. Offset sai/lệch
word hoặc ghi RO trả fault. Reset chặn handshake. Datapath/model giữ nguyên.

'''
replace(p,'## 8. Timer',section_text+'## 8. Timer')
replace(p,'## 9. Kiểm thử và tiêu chí hoàn tất','''## 8.1. Reset board

`reset_controller` dùng power-up value của FF MAX10/Quartus để giữ POR
`POR_CYCLES=1024` clock sau configuration, rồi thêm 3 clock đồng bộ nhả reset.
KEY[0] assert bất đồng bộ, nhả qua cùng chuỗi 3 FF. Không cần nhấn KEY lúc bật
board. Các state timer/QNN/UART/core được reset bằng tín hiệu chung.
POR không phải mạch phát hiện brown-out hoặc mất clock; phụ thuộc clock board.

## 9. Kiểm thử và tiêu chí hoàn tất''')
p=Path('docs/giao_tiep_rtl_vi.md')
section(p,'Bộ giải mã tổ hợp,','### 4.4. Bố trí', '''Data bus một master, một transaction outstanding, có thanh ghi request và
response. Giao thức core `req/ready/err` giữ nguyên. `soc_bus` nay có `clk_i`,
`wdata_i/wstrb_i` và output payload `slave_addr_o/slave_we_o/slave_wdata_o/
slave_wstrb_o`. Tất cả slave dùng payload này thay cho dmem_* trực tiếp.

| Lane | Slave | Slice |
|---:|---|---|
| 0 | ROM | `[31:0]` |
| 1 | SRAM | `[63:32]` |
| 2 | GPIO | `[95:64]` |
| 3 | UART TX/RX | `[127:96]` |
| 4 | I²C | `[159:128]` |
| 5 | QNN | `[191:160]` |
| 6 | Timer | `[223:192]` |

```mermaid
flowchart LR
    CPU[Core data request] --> RQ[Request register]
    RQ --> DEC[Address decoder]
    DEC --> SL[One selected slave]
    SL --> RP[Response register]
    RP --> CPU
```

| Cạnh | Hoạt động slave zero-wait |
|---|---|
| N | IDLE chụp toàn bộ request CPU |
| N+1 | ACCESS: slave commit, bus chụp rdata/err và ngừng req slave |
| N+2 | RESPONSE: CPU hoàn tất; không capture lại payload cũ |
| N+3 | Sớm nhất chụp request kế, req CPU có thể giữ cao liên tục |

Slave wait W clock làm N+1 và N+2 trễ thêm W clock. Request/payload tới slave
giữ nguyên suốt ACCESS. Ready/err/data CPU lấy từ register, không nối tổ hợp
ngược từ ngoại vi về pipeline. Reset/idle không có response; ready chỉ cao ở
RESPONSE, master phải giữ req tới cạnh đó. Không hỗ trợ master tự hủy request
ngoài reset; không có nhiều transaction outstanding hay reordering.

MMIO giải mã page `addr[31:12]`. Từng peripheral nhận đủ offset 12 bit và trả
lỗi cho register sai, không mirror ở offset cao. Unmapped/unaligned/write-ROM
cũng đi qua response register và không chọn slave. Dữ liệu lỗi bằng 0.
Reset hủy pending nhưng không rollback side effect đã commit ở slave.
Register map chi tiết nằm tại [đặc tả SoC 3.0](dac_ta_core_bus_ngoai_vi.md).
''')
replace(p,'Payload ghi được\nnối trực tiếp từ core đến slave; chỉ `req` của slave được chọn mới có hiệu lực.',
        'Payload ghi được\nchốt tại bus trước khi đến slave; chỉ `req` của slave được chọn mới có hiệu lực.')
replace(p,'Refactor ngày 25/09/2026 giữ nguyên tên/độ rộng cổng bên ngoài, chỉ số lane,','Refactor ngày 25/09/2026 (baseline lịch sử) giữ nguyên tên/độ rộng cổng bên ngoài, chỉ số lane,')
replace(p,'## 5. Giao tiếp nội bộ pipeline','''Nâng cấp P0/P1 ngày 26/09/2026 giữ handshake core/ISA, đổi interface nội bộ
bus và offset MMIO lên 12 bit; GPIO board là 8 bit, SoC thêm uart_rx_i.
Mọi nơi instantiate SoC cần nối RX idle=1 nếu không dùng. Xem
[báo cáo P0/P1](bao_cao_kien_truc_p0_p1_vi.md) để biết thay đổi và kiểm chứng.

## 5. Giao tiếp nội bộ pipeline''')
p=Path('README.md')
replace(p,'UART TX có FIFO','UART TX/RX có FIFO')
replace(p,'23 testbench','28 testbench'); replace(p,'26 khi chạy toàn bộ','31 khi chạy toàn bộ')
replace(p,'59 lượt chạy trên 26 testbench','69 lượt chạy trên 31 testbench')
replace(p,'scope All chạy 26 testbench','scope All chạy 31 testbench')
replace(p,'GPIO/UART/I²C/timer chỉ decode 16 byte đầu page; offset còn lại trả access\nfault, không mirror thanh ghi. Chi tiết quyền đọc/ghi và byte-enable xem đặc tả.',
'''Mỗi MMIO có page 4 KiB; slave nhận offset 12 bit, offset chưa định nghĩa trả
fault và không mirror thanh ghi. Data bus chốt cả request và response, một
transaction outstanding. GPIO phần mềm có 8 LED; LED[8:9] là debug.
Chi tiết quyền đọc/ghi, byte-enable và UART RX xem đặc tả.''')
replace(p,'`-Stress` chạy thêm 16 seed', '`-Stress` có 38 lượt bổ sung, gồm 16 seed')
replace(p,'Test mới kiểm tra timeout, phục hồi bus và lỗi ghi\nMMIO truyền về trap CPU. Kết quả mới nhất xem mục 9 của',
'''Test mới kiểm tra timeout, phục hồi bus, UART RX/overrun/framing/baud mismatch,
POR, forwarding qua registered bus và lỗi MMIO truyền về trap CPU.
Kết quả mới nhất xem [báo cáo P0/P1](docs/bao_cao_kien_truc_p0_p1_vi.md) và mục 10 của''')
replace(p,'Top-level là `de10_lite_top`. `KEY[0]` reset active-low;',
'''Top-level là `de10_lite_top`. POR tự giữ reset 1024+3 clock sau cấu hình;
`KEY[0]` reset active-low, nhả đồng bộ;''')
replace(p,'`UART_TX` được gán vào chân header `PIN_V9`.','`UART_TX` dùng `PIN_V9` (GPIO[2]), `UART_RX` dùng `PIN_W9` (GPIO[3]).')
replace(p,'## Tài liệu\n','## Tài liệu\n\n- [Báo cáo kiến trúc P0/P1: thay đổi, kiểm thử và timing trước/sau](docs/bao_cao_kien_truc_p0_p1_vi.md).\n')
