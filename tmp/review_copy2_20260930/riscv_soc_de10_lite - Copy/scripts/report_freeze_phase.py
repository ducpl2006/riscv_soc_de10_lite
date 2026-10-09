#!/usr/bin/env python3
"""Assemble the freeze report from saved, successful verification evidence."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]


def read(path):
    data=(ROOT/path).read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    isa=json.loads(read('sim/isa/results.json'))
    firmware=json.loads(read('sim/firmware/results.json'))
    baseline=json.loads(read('tmp/freeze_phase_before.json'))
    frozen=json.loads(read('docs/core_frozen_manifest.json'))
    regression=read('tmp/freeze_final_regression.log')
    assert 'RESULT: PASS (78/78 test runs)' in regression
    names=re.findall(r'^(tb_rv32_\w+)\s+PASS\s+[0-9.]+\s+s\s*$',regression,re.M)
    assert len(names)==78 and len(set(names))==78
    assert len(isa['results'])==195 and all(x['status']=='PASS' for x in isa['results'])
    assert len(firmware['results'])==9 and all(x['status']=='PASS' for x in firmware['results'])
    assert 'Full Compilation was successful. 0 errors, 14 warnings' in read('tmp/freeze_quartus.log')
    assert '54.86 MHz' in read('tmp/freeze_timing/fmax.rpt')
    for path,sha in frozen['files'].items(): assert digest(ROOT/path)==sha,path
    rtl_paths=[p for p in baseline if p.startswith('rtl/')]
    assert all(digest(ROOT/p)==baseline[p] for p in rtl_paths)
    default_benches=sorted(p.stem for p in (ROOT/'tb').rglob('tb_rv32_*') if p.suffix in ['.v','.sv'])
    for name in default_benches:
        log=read('sim/iverilog/work/'+name+'.log')
        assert 'PASS' in log and not re.search(r'\b(FAIL|FATAL|ERROR)\b',log)

    isa_rows=[x for x in isa['results'] if x['seed']==0]
    isa_text='''# RV32I ISA verification — 2026-09-27

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
'''
    for r in isa_rows:
        isa_text+=f"| `{r['name']}` | {r['origin']} | {r['cases']} | PASS | PASS | PASS |\n"
    isa_text+='''
## Tái lập

```bash
python3 scripts/check_core_freeze.py
python3 scripts/run_isa.py
```

Khôi phục upstream đúng commit theo `third_party/README.md` nếu chưa có checkout.
Script kiểm revision và tracked ISA source chưa sửa; không tự tải hoặc cài tool.
ELF, BIN, byte HEX, build/simulation logs và SHA256 từng image nằm trong `sim/isa/`.
Các assembly exception local được sinh từ `local_tests()` trong script.
'''
    (ROOT/'docs/isa_verification_vi.md').write_text(isa_text,encoding='utf-8')

    # Build a reviewable source inventory, excluding tool databases/logs and the
    # pre-existing generated board/model images. New test assets are included.
    paths={ROOT/p for p in baseline if not p.startswith('quartus/output_files/')}
    extensions={'.v','.sv','.vh','.py','.ps1','.tcl','.md','.c','.h','.S','.ld','.qsf','.sdc','.qpf'}
    for base in ['rtl','tb','scripts','docs','firmware']:
        paths.update(p for p in (ROOT/base).rglob('*') if p.is_file() and 'build' not in p.parts
                     and '__pycache__' not in p.parts and p.suffix in extensions)
    paths.update((ROOT/'tb/soc/firmware_assets').glob('*'))
    paths.update([ROOT/'AGENTS.md',ROOT/'README.md',ROOT/'docs/core_frozen_manifest.json',ROOT/'third_party/README.md'])
    report_path=ROOT/'docs/bao_cao_freeze_isa_soc_vi.md'
    paths.add(report_path)
    if not report_path.exists(): report_path.write_text('',encoding='utf-8')
    changes=[]
    for path in sorted(paths):
        relative=path.relative_to(ROOT).as_posix()
        if relative=='docs/freeze_phase_files.json': continue
        if relative not in baseline or digest(path)!=baseline[relative]:
            changes.append(dict(path=relative,status='modified' if relative in baseline else 'new'))
    text='''# Báo cáo Freeze RV32I + ISA + Timing + Firmware INA228

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

'''
    text+='| Firmware build | Kích thước | Trạng thái |\n|---|---:|---|\n'
    for img in firmware['images']:
        text+=f"| {img['name']} | {img['bytes']} byte | Build RV32I PASS; {'đã simulation' if img['name']!='board' else 'chưa cài ROM board'} |\n"
    text+='''
Build manifest và source SHA256 nằm ở `tb/soc/firmware_assets/build_manifest.json`.
[Cấu hình, contract và quy trình board](firmware_ina228_vi.md).

## D. Danh sách regression đầy đủ

Icarus default là 32 hàng có PASS ở cột thứ ba; các hàng stress khác được kiểm
bằng ModelSim. Bộ firmware Icarus 9 kịch bản riêng đã liệt kê ở phần C.

| Test/run | ModelSim | Icarus default |
|---|---|---|
'''
    for name in names: text+=f"| `{name}` | PASS | {'PASS' if name in default_benches else '—'} |\n"
    text+='\n## E. File thay đổi\n\n| File | Trạng thái |\n|---|---|\n'
    for change in changes: text+=f"| `{change['path']}` | {change['status']} |\n"
    text+='''
Ngoài bảng source của dự án, thêm checkout upstream `third_party/riscv-tests/`
nguyên bản và giữ LICENSE. Danh sách từng file/vendor SHA256 nằm trong
`docs/freeze_phase_files.json`; `.git` và build database không thuộc inventory.
Các ELF/BIN/MIF/log simulation/timing sinh ra là bằng chứng tái lập, nằm ở
`firmware/build/verify_*`, `sim/isa`, `sim/firmware`, `sim/modelsim/work`,
`sim/iverilog/work`, `tmp/freeze_*` và `quartus/output_files`.

### Core không thay đổi

'''
    for path in frozen['files']: text+=f'- `{path}`\n'
    text+=f'\nTổng {len(rtl_paths)} file RTL source được ghi trong baseline đều giữ nguyên byte.\n'
    text+='''
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
.\\.tools\\python311\\python.exe scripts/check_core_freeze.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_isa.py
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_firmware_tests.py
wsl -d Ubuntu -- python3 /mnt/c/FPGA/riscv_soc_de10_lite/scripts/run_tests.py --scope all
```

Từ `quartus/`: `quartus_sh --flow compile riscv_soc`, sau đó
`quartus_sta -t ../scripts/report_bus_timing.tcl ../tmp/freeze_timing`.
Script `report_freeze_phase.py` tổng hợp báo cáo này từ evidence đã lưu;
không tự chạy test hay tự biến kết quả FAIL thành PASS.
'''
    report_path.write_text(text,encoding='utf-8')
    for change in changes: change['sha256']=digest(ROOT/change['path'])
    vendor=[]
    for p in sorted((ROOT/'third_party/riscv-tests').rglob('*')):
        if '.git' in p.parts: continue
        if p.is_symlink():
            vendor.append(dict(path=p.relative_to(ROOT).as_posix(),symlink=p.readlink().as_posix()))
        elif p.is_file():
            vendor.append(dict(path=p.relative_to(ROOT).as_posix(),sha256=digest(p)))
    (ROOT/'docs/freeze_phase_files.json').write_text(json.dumps(dict(
        project_changes=changes,vendor_commit=isa['upstream_commit'],vendor=vendor,
        unchanged_core=frozen['files']),indent=2)+'\n',encoding='utf-8')
    print(f'Reports generated: {len(changes)} project files; {len(vendor)} upstream files; 15 core files unchanged')


if __name__=='__main__': main()
