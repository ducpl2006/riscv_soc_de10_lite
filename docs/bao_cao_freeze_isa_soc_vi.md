# Báo cáo Freeze RV32I + ISA + Timing + Firmware INA228

Ngày 2026-09-27. **CORE BASELINE FROZEN**. Không đổi bất kỳ RTL core, bus,
ngoại vi hoặc QNN nào trong phase này. Không thêm ISA extension, CSR, interrupt,
cache, DMA hoặc bus mới. Theo đính chính của người dùng, driver đích là **INA228**.

## Kết quả chính

| Hạng mục | Kết quả | Bằng chứng |
|---|---|---|
| Regression trước thay đổi | 69/69 PASS | `tmp/freeze_baseline_regression.log` |
| Regression trước chốt core | 69/69 PASS | `tmp/freeze_pre_firmware_regression.log` |
| ISA upstream + local | 195/195 PASS | `sim/isa/results.json` |
| ModelSim toàn bộ cuối phase | 78/78 PASS, 32 TB + 46 stress | `tmp/freeze_final_regression.log` |
| Icarus toàn bộ mặc định | 32/32 PASS | `sim/iverilog/work/*.log` |
| Firmware Icarus end-to-end | 9/9 PASS | `sim/firmware/results.json` |
| Host C | 2 nhóm PASS | `sim/firmware/host.log` |
| Quartus compile | 0 errors, 14 warnings | `tmp/freeze_quartus.log` |
| Core integrity | 15/15 file giữ nguyên SHA256 | `docs/core_frozen_manifest.json` |

Các số ở các hàng là bộ kiểm thử riêng, có giao nhau; không cộng chúng thành
một con số “test độc lập”. Không loại hoặc giảm 69 lượt regression baseline.

## A. ISA và chốt core

40 chương trình RV32UI upstream nguyên bản, 926 nhãn test; thêm 25 chương trình
local cho trap, alignment, access fault, JALR bit0 và FENCE. Mỗi chương trình chạy
ba lịch chờ bộ nhớ. [Danh sách và coverage đầy đủ](isa_verification_vi.md).

Adapter thay environment privileged bằng trap-and-halt, không thay test body
hoặc core. `fence_i` và `ma_data` không chạy nguyên bản do khác scope/EEI;
encoding unsupported và misaligned trap được kiểm riêng. Không tự nhận đây là
chứng nhận RISC-V compliance đầy đủ. Không tìm thấy bug core cần sửa.

Baseline source được lưu trước khi làm trong `tmp/freeze_phase_before.zip` và
`tmp/freeze_phase_before.json`. Sau ISA, regression và Quartus PASS, chốt hash ở
`docs/core_frozen_manifest.json`; `scripts/check_core_freeze.py` phát hiện cả
file mới, file mất hoặc hash thay đổi. `AGENTS.md` ghi lại chính sách freeze.

## B. Timing trước / sau

| Chỉ tiêu | Baseline P0/P1 | Compile lại cuối core phase |
|---|---:|---:|
| Fmax slow 85°C | 54.86 MHz | 54.86 MHz |
| Worst setup | +1.772 ns | +1.772 ns |
| Worst hold | +0.097 ns | +0.097 ns |
| Worst recovery | +17.049 ns | +17.049 ns |
| Worst removal | +1.069 ns | +1.069 ns |
| Logic elements | 6353 | 6353 |
| Registers | 3184 | 3184 |
| Memory bits | 338944 | 338944 |
| DSP 9-bit | 3 | 3 |

Trước và sau đều có đường từ `u_core|memwb_exc_valid_q` tới instruction ROM
`ram_block1a6~porta_re_reg`. 12 logic levels; data delay 17.964 ns, routing
11.430 ns; fanout cao nhất trên các net data được liệt kê là 78.
Đường qua WB write-valid → forwarding/EX operand → ALU compare → EX fault →
IF FIFO/credit → ROM enable. [Sơ đồ, fanout/delay và option A/B/C](timing_review_freeze_vi.md).

Chọn option A giữ nguyên: yêu cầu 50 MHz đã đạt, không có bug tái hiện và không
có bằng chứng lợi ích đủ lớn để đổi core. Không thực hiện optimization để rồi
giữ một mức tăng dưới 2 MHz. **60 MHz+ chưa đạt**. Setup/hold/recovery/removal
đều PASS trên ba corner. 14 cảnh báo Quartus thuộc baseline (port/bit ROM không
dùng, KEY không dùng, tùy chọn/assignment I/O và license); không có cảnh báo mới
do phase này. Xem log compiler để biết đầy đủ từng cảnh báo.

Các số Quartus dùng ảnh ROM/model baseline. Firmware C mới được build ra thư mục
riêng và chạy trong simulation; chưa đổi `firmware/build/boot.*`, QSF hoặc SDC.
Vì vậy không gán kết quả fit trên cho một ảnh board INA228 mới đã được triển khai.

