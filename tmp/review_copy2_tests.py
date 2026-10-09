"""Đối chiếu bản RAR; mọi tệp chẩn đoán và log chỉ nằm trong tmp."""
from pathlib import Path
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
from soc_rtl_sources import soc_rtl_sources

review = root / 'tmp/review_copy2_20260930'
archived = review / 'riscv_soc_de10_lite - Copy'
evidence = review / 'evidence'
evidence.mkdir(exist_ok=True)
results = []

def run(label, project, extra=False, top_override=None, simulate=False):
    sources = soc_rtl_sources(project)
    if extra:
        sources.append(archived / 'rtl/core/rv32_pipeline_regs.v')
    if top_override:
        sources = [top_override if p == archived / 'rtl/core/rv32_core.v' else p for p in sources]
    command = ['iverilog', '-g2012', '-I', str(project / 'rtl/core'),
               '-I', str(project / 'rtl/bus'), '-I', str(project / 'rtl/accelerator'),
               '-s', 'tb_rv32_core_traps', '-o', str(evidence / (label + '.vvp')),
               *map(str, sources), str(project / 'tb/core/tb_rv32_core_traps.v')]
    result = subprocess.run(command, cwd=evidence, text=True, capture_output=True, timeout=120)
    (evidence / (label + '_compile.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
    item = {'label': label, 'compile_exit': result.returncode, 'compile_command': command}
    print(label, 'compile_exit=', result.returncode, flush=True)
    print(result.stdout + result.stderr, flush=True)
    if simulate and result.returncode == 0:
        sim = subprocess.run(['vvp', str(evidence / (label + '.vvp'))], cwd=evidence,
                             text=True, capture_output=True, timeout=120)
        output = sim.stdout + sim.stderr
        (evidence / (label + '_run.log')).write_text(output, encoding='utf-8')
        item.update(run_exit=sim.returncode, output=output)
        print(output, flush=True)
    results.append(item)

run('rar_nguyen_trang', archived)
run('rar_them_nguon_regs', archived, extra=True)

# Chỉ sửa tên cổng trong một bản sao phục vụ chẩn đoán, giữ nguyên biểu thức kết nối.
original = (archived / 'rtl/core/rv32_core.v').read_text(encoding='utf-8')
adapted = original
mapping = {
    'u_if_stage': {'ifid_consumed_i': 'consumed_id_i'},
    'u_id_stage': {'rd_addr_wb_i': 'memwb_rd_addr_i', 'wb_data_wb_i': 'memwb_wb_data_i'},
    'u_ex_stage': {'wb_sel_mem_i': 'exmem_wb_sel_i', 'pc4_mem_i': 'exmem_pc4_i',
                   'alu_result_mem_i': 'exmem_alu_result_i', 'wb_data_wb_i': 'memwb_wb_data_i'},
}
for instance, ports in mapping.items():
    match = re.search(r'\b' + instance + r'\s*\(.*?\n    \);', adapted, re.S)
    assert match, instance
    block = match.group()
    for old, new in ports.items():
        block, count = re.subn(r'\.' + old + r'\b', '.' + new, block)
        assert count == 1, (instance, old, count)
    adapted = adapted[:match.start()] + block + adapted[match.end():]
top_copy = evidence / 'rv32_core_chi_sua_ten_cong.v'
top_copy.write_text(adapted, encoding='utf-8')
run('rar_chan_doan_ten_cong', archived, extra=True, top_override=top_copy, simulate=True)
run('ban_hien_tai', root, simulate=True)
(evidence / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
