# RV32I ISA verification — 2026-09-27

**195/195 PASS**, gồm 40 chương trình upstream RV32UI và 25 chương trình local,
mỗi chương trình chạy seed 0, 17, 20260927. Upstream có 926 nhãn `test_N`;
`simple` là smoke test không có nhãn này. Đây là số case tĩnh, không phải số
instruction retire hoặc số assertion; không dùng các đơn vị đó để cộng lẫn nhau.

Nguồn: [riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests),
commit `bcffa2b3188b040c611f90dc0b6e422f54775a09`, giữ nguyên test body và scalar macros.
Compiler WSL: `riscv64-unknown-elf-gcc` 14.2.0; `-march=rv32i -mabi=ilp32`, no relax.
Icarus chạy core thật qua giao tiếp memory ngoài và quan sát trace, không force
thanh ghi hoặc trạng thái pipeline bên trong.

## Adapter và giới hạn

Environment privileged/tohost của upstream không tương thích trực tiếp với core
trap-and-halt không CSR/MRET. `tb/core/isa/env/riscv_test.h` chỉ thay bootstrap và
PASS/FAIL: a0=1, EBREAK tại label PASS; FAIL có a0=0 và PC khác. gp giữ TESTNUM.
Harness kiểm cause, PC, a0, timeout, request ổn định, không ghi x0 qua trace,
không có side effect trẻ hơn vào sentinel và không giao dịch sau halt.

Hai chương trình upstream không chạy nguyên bản:

- `fence_i`: thuộc Zifencei, không được hỗ trợ; test local yêu cầu illegal instruction.
- `ma_data`: giả định load/store misaligned vẫn thực thi. EEI dự án chọn trap;
  các test local kiểm cause 4/6 và precise trap tại địa chỉ lệnh gây lỗi.

Đây là verification có dùng test upstream, **không phải chứng nhận architectural
compliance của RISC-V International**, không phải formal proof hay chạy toàn bộ
riscv-arch-test/privileged suite. Chưa differential trace với Spike/Sail.

## Instruction và corner coverage

| Nhóm | Lệnh / kiểm tra |
|---|---|
| Arithmetic | ADD, SUB, ADDI; signed endpoints, wraparound |
| Logic | AND, OR, XOR, ANDI, ORI, XORI |
| Shift | SLL, SRL, SRA, SLLI, SRLI, SRAI; amount 0/31 và mask low 5 bits |
| Compare | SLT, SLTU, SLTI, SLTIU; âm/dương, signed/unsigned |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU; taken/not-taken, forward/backward |
| Jump | JAL/JALR link PC+4, rs1=rd, JALR clear bit0, misaligned target |
| Upper | LUI, AUIPC; giá trị PC-relative |
| Load | LB/LBU/LH/LHU/LW; sign/zero extension, các byte/halfword lane |
| Store | SB/SH/SW, store-load và load-store dependency |
| System | FENCE, ECALL, EBREAK, illegal, cause 0/1/2/3/4/5/6/7/11 |
| Hazard | Dependency liền kề/cách 1/cách 2 instruction, x0, source=destination |

Upstream kiểm 0x80000000, 0x7FFFFFFF, 0xFFFFFFFF và toán hạng âm. Seed 0 không
chèn data wait; seed khác trì hoãn instruction grant và data completion theo LFSR.
195 lượt không thay thế test fetch hai outstanding, hazard/LSU/precise ordering
vốn đã có trong regression 78 lượt; cả hai bộ đều bắt buộc PASS.

## Danh sách đầy đủ

Mỗi hàng dưới đây tương ứng chính xác ba lượt trong `sim/isa/results.json`.