## C. Firmware và đường dữ liệu

Luồng fake sensor và luồng INA228 pin-level đều chạy mã C biên dịch RV32I trên
SoC thật trong simulator: ROM → CPU → RAM/vòng đệm 20 mẫu → MMIO/QNN → UART.
25 mẫu tạo 6 cửa sổ, kiểm 480 feature theo thứ tự và 6 kết quả với Python golden,
giải mã 63 byte tại chân UART. Không dùng MMIO backdoor để thay hành vi CPU.

Driver INA228 có ID check, init/config/calibration/readback, đọc VBUS/CURRENT/
VSHUNT/DIETEMP, chờ conversion hữu hạn, kiểm lỗi và recovery I²C một lần.
Không thay I²C RTL. UART dùng bit mask; QNN chờ idle trước ghi, xóa done cũ rồi
start/poll; timer polling, không IRQ. Host C kiểm saturation/truncation, vòng đệm,
mất mẫu, thiếu nhiệt độ, signed 20-bit và calibration/error paths.

| Kịch bản firmware RTL | Kết quả |
|---|---|
| Fake sensor → 20 mẫu → QNN → UART | PASS |
| INA228 pin-level → 20 mẫu → QNN → UART | PASS |
| NACK địa chỉ / mất sensor | PASS |
| SCL kẹt thấp | PASS |
| Sai manufacturer/device identity | PASS |
| Conversion không hoàn tất | PASS |
| MATHOF | PASS |
| NACK pointer giữa acquisition | PASS |
| Sensor mất calibration | PASS |

Mỗi ca lỗi phải thoát hữu hạn, báo UART và không ghi feature/start QNN. Hai nhóm
host test kiểm nhiều assertion; không gọi đây là chỉ hai assertion.

| Firmware build | Kích thước | Trạng thái |
|---|---:|---|
| fake | 2216 byte | Build RV32I PASS; đã simulation |
| ina228 | 8160 byte | Build RV32I PASS; đã simulation |
| board | 8144 byte | Build RV32I PASS; chưa cài ROM board |

Build manifest và source SHA256 nằm ở `tb/soc/firmware_assets/build_manifest.json`.
[Cấu hình, contract và quy trình board](firmware_ina228_vi.md).

## D. Danh sách regression đầy đủ

Icarus default là 32 hàng có PASS ở cột thứ ba; các hàng stress khác được kiểm
bằng ModelSim. Bộ firmware Icarus 9 kịch bản riêng đã liệt kê ở phần C.

