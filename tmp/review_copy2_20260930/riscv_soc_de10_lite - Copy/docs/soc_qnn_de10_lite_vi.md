# SoC ước lượng SOC bằng QNN trên DE10-Lite

> Cập nhật 2026-09-28: tài liệu này mô tả cấu hình hiện tại dùng **INA228**.
> Firmware đã có kiểm thử C và end-to-end RTL; chưa xác minh hệ thống trên board.
> Xem [hướng dẫn firmware INA228](firmware_ina228_vi.md),
> [báo cáo freeze/ISA](bao_cao_freeze_isa_soc_vi.md) và
> [quy trình thu bằng chứng trên board](kiem_chung_board_vi.md).

## 1. Điều gì được kế thừa từ bài báo

Bài báo là nguồn ý tưởng hệ thống, không phải đặc tả RTL bắt buộc. Các điểm được
giữ lại là:

- cửa sổ thời gian gồm 20 mẫu;
- mỗi mẫu có 4 đặc trưng: điện áp, dòng, nhiệt độ và khoảng thời gian;
- flatten thành vector 80 phần tử;
- mạng fully-connected `80 → 16 → 8 → 1`;
- ReLU ở hai lớp ẩn, output tuyến tính;
- weight/activation INT8, bias/accumulator INT32;
- lấy mẫu và xuất kết quả định kỳ, firmware điều phối cảm biến và accelerator.

Các điểm được chủ động thay đổi: FPGA là MAX 10 DE10-Lite; CPU là core RV32I
tự xây; bus và ngoại vi là RTL riêng; không dùng Arty Z7, LiteX hay VexRiscv.
Sự khác nhau này là chủ đích để phù hợp công cụ Quartus Prime 20.1 và tài nguyên
trên kit.

## 2. Luồng dữ liệu hệ thống

```text
INA228 --I2C--> firmware RV32I --> cửa sổ 20 x 4 --> lượng tử INT8
                                              |
                                              v
                                      QNN 80-16-8-1
                                              |
                                              v
                                  SOC 0..1000 (0,1 %/LSB)
                                      |              |
                                     LED           UART TX
```

CPU thực hiện phần điều khiển có nhánh và giao thức; accelerator thực hiện phần
MAC đều đặn. Cách chia này giữ RTL QNN nhỏ, dễ kiểm thử và cho phép thay đổi
logic lấy mẫu mà không phải tổng hợp lại datapath toán học.

Nhiệt độ trong bốn feature là **nhiệt độ pin**, cần nguồn đo hợp lệ riêng.
DIETEMP của INA228 chỉ là nhiệt độ die. Firmware board hiện chưa có nguồn nhiệt
độ pin nên chưa được phép tạo feature/chạy suy luận từ dữ liệu cảm biến thật.

## 3. `rv32_soc`: bus fabric và lỗi truy cập

Core có hai master Harvard. Instruction master chỉ nối ROM. Data master được
decode tới ROM, SRAM hoặc peripheral theo bảng trong README. Mỗi slave trả
`ready`, `rdata`, `err`; địa chỉ không ánh xạ vẫn được trả `ready+err` để CPU
nhận access fault thay vì treo vô hạn.

ROM hai cổng cho phép IF đọc instruction trong lúc load `.rodata`. SRAM dùng
byte enable tương ứng `SB/SH/SW`. Chỉ số mảng SRAM được thu hẹp theo độ sâu vật
lý; đây là điều kiện quan trọng để Quartus nhận dạng M9K.

## 4. `qnn_soc_accelerator`: nguyên tắc tính toán

Với một neuron, phần cứng tính:

```text
acc = bias + Σ(input[i] × weight[i])
hidden = sat_int8(ReLU(acc >>> SHIFT))
result = clamp(acc_out >>> OUT_SHIFT, 0, 1000)
```

Chỉ có một đường MAC được tái sử dụng theo thời gian. Mỗi trọng số lớp 1 và lớp
2 cần một chu kỳ fetch ROM rồi một chu kỳ MAC. Tổng số phép nhân là
`80×16 + 16×8 + 8 = 1416`; đổi lại, trọng số lớn nằm trong M9K và số DSP cần
thiết thấp. Đây là lựa chọn area-first phù hợp DE10-Lite, không phải kiến trúc
song song tối đa.

