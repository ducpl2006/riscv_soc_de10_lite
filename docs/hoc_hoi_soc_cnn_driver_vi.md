# Những ý tưởng đã áp dụng từ SoC_CNN_Driver

Đây là báo cáo đợt trước P0/P1. Trạng thái hiện tại đã có UART RX, bus đăng ký
và page MMIO 4 KiB; xem [báo cáo kiến trúc P0/P1](bao_cao_kien_truc_p0_p1_vi.md).

Ngày 26/09/2026. Nguồn tham khảo: `C:/Users/X1/Downloads/SoC_CNN_Driver.zip`.
Đã đọc source core, AXI4-Lite/APB4, I²C, UART và GPIO; trích source vào
`tmp/reference_soc_cnn/SoC_CNN_Driver`. Các nhận xét dưới đây dựa vào code và
mô phỏng tập trung, không coi comment hoặc báo cáo build đi kèm là chứng nhận.

| Ý tưởng trong bản tham khảo | Cách áp dụng vào SoC hiện tại |
|---|---|
| I²C có watchdog, bus recovery và status lỗi | Thêm vào FSM hiện có, giữ offset 16 byte; watchdog đếm lúc chờ chân bus, recovery kiểm tra SCL/SDA thực tế |
| UART có FIFO TX/RX | Thêm FIFO TX sâu 4 byte ngoài serializer, hỗ trợ cấu hình 0/1/3/4; giữ UART TX 8N1 và firmware polling |
| Tách giao dịch bus khỏi hoạt động kéo dài | UART nhận byte vào hàng đợi; I²C trả lỗi cho ghi đang chờ bị timeout, không thực hiện tác dụng phụ muộn |
| Byte-enable và trạng thái lỗi là một phần của interface | Test zero/upper strobes, reset, FIFO đầy; test lỗi timeout truyền qua bus tới precise trap CPU |
| Bộ nhân/chia RV32M riêng | Ghi nhận hướng mở rộng; chưa thêm extension khi chưa đo nhu cầu firmware và chi phí timing/DSP |
| Phân tầng AXI manager → interconnect → APB bridge → peripheral | Giữ nguyên native bus một master; cân nhắc adapter khi cần IP APB/AXI cụ thể, không có lợi ích đã đo để thay toàn bộ bus |

UART RX, interrupt/CSR và lọc glitch I²C chưa được thêm trong đợt này. Đồng bộ
hai FF hiện có ở board vẫn giữ nguyên. Thêm RX cần port/pin, thanh ghi dữ liệu,
cờ framing/overrun và driver; thêm IRQ cần thay đổi cả core.

## Những điểm phải sửa nếu tái sử dụng source tham khảo

1. **APB I²C làm mất byte không được chọn.** `APB4_I2C_Slave.v:68` mask các
   byte không có PSTRB thành 0; `I2C_Register_IF.v:97` ghi đè toàn thanh ghi.
   Probe ghi TIMEOUT=`0x00123456`, rồi ghi byte thấp `0xAB` thu được
   `0x000000AB` thay vì `0x001234AB`; zero-strobe cũng xóa thanh ghi.
   Strobe chỉ chọn các lane cần cập nhật theo
   [Arm AMBA APB, §3.2](https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3?token=).
   Vì vậy code mới ở dự án này vẫn chặn tác dụng phụ bằng lane/handshake.
2. **Memory có thể kẹt khi hoàn tất trong lúc MDU bận.**
   `Memory_Cycle.v:108` chốt `axi_done_latch` và hạ request;
   `Hazard_Unit.v:98` vẫn dùng MemReadM/MemWriteM gốc để tính chờ mem_ready.
   Khi ready là xung, latch đã hoàn tất nhưng stall vẫn giữ sau khi MDU hết bận.
   Probe ghép hai khối theo kết nối CPU tái hiện được tình huống này; chưa
   chạy chương trình end-to-end trên toàn bộ CPU tham khảo.
3. **Lỗi AXI chưa truyền về CPU.** `AXI_Manager.v` nhận `axi_bresp` và
   `axi_rresp` nhưng không sử dụng; đây là kết quả đọc source. Core hiện tại
   đã có access-fault và precise trap nên phải giữ đường lỗi này.
