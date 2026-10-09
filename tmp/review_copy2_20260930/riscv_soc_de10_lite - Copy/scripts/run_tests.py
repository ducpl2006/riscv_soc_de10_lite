#!/usr/bin/env python3
"""Chạy toàn bộ testbench trên Ubuntu bằng Icarus Verilog, dùng RTL behavioral."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
from soc_rtl_sources import soc_rtl_sources


ROOT = Path(__file__).resolve().parents[1]
# Giữ cùng độ sâu với sim/modelsim/work vì testbench dùng đường dẫn ../../../.
WORK = ROOT / 'sim/iverilog/work'


def run_logged(command, log):
    try:
        result = subprocess.run(command, cwd=WORK, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        log.write_text('FAIL: timeout after 120 seconds\n', encoding='utf-8')
        raise RuntimeError(f'Timeout; xem {log}') from None
    log.write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'Exit {result.returncode}; xem {log}\n{result.stdout}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scope', choices=('base', 'all'), default='all',
                        help='base: core/bus/memory/peripherals, không chạy test QNN/model')
    args = parser.parse_args()
    for tool in ('iverilog', 'vvp'):
        if not shutil.which(tool):
            raise RuntimeError('Thiếu Icarus Verilog. Chạy: sudo apt-get install iverilog')
    rtl = soc_rtl_sources(ROOT)
    benches = sorted(p for p in (ROOT / 'tb').rglob('tb_rv32_*')
                     if p.suffix in ('.v', '.sv'))
    if args.scope == 'base':
        benches = [p for p in benches if 'accelerator' not in p.relative_to(ROOT / 'tb').parts
                   and p.stem != 'tb_rv32_soc']
    if not rtl or not benches:
        raise RuntimeError('Không tìm thấy RTL hoặc testbench')
    if len({p.stem for p in benches}) != len(benches):
        raise RuntimeError('Tên top testbench bị trùng')
    WORK.mkdir(parents=True, exist_ok=True)
    for bench in benches:
        executable = WORK / (bench.stem + '.vvp')
        run_logged([
            'iverilog', '-g2012', '-I', str(ROOT / 'rtl/core'),
            '-I', str(ROOT / 'rtl/bus'),
            '-I', str(ROOT / 'rtl/accelerator'), '-s', bench.stem,
            '-o', str(executable), *map(str, rtl), str(bench),
        ], WORK / ('compile_' + bench.stem + '.log'))
        log = WORK / (bench.stem + '.log')
        output = run_logged(['vvp', str(executable)], log)
        if re.search(r'\b(?:FAIL|ERROR|FATAL)\b', output, re.I) or not re.search(r'\bPASS\b', output):
            raise RuntimeError(f'{bench.stem}: thiếu PASS hoặc có lỗi; xem {log}\n{output}')
        print(f'{bench.stem}: PASS', flush=True)
    print(f'RESULT: PASS ({len(benches)}/{len(benches)} testbench)')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f'RESULT: FAIL - {error}', file=sys.stderr)
        sys.exit(1)