Hai lớp ẩn có activation 8 bit. ReLU loại giá trị âm, phép saturate ngăn wrap
về số âm khi vượt 127. Accumulator 32 bit phải được kiểm tra overflow trong
pipeline huấn luyện; RTL cố ý không dùng số thực.

### Thanh ghi QNN

| Offset | Tên | Ý nghĩa |
|---:|---|---|
| `0x000` | CONTROL | bit0 start, bit1 clear done |
| `0x004` | STATUS | bit0 busy, bit1 done, bit2 model_loaded |
| `0x008` | RESULT | 0..1000, đơn vị 0,1 %SOC |
| `0x00C` | CYCLES | latency lần chạy hiện tại/gần nhất |
| `0x010` | CONFIG | mã hóa 80, 16, 8, 1 |
| `0x100..0x23C` | FEATURE[0..79] | byte thấp là INT8 |

Feature chỉ được ghi khi accelerator không busy. Ghi feature lane0 hoặc START
trong lúc busy giữ ready=0 tới khi rảnh; dữ liệu/lệnh được thực hiện tại handshake,
không báo success rồi bỏ qua. done giữ tới clear hoặc start mới. Bus SoC đăng ký
cả request/response; xem [đặc tả 3.0](dac_ta_core_bus_ngoai_vi.md) cho UART RX,
page MMIO 4 KiB và GPIO 8 LED.

## 5. Ngoại vi

`soc_i2c_master` làm việc theo từng byte. Firmware ghi DATA, sau đó ghi CMD với
bit EXECUTE và tổ hợp START/STOP/READ/NACK. Chân ra chỉ có tín hiệu “kéo thấp”;
top-level chuyển thành open-drain. Khi SCL được nhả, FSM chỉ đi tiếp sau khi
`scl_i` thực sự cao nên chấp nhận clock stretching; thiết kế hiện không hỗ trợ
multi-master/arbitration.

`soc_uart` cung cấp TX/RX 8N1 với FIFO, read-pop RX và cờ lỗi W1C; bên trong dùng
`soc_uart_tx`, `uart_rx` và `uart_rx_fifo`. `soc_timer` là counter 64 bit phục
vụ polling chu kỳ lấy mẫu, đọc TIME_LO chốt TIME_HI. `soc_gpio` nối switch và
8 LED; hai LED cao được top-level dành cho busy và trap để quan sát nhanh.
I²C có watchdog và lệnh phục hồi bus; firmware giới hạn thời gian chờ và số lần
thử lại. Contract thanh ghi chi tiết nằm trong đặc tả tích hợp.

## 6. Firmware

`firmware/main.c` thực hiện luồng sau:

1. kiểm tra cấu hình, ID và calibration của INA228;
2. đọc VBUS, CURRENT, VSHUNT và DIETEMP, quy đổi bằng số nguyên;
3. ghi mẫu vào vòng đệm 20 phần tử, giữ validity và khoảng thời gian thực;
4. khi đủ 20 mẫu và có nhiệt độ pin hợp lệ, tạo 80 feature INT8, ghi QNN và start;
5. chờ done có timeout, đọc RESULT, xuất UART và LED;
6. chờ 10 giây bằng timer trước vòng tiếp theo; lỗi/mất mẫu xóa cửa sổ theo contract.

`firmware/include/soc_map.h` là contract MMIO dùng chung ở phía phần mềm.
`model_config.h` chứa center/scale của bước lượng tử đầu vào. Driver và pipeline
được kiểm thử bằng `scripts/run_firmware_tests.py`; script dùng toolchain
`riscv64-unknown-elf-*` trong Linux/WSL với đích RV32I, tạo ELF/BIN/HEX/MIF.

