from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
before = root / 'sim/module_equivalence/truoc_tach'
work = root / 'sim/module_equivalence/kiem_tra_am_20260930'
work.mkdir(exist_ok=False)
snapshot = json.loads((before / 'results.json').read_text(encoding='utf-8'))
sources = [before / 'candidate' / name for name in snapshot['sha256_nguon']
           if name.endswith('.v') and name != 'rtl/core/rv32_core.v']
original_wb = before / 'candidate/rtl/core/wb/rv32_wb_stage.v'
source = original_wb.read_text(encoding='utf-8')
old = "retire_pc_o      <= 32'b0;"
assert source.count(old) == 1
mutated = work / 'rv32_wb_stage_mutated.v'
mutated.write_text(source.replace(old, "retire_pc_o      <= 32'd4;"), encoding='utf-8')
sources = [mutated if p == original_wb else p for p in sources]
sources += [before / 'rv32_core_candidate.v', before / 'rv32_core_wrapper.sv']
sources += sorted((before / 'reference/rtl/core').rglob('*.v'))
sources += [before / 'benches/tb/core/tb_rv32_core.v']
command = ['iverilog', '-g2012', '-s', 'tb_rv32_core', '-o', str(work / 'negative.vvp')]
for folder in ('candidate/rtl/core', 'candidate/rtl/bus', 'candidate/rtl/accelerator', 'reference/rtl/core'):
    command += ['-I', str(before / folder)]
command += list(map(str, sources))
build = subprocess.run(command, cwd=work, capture_output=True, text=True)
(work / 'compile.log').write_text(build.stdout + build.stderr, encoding='utf-8')
assert build.returncode == 0
result = subprocess.run(['vvp', str(work / 'negative.vvp')], cwd=work, capture_output=True, text=True)
output = result.stdout + result.stderr
(work / 'simulation.log').write_text(output, encoding='utf-8')
assert result.returncode != 0 and 'Sai khác' in output and '.retire_pc_o' in output, output
(work / 'results.json').write_text(json.dumps({
    'trang_thai': 'PASS',
    'kiem_tra': 'Đổi retire_pc reset từ 0 thành 4 chỉ trên bản sao; bộ đối chiếu phát hiện sai khác dù retire_valid=0.',
    'ma_thoat_du_kien_khac_0': result.returncode,
    'rtl_hien_tai_bi_sua': False,
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('PASS: bộ đối chiếu phát hiện sai payload invalid trong bản sao kiểm tra âm.')