| Test/run | ModelSim | Icarus default |
|---|---|---|
| `tb_rv32_alu` | PASS | PASS |
| `tb_rv32_branch_unit` | PASS | PASS |
| `tb_rv32_core` | PASS | PASS |
| `tb_rv32_core_bus_wait` | PASS | PASS |
| `tb_rv32_core_fetch` | PASS | PASS |
| `tb_rv32_core_ordering` | PASS | PASS |
| `tb_rv32_core_traps` | PASS | PASS |
| `tb_rv32_decoder` | PASS | PASS |
| `tb_rv32_firmware_e2e` | PASS | PASS |
| `tb_rv32_gpio` | PASS | PASS |
| `tb_rv32_hazard_unit` | PASS | PASS |
| `tb_rv32_i2c_master` | PASS | PASS |
| `tb_rv32_i2c_recovery` | PASS | PASS |
| `tb_rv32_i2c_transactions` | PASS | PASS |
| `tb_rv32_if_stage` | PASS | PASS |
| `tb_rv32_imm_gen` | PASS | PASS |
| `tb_rv32_lsu` | PASS | PASS |
| `tb_rv32_qnn_model` | PASS | PASS |
| `tb_rv32_qnn_soc_accelerator` | PASS | PASS |
| `tb_rv32_regfile` | PASS | PASS |
| `tb_rv32_reset_controller` | PASS | PASS |
| `tb_rv32_soc` | PASS | PASS |
| `tb_rv32_soc_bus` | PASS | PASS |
| `tb_rv32_soc_mmio` | PASS | PASS |
| `tb_rv32_soc_ram` | PASS | PASS |
| `tb_rv32_soc_rom` | PASS | PASS |
| `tb_rv32_soc_uart_rx` | PASS | PASS |
| `tb_rv32_timer` | PASS | PASS |
| `tb_rv32_uart_fifo` | PASS | PASS |
| `tb_rv32_uart_rx` | PASS | PASS |
| `tb_rv32_uart_rx_fifo` | PASS | PASS |
| `tb_rv32_uart_tx` | PASS | PASS |
| `tb_rv32_firmware_ina228_fault_0` | PASS | — |
| `tb_rv32_firmware_ina228_fault_1` | PASS | — |
| `tb_rv32_firmware_ina228_fault_2` | PASS | — |
| `tb_rv32_firmware_ina228_fault_3` | PASS | — |
| `tb_rv32_firmware_ina228_fault_4` | PASS | — |
| `tb_rv32_firmware_ina228_fault_5` | PASS | — |
| `tb_rv32_firmware_ina228_fault_6` | PASS | — |
| `tb_rv32_firmware_ina228_fault_7` | PASS | — |
| `tb_rv32_uart_rx_div_8_depth_1` | PASS | — |
| `tb_rv32_uart_rx_div_9_depth_3` | PASS | — |
| `tb_rv32_uart_rx_div_100_depth_1` | PASS | — |
| `tb_rv32_uart_rx_fifo_depth_1` | PASS | — |
| `tb_rv32_gpio_width_10` | PASS | — |
| `tb_rv32_core_seed_1` | PASS | — |
| `tb_rv32_core_seed_2` | PASS | — |
| `tb_rv32_core_seed_3` | PASS | — |
| `tb_rv32_core_seed_4` | PASS | — |
| `tb_rv32_core_seed_5` | PASS | — |
| `tb_rv32_core_seed_6` | PASS | — |
| `tb_rv32_core_seed_7` | PASS | — |
| `tb_rv32_core_seed_8` | PASS | — |
| `tb_rv32_core_seed_9` | PASS | — |
| `tb_rv32_core_seed_10` | PASS | — |
| `tb_rv32_core_seed_11` | PASS | — |
| `tb_rv32_core_seed_12` | PASS | — |
| `tb_rv32_core_seed_13` | PASS | — |
| `tb_rv32_core_seed_14` | PASS | — |
| `tb_rv32_core_seed_15` | PASS | — |
| `tb_rv32_core_seed_16` | PASS | — |
| `tb_rv32_uart_tx_div_1` | PASS | — |
| `tb_rv32_uart_tx_div_2` | PASS | — |
| `tb_rv32_uart_tx_div_3` | PASS | — |
| `tb_rv32_uart_tx_div_7` | PASS | — |
| `tb_rv32_uart_fifo_div_1_depth_1` | PASS | — |
| `tb_rv32_uart_fifo_div_1_depth_3` | PASS | — |
| `tb_rv32_uart_fifo_div_7_depth_3` | PASS | — |
| `tb_rv32_i2c_div_2_sync_0` | PASS | — |
| `tb_rv32_i2c_recovery_div_2_sync_0` | PASS | — |
| `tb_rv32_i2c_div_2_sync_1` | PASS | — |
| `tb_rv32_i2c_recovery_div_2_sync_1` | PASS | — |
| `tb_rv32_i2c_div_3_sync_0` | PASS | — |
| `tb_rv32_i2c_recovery_div_3_sync_0` | PASS | — |
| `tb_rv32_i2c_div_3_sync_1` | PASS | — |
| `tb_rv32_i2c_recovery_div_3_sync_1` | PASS | — |
| `tb_rv32_i2c_div_5_sync_0` | PASS | — |
| `tb_rv32_i2c_recovery_div_5_sync_0` | PASS | — |

## E. File thay đổi

| File | Trạng thái |
|---|---|
| `AGENTS.md` | new |
| `README.md` | modified |
| `docs/bao_cao_freeze_isa_soc_vi.md` | new |
| `docs/core_frozen_manifest.json` | new |
| `docs/firmware_ina228_vi.md` | new |
| `docs/isa_scope_vi.md` | modified |
| `docs/isa_verification_vi.md` | new |
| `docs/module_va_testbench_vi.md` | modified |
| `docs/soc_qnn_de10_lite_vi.md` | modified |
| `docs/timing_review_freeze_vi.md` | new |
| `firmware/ina228.c` | new |
| `firmware/include/board_config.h` | new |
| `firmware/include/ina228.h` | new |
| `firmware/include/sample_pipeline.h` | new |
| `firmware/include/soc_platform.h` | new |
| `firmware/main.c` | modified |
| `firmware/runtime.c` | new |
| `firmware/sample_pipeline.c` | new |
| `firmware/soc_platform.c` | new |
| `scripts/build_firmware.ps1` | modified |
| `scripts/build_firmware.py` | modified |
| `scripts/check_core_freeze.py` | new |
| `scripts/generate_firmware_vectors.py` | new |
| `scripts/report_freeze_phase.py` | new |
| `scripts/run_firmware_tests.py` | new |
| `scripts/run_isa.py` | new |
| `scripts/run_tests.ps1` | modified |
| `tb/core/isa/env/link.ld` | new |
| `tb/core/isa/env/riscv_test.h` | new |
| `tb/core/isa/isa_core_harness.sv` | new |
| `tb/firmware/test_pipeline_ina228.c` | new |
| `tb/soc/firmware_assets/build_manifest.json` | new |
| `tb/soc/firmware_assets/bus_raw.hex` | new |
| `tb/soc/firmware_assets/current_raw.hex` | new |
| `tb/soc/firmware_assets/fake.hex` | new |
| `tb/soc/firmware_assets/fake_features.hex` | new |
| `tb/soc/firmware_assets/fake_reference.json` | new |
| `tb/soc/firmware_assets/fake_results.hex` | new |
| `tb/soc/firmware_assets/fake_uart.hex` | new |
| `tb/soc/firmware_assets/fake_uart_length.hex` | new |
| `tb/soc/firmware_assets/ina228.hex` | new |
| `tb/soc/firmware_assets/ina228_features.hex` | new |
| `tb/soc/firmware_assets/ina228_reference.json` | new |
| `tb/soc/firmware_assets/ina228_results.hex` | new |
| `tb/soc/firmware_assets/ina228_uart.hex` | new |
| `tb/soc/firmware_assets/ina228_uart_length.hex` | new |
| `tb/soc/firmware_assets/shunt_raw.hex` | new |
| `tb/soc/tb_rv32_firmware_e2e.sv` | new |
| `third_party/README.md` | new |