`firmware/build/boot.*` vẫn là ảnh demo baseline mà top Quartus tham chiếu.
Firmware C mới được build riêng trong `firmware/build/verify_*`; fixture RTL ở
`tb/soc/firmware_assets`. Chạy test không có nghĩa firmware C đã được nạp board.
Địa chỉ I²C, shunt và CURRENT_LSB trong `board_config.h` chưa cấu hình; firmware
board hiện báo `CONFIG_REQUIRED`. Sau khi cấu hình cảm biến đúng, vẫn cần nguồn
nhiệt độ pin; nếu thiếu thì báo `CELL_TEMP_REQUIRED` khi đủ cửa sổ.

## 7. Đưa model thật vào thiết kế

Model được cài hiện có manifest tại `firmware/model/model_manifest.json`, gồm
topology, center/scale, quy ước dòng dương khi sạc và phân chia dataset. Quy trình
dưới đây áp dụng khi huấn luyện hoặc thay model; không coi kết quả dataset là
bằng chứng độ chính xác trên board:

1. chuẩn hóa dataset CALCE thành các chuỗi liên tục có nhãn SOC;
2. chia train/validation/test theo cell hoặc cycle trước khi tạo cửa sổ để tránh
   rò rỉ dữ liệu giữa các tập;
3. train mạng float 80–16–8–1 và lưu metric MAE/RMSE/max error;
4. lượng tử hóa với dữ liệu calibration, chọn ba shift sao cho activation không
   bão hòa quá mức và accumulator không overflow;
5. chạy một reference model integer bit-exact;
6. export đúng thứ tự `weight[neuron*input_count + input]` sang các file HEX/MIF;
7. dùng cùng vector vàng cho reference, RTL accelerator và test toàn SoC;
8. chỉ sau khi cả ba khớp mới thay model đang dùng trong project Quartus.

Không nên đánh giá chỉ bằng độ lệch float-vs-quantized trung bình. Cần thống kê
tỷ lệ saturate, dải accumulator, sai số theo từng nhiệt độ/cycle và trường hợp
SOC gần 0/100%.

## 8. Tư duy của testbench

- `tb_rv32_qnn_soc_accelerator`: nạp một model vàng thưa, từ đó kết quả 84 có
  thể tính tay; kiểm tra busy/done/cycle/MMIO và khóa feature khi đang chạy.
- `tb_rv32_soc`: chạy instruction thật qua pipeline, ghi feature/start QNN, poll
  done, đọc result, ghi LED, phát UART rồi EBREAK.
- `tb_rv32_i2c_master`: kiểm tra START/STOP, thứ tự MSB-first, ACK/NACK, read,
  done/clear và wait-state khi ghi CMD lúc busy.
- `tb_rv32_core_traps`: reset và kích lần lượt đủ chín cause; kiểm tra trap sticky
  và instruction lỗi không retire.
- `tb_rv32_firmware_e2e`: chạy firmware C qua CPU, driver INA228 giả lập ở chân
  I²C, so khớp feature/kết quả QNN và byte UART; fault phải chặn suy luận.
- Test UART RX/FIFO, I²C recovery và reset có trong regression cùng các cấu hình
  stress. Script lấy source từ QSF SoC để không trộn project UART độc lập.

Testbench model vàng nhỏ chỉ chứng minh tính đúng của datapath và protocol. Độ
chính xác SOC thực tế phải được chứng minh bằng dataset độc lập và model đã
huấn luyện.

## 9. Trình tự mang lên board

Thực hiện theo [biên bản kiểm chứng board](kiem_chung_board_vi.md): chốt ảnh
firmware/model, kiểm tra chân và reset, đo UART/I²C, đối chiếu dữ liệu với dụng
cụ đo rồi mới thử toàn luồng. Mỗi bước phải có log hoặc capture và tiêu chí đạt.
Firmware baseline và firmware C có hành vi boot khác nhau; LED trap bật sau
EBREAK có thể là kết thúc demo có chủ đích, không dùng tiêu chí “LED luôn tắt”.

Chỉ ghi “đã xác minh hệ thống trên phần cứng” sau khi có đủ bằng chứng cho cấu
hình và luồng được công bố. Hiện trạng vẫn là đã kiểm thử mô phỏng, có báo cáo
timing baseline; kiểm chứng phần cứng còn chờ.