4. **Recovery cần quan sát SCL.** `I2C_Bus_Recovery.v` của bản tham khảo chỉ
   nhận SDA, dùng tick chung với bộ chia có pause. Cần kiểm tra quyền điều
   khiển clock và trường hợp SCL bị giữ thấp trước khi dùng lại. Bản mới chờ
   SCL cao thật và watchdog vẫn hoạt động trong recovery. NXP phân biệt rõ
   phục hồi SDA bằng xung clock với SCL kẹt cần reset/power-cycle thiết bị:
   [UM10204 §3.1.16](https://www.nxp.com/docs/en/user-guide/UM10204.pdf).

Probe trên source tham khảo không chỉnh sửa nằm tại
`tmp/reference_soc_cnn/tb_reference_review.v`; log riêng trong
`tmp/reference_soc_cnn/work/tb_reference_apb_strobe.log` và
`tb_reference_mem_mdu_stall.log`. Đây là test tái hiện lỗi, không thuộc
regression của RTL dự án.

## Thay đổi và cách sử dụng

- [UART TX](../rtl/peripherals/soc_uart_tx.v): `FIFO_DEPTH=4` mặc định;
  `STATUS.bit0` là còn chỗ nhận byte, `bit1` là còn byte/frame chưa phát hết.
  `FIFO_DEPTH=0` giữ hành vi không FIFO. Không cần đổi code `uart_putc`.
- [I²C](../rtl/peripherals/soc_i2c_master.v): `TIMEOUT_CYCLES` mặc định 10 ms
  ở 50 MHz (sàn 1024 clock); 0 tắt watchdog. `CMD.bit5=RECOVER`,
  `bit6=CLEAR_ERRORS`; `STATUS.bit3=timeout`, `bit4=recovery_error` sticky.
  RECOVER có thể hủy lệnh đang bận, tối đa 9 xung rồi STOP; không tự retry.
- [Header firmware](../firmware/include/soc_map.h) có tên và chú thích cho
  các bit mới. Driver I²C kiểm tra lỗi, thử phục hồi một lần và bỏ mẫu đo lỗi.
- Địa chỉ, byte-enable, reset và các giới hạn được ghi trong
  [đặc tả phiên bản 2.1](dac_ta_core_bus_ngoai_vi.md).

## Kiểm chứng

- ModelSim `scripts/run_tests.ps1 -Scope All -Stress`: **PASS 59/59**,
  gồm 26 testbench và 33 lượt cấu hình/seed bổ sung.
- Test I²C mới bao gồm SCL/SDA kẹt, ghi DATA/CMD pending phải fault,
  không ghi muộn, nhả SDA sau vài xung, giới hạn 9 xung, recovery khi đang busy,
  clock stretching hợp lệ, khoảng chờ giữa byte, byte-enable và reset.
- Test SoC dùng chương trình RV32I xác nhận timeout gây store access fault
  cause 7 tại PC=12 và không thực hiện store trẻ hơn tới GPIO.
- Test UART kiểm tra waveform theo hàng đợi byte được bus nhận, wrap con trỏ
  ở độ sâu không phải lũy thừa 2, push/pop đồng thời, đầy, no-op/error và reset.
- Quartus full compile: **0 errors, 14 warnings**, fitter thành công;
  6.074 LE, 2.888 registers, 338.944 memory bits, 3 multiplier 9-bit.
  Timing 50 MHz: worst setup **+1,750 ns**, hold **+0,119 ns**;
  setup/hold fully constrained. Cảnh báo còn lại cùng nhóm QNN ROM/pin/license
  của baseline; không còn cảnh báo truncation mới ở UART.
- Firmware C qua `gcc -std=c11 -ffreestanding -Wall -Wextra -Werror
  -fsyntax-only firmware/main.c`. Chưa cross-build RISC-V: WSL bị chặn quyền
  truy cập, lần yêu cầu chạy ngoài sandbox bị hủy. Ảnh ROM demo giữ nguyên.
- Chưa thử board, chưa chạy lại Icarus/GUI NativeLink. Mô phỏng hai FF xác nhận
  độ trễ logic, không chứng minh metastability hay timing điện của bus.

Log: `tmp/adopt_reference_regression.log`, `tmp/adopt_reference_quartus.log`;
báo cáo fitter/STA mới nằm tại `quartus/output_files/`.