| Chương trình | Nguồn | Case có nhãn / ca local | Seed 0 | Seed 17 | Seed 20260927 |
|---|---|---:|---|---|---|
| `add` | upstream | 37 | PASS | PASS | PASS |
| `addi` | upstream | 24 | PASS | PASS | PASS |
| `and` | upstream | 26 | PASS | PASS | PASS |
| `andi` | upstream | 13 | PASS | PASS | PASS |
| `auipc` | upstream | 2 | PASS | PASS | PASS |
| `beq` | upstream | 20 | PASS | PASS | PASS |
| `bge` | upstream | 23 | PASS | PASS | PASS |
| `bgeu` | upstream | 23 | PASS | PASS | PASS |
| `blt` | upstream | 20 | PASS | PASS | PASS |
| `bltu` | upstream | 20 | PASS | PASS | PASS |
| `bne` | upstream | 20 | PASS | PASS | PASS |
| `jal` | upstream | 2 | PASS | PASS | PASS |
| `jalr` | upstream | 6 | PASS | PASS | PASS |
| `lb` | upstream | 18 | PASS | PASS | PASS |
| `lbu` | upstream | 18 | PASS | PASS | PASS |
| `ld_st` | upstream | 48 | PASS | PASS | PASS |
| `lh` | upstream | 18 | PASS | PASS | PASS |
| `lhu` | upstream | 18 | PASS | PASS | PASS |
| `lui` | upstream | 5 | PASS | PASS | PASS |
| `lw` | upstream | 18 | PASS | PASS | PASS |
| `or` | upstream | 26 | PASS | PASS | PASS |
| `ori` | upstream | 13 | PASS | PASS | PASS |
| `sb` | upstream | 22 | PASS | PASS | PASS |
| `sh` | upstream | 22 | PASS | PASS | PASS |
| `simple` | upstream | 0 | PASS | PASS | PASS |
| `sll` | upstream | 41 | PASS | PASS | PASS |
| `slli` | upstream | 24 | PASS | PASS | PASS |
| `slt` | upstream | 37 | PASS | PASS | PASS |
| `slti` | upstream | 24 | PASS | PASS | PASS |
| `sltiu` | upstream | 24 | PASS | PASS | PASS |
| `sltu` | upstream | 37 | PASS | PASS | PASS |
| `sra` | upstream | 42 | PASS | PASS | PASS |
| `srai` | upstream | 24 | PASS | PASS | PASS |
| `srl` | upstream | 42 | PASS | PASS | PASS |
| `srli` | upstream | 24 | PASS | PASS | PASS |
| `st_ld` | upstream | 48 | PASS | PASS | PASS |
| `sub` | upstream | 36 | PASS | PASS | PASS |
| `sw` | upstream | 22 | PASS | PASS | PASS |
| `xor` | upstream | 26 | PASS | PASS | PASS |
| `xori` | upstream | 13 | PASS | PASS | PASS |
| `ecall` | local | 1 | PASS | PASS | PASS |
| `ebreak` | local | 1 | PASS | PASS | PASS |
| `illegal_zero` | local | 1 | PASS | PASS | PASS |
| `illegal_m` | local | 1 | PASS | PASS | PASS |
| `illegal_c` | local | 1 | PASS | PASS | PASS |
| `illegal_csr` | local | 1 | PASS | PASS | PASS |
| `illegal_mret` | local | 1 | PASS | PASS | PASS |
| `illegal_fence_i` | local | 1 | PASS | PASS | PASS |
| `jal_misaligned` | local | 1 | PASS | PASS | PASS |
| `jalr_misaligned` | local | 1 | PASS | PASS | PASS |
| `branch_misaligned` | local | 1 | PASS | PASS | PASS |
| `lh_misaligned` | local | 1 | PASS | PASS | PASS |
| `lhu_misaligned` | local | 1 | PASS | PASS | PASS |
| `lw_misaligned_1` | local | 1 | PASS | PASS | PASS |
| `lw_misaligned_2` | local | 1 | PASS | PASS | PASS |
| `lw_misaligned_3` | local | 1 | PASS | PASS | PASS |
| `sh_misaligned` | local | 1 | PASS | PASS | PASS |
| `sw_misaligned_1` | local | 1 | PASS | PASS | PASS |
| `sw_misaligned_2` | local | 1 | PASS | PASS | PASS |
| `sw_misaligned_3` | local | 1 | PASS | PASS | PASS |
| `load_access` | local | 1 | PASS | PASS | PASS |
| `store_access` | local | 1 | PASS | PASS | PASS |
| `load_x0_access` | local | 1 | PASS | PASS | PASS |
| `instruction_access` | local | 1 | PASS | PASS | PASS |
| `jalr_bit0_fence` | local | 1 | PASS | PASS | PASS |

## Tái lập

```bash
python3 scripts/check_core_freeze.py
python3 scripts/run_isa.py
```

Khôi phục upstream đúng commit theo `third_party/README.md` nếu chưa có checkout.
Script kiểm revision và tracked ISA source chưa sửa; không tự tải hoặc cài tool.
ELF, BIN, byte HEX, build/simulation logs và SHA256 từng image nằm trong `sim/isa/`.
Các assembly exception local được sinh từ `local_tests()` trong script.