Ngoài bảng source của dự án, thêm checkout upstream `third_party/riscv-tests/`
nguyên bản và giữ LICENSE. Inventory lịch sử từng file/vendor SHA256 được giữ
cục bộ tại `docs/freeze_phase_files.json`, không đi kèm checkout GitHub;
`.git` và build database không thuộc inventory. Manifest kiểm tra core hiện tại
vẫn được cung cấp tại `docs/core_frozen_manifest.json`.
Các ELF/BIN/MIF/log simulation/timing sinh ra là bằng chứng tái lập, nằm ở
`firmware/build/verify_*`, `sim/isa`, `sim/firmware`, `sim/modelsim/work`,
`sim/iverilog/work`, `tmp/freeze_*` và `quartus/output_files`.

### Core không thay đổi

- `rtl/core/common/rv32_lsu.v`
- `rtl/core/control/rv32_hazard_unit.v`
- `rtl/core/control/rv32_pipeline_control.v`
- `rtl/core/ex/rv32_alu.v`
- `rtl/core/ex/rv32_branch_unit.v`
- `rtl/core/ex/rv32_ex_stage.v`
- `rtl/core/id/rv32_decoder.v`
- `rtl/core/id/rv32_id_stage.v`
- `rtl/core/id/rv32_imm_gen.v`
- `rtl/core/id/rv32_regfile.v`
- `rtl/core/if/rv32_if_stage.v`
- `rtl/core/mem/rv32_mem_stage.v`
- `rtl/core/rv32_core.v`
- `rtl/core/rv32_defs.vh`
- `rtl/core/wb/rv32_wb_stage.v`

Tổng 34 file RTL source được ghi trong baseline đều giữ nguyên byte.

## F. Giới hạn và việc cần trước board

- Không RV32M/C/A, CSR, interrupt, MRET, Zifencei, cache/MMU/DMA. Trap-and-halt
  là contract hiện tại. Chưa formal proof hoặc full privileged compliance.
- UART RX vẫn middle-bit sampling, không 16x majority voting.
- Fmax chưa đạt 60 MHz; hold dương 0.097 ns nhưng margin nhỏ. Không đổi constraint
  để che path hoặc loại bỏ wrong-path/outstanding-fetch protection.
- Chưa có thông số shunt, địa chỉ INA228 và CURRENT_LSB xác nhận cho board;
  mặc định board để chưa cấu hình. Giá trị 0x40/10 mΩ/10 µA chỉ là fixture simulation.
- INA228 die temperature chưa được xác nhận thay thế nhiệt độ pin của model;
  board không giả định 25°C. Model yêu cầu T thật/phù hợp, nếu thiếu thì không
  chạy inference. Hai test end-to-end dùng nguồn nhiệt độ pin giả được ghi rõ.
- Chưa thử board: `quartus_pgm -l` trả `No JTAG hardware available`. GUI NativeLink
  chưa chạy. Không nạp FPGA hoặc thay ảnh boot mặc định.
- Chưa chứng minh độ chính xác SOC trên pin/sensor thật; simulation xác minh
  số học, firmware và giao thức với model hiện có.

## Tái lập

```powershell
.\.tools\python311\python.exe scripts/check_core_freeze.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_isa.py
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_firmware_tests.py
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_tests.py --scope all
```

Từ `quartus/`: `quartus_sh --flow compile riscv_soc`, sau đó
`quartus_sta -t ../scripts/report_bus_timing.tcl ../tmp/freeze_timing`.
Script `report_freeze_phase.py` tổng hợp báo cáo này từ evidence đã lưu;
không tự chạy test hay tự biến kết quả FAIL thành PASS.
