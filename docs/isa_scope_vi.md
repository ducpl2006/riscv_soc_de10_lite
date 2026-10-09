# Phạm vi ISA và chính sách ngoại lệ

**CORE BASELINE FROZEN — 2026-09-27.** 15 file RTL core có SHA256 trong
`core_frozen_manifest.json`. Bộ RV32UI upstream + exception/corner cục bộ đạt
195/195 lượt; xem [báo cáo ISA](isa_verification_vi.md). Không phải chứng nhận
RISC-V architectural compliance đầy đủ và không mở rộng phạm vi ISA bên dưới.

## RV32I v2.1 được hỗ trợ

| Nhóm | Lệnh |
|---|---|
| Upper immediate | `LUI`, `AUIPC` |
| Jump | `JAL`, `JALR` |
| Branch | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Load | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Store | `SB`, `SH`, `SW` |
| OP-IMM | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| OP | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Ordering/system | `FENCE`, `ECALL`, `EBREAK` |

`FENCE` retire như một NOP phần cứng. Điều này hợp lệ với microarchitecture hiện
tại vì core in-order, không có cache và chỉ cho một data transaction outstanding.

## Không thuộc baseline

- `FENCE.I` (`Zifencei`).
- Sáu lệnh CSR (`Zicsr`) và counter.
- Multiply/divide (`M`), atomic (`A`), compressed (`C`).
- Privileged return, interrupt controller, CSR trap vector.

Các encoding này gây illegal-instruction thay vì bị coi như NOP.

## Alignment

| Truy cập | Yêu cầu |
|---|---|
| Instruction | địa chỉ chia hết cho 4 |
| Byte load/store | không hạn chế |
| Halfword load/store | `addr[0]=0` |
| Word load/store | `addr[1:0]=00` |

Misaligned load/store không được emulation bằng hai bus access.

## Cause output

| Cause | Ý nghĩa |
|---:|---|
| 0 | instruction address misaligned |
| 1 | instruction access fault |
| 2 | illegal instruction |
| 3 | breakpoint (`EBREAK`) |
| 4 | load address misaligned |
| 5 | load access fault |
| 6 | store address misaligned |
| 7 | store access fault |
| 11 | environment call |

Core chưa có CSR `mtvec/mepc/mcause`, vì vậy khi cause tới WB, `trap_valid_o`
được giữ và `halted_o=1` cho tới reset. `trap_pc_o` là PC lệnh gây fault;
`trap_instr_o` là instruction tương ứng nếu đã fetch được.
