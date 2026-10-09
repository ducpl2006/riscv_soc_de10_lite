#!/usr/bin/env python3
"""Đối chiếu theo chu kỳ giữa core hiện tại và bản trước khi tách module.

Chạy bằng Python trong môi trường có Icarus Verilog, ví dụ Ubuntu/WSL:
    python3 scripts/check_core_module_equivalence.py --label truoc_tach

Giữ nguyên testbench hiện có. Lớp bọc cấp cùng đầu vào cho hai bản RTL,
so sánh mọi đầu ra sau cả hai cạnh clock, kể cả payload khi valid=0.
Đây là kiểm thử vi sai trên các kịch bản đã chạy, không phải chứng minh hình thức.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from soc_rtl_sources import soc_rtl_sources


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'docs/core_module_baseline_20260929.zip'
BASELINE_SHA256 = '30f7d0a4b68999a298f14f172bdcff8d99b6fc18059ee0695fbdbdbae811d3c9'
BENCHES = (
    'tb/core/tb_rv32_core.v',
    'tb/core/tb_rv32_core_fetch.v',
    'tb/core/tb_rv32_core_ordering.v',
    'tb/core/tb_rv32_core_traps.v',
    'tb/soc/tb_rv32_core_bus_wait.v',
    'tb/core/if/tb_rv32_if_stage.v',
)
# Chỉ thay tên định danh; không sửa chuỗi, chú thích hoặc tên thoát.
LEXEME = re.compile(
    r'(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)'
    r'|(?P<string>"(?:\\[\s\S]|[^"\\])*")'
    r'|(?P<escaped>\\[^\s]+)'
    r'|(?P<name>[$A-Za-z_][$A-Za-z_0-9]*)'
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_text(path, source):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source, encoding='utf-8')


def rename_identifiers(source, mapping):
    return LEXEME.sub(
        lambda match: mapping.get(match.group(), match.group())
        if match.lastgroup == 'name' else match.group(), source)


def without_comments(source):
    return LEXEME.sub(
        lambda match: ' ' if match.lastgroup == 'comment' else match.group(),
        source)


def interface(source, module_name):
    """Đọc giao tiếp ANSI hiện có; dừng nếu có khai báo chưa được hỗ trợ."""
    clean = without_comments(source)
    match = re.search(
        r'\bmodule\s+' + re.escape(module_name)
        + r'\s*#\((.*?)\)\s*\((.*?)\)\s*;', clean, re.S)
    if not match:
        raise RuntimeError('Không đọc được giao tiếp module: ' + module_name)
    parameters, port_text = match.groups()
    if not re.fullmatch(
            r"\s*parameter\s+\[31:0\]\s+RESET_VECTOR\s*=\s*32'h0000_0000\s*",
            parameters):
        raise RuntimeError('Tham số module đã đổi: ' + module_name)
    ports = []
    for declaration in port_text.split(','):
        port = re.fullmatch(
            r'\s*(input|output)\s+(?:wire|reg)\s*'
            r'(\[[^\]]+\])?\s*([A-Za-z_][A-Za-z_0-9]*)\s*', declaration)
        if not port:
            raise RuntimeError('Khai báo cổng chưa hỗ trợ: ' + declaration)
        direction, width, name = port.groups()
        ports.append((direction, width or '', name))
    return ports


def wrapper(module_name, ports):
    """Tạo lớp bọc tương thích hoàn toàn giao tiếp testbench hiện hữu."""
    declarations = ',\n'.join(
        f'    {direction} wire {width} {name}' for direction, width, name in ports)
    outputs = [(width, name) for direction, width, name in ports
               if direction == 'output']
    lines = [
        '`timescale 1ns/1ps', '`default_nettype none',
        '// Tệp sinh tự động: hai bản nhận cùng đầu vào và cùng RESET_VECTOR.',
        f'module {module_name} #(parameter [31:0] RESET_VECTOR = 32\'h0000_0000) (',
        declarations, ');',
    ]
    for width, name in outputs:
        lines.append(f'    wire {width} tham_chieu_{name};')
    for prefix, instance in (('eq_candidate_', 'u_ban_moi'),
                             ('eq_reference_', 'u_ban_goc')):
        lines.append(f'    {prefix}{module_name} #(.RESET_VECTOR(RESET_VECTOR)) {instance} (')
        lines.append(',\n'.join(
            f'        .{name}('
            + ('tham_chieu_' if instance == 'u_ban_goc' and direction == 'output' else '')
            + name + ')'
            for direction, _, name in ports))
        lines.append('    );')
    lines.extend([
        '    reg da_reset = 1\'b0;',
        '    integer so_lan_so_sanh = 0;',
        '    // Chờ một ns để cập nhật nonblocking và logic tổ hợp ổn định.',
        '    // So payload cả khi invalid để phát hiện thay đổi quy tắc giữ/xóa.',
        '    always @(posedge clk_i or negedge clk_i) begin',
        '        if (clk_i && rst_i) da_reset = 1\'b1;',
        '        #1;',
        '        if (da_reset) begin',
    ])
    for _, name in outputs:
        lines.extend([
            f'            if ({name} !== tham_chieu_{name})',
            f'                $fatal(1, "Sai khác %m.{name} lúc %0t: mới=%h gốc=%h",',
            f'                       $time, {name}, tham_chieu_{name});',
        ])
    lines.extend([
        '            so_lan_so_sanh = so_lan_so_sanh + 1;',
        '        end', '    end',
        '    final begin',
        '        if (so_lan_so_sanh == 0)',
        '            $fatal(1, "Không có lần đối chiếu nào tại %m");',
        '        $display("DOI_CHIEU %m: %0d lần", so_lan_so_sanh);',
        '    end', 'endmodule', '`default_nettype wire', '',
    ])
    return '\n'.join(lines)


def run_logged(command, cwd, log):
    try:
        result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                encoding='utf-8', errors='replace', timeout=120)
    except subprocess.TimeoutExpired:
        write_text(log, 'FAIL: Quá thời gian 120 giây.\n')
        raise RuntimeError('Quá thời gian; xem ' + str(log)) from None
    write_text(log, result.stdout)
    if result.returncode:
        raise RuntimeError(f'Lệnh kết thúc với mã {result.returncode}; xem {log}')
    return result.stdout


def prepare(work, results):
    """Chụp nguồn đầu vào trước khi chạy; xác minh bản ZIP độc lập với manifest mới."""
    if digest(BASELINE.read_bytes()) != BASELINE_SHA256:
        raise RuntimeError('Bản lưu trước tách module không khớp SHA256 cố định')
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read('docs/core_frozen_manifest.json'))
        baseline_sources = {}
        for name, expected in manifest['files'].items():
            data = archive.read(name)
            if digest(data) != expected:
                raise RuntimeError('Tệp gốc không khớp manifest đã lưu: ' + name)
            baseline_sources[name] = data.decode('utf-8')
    baseline_modules = [
        match[1] for source in baseline_sources.values()
        for match in re.finditer(r'\bmodule\s+(\w+)', without_comments(source))
    ]
    rename = {name: 'eq_reference_' + name for name in baseline_modules}
    # Đổi cả tên macro và tên header để bản gốc không dùng định nghĩa của bản mới.
    core_def = 'rtl/core/rv32_defs.vh'
    for name in re.findall(r'`define\s+(\w+)', baseline_sources[core_def]):
        rename[name] = 'EQ_REFERENCE_' + name
    references = []
    for name, source in baseline_sources.items():
        destination = work / 'reference' / name
        if name == core_def:
            destination = destination.with_name('eq_reference_rv32_defs.vh')
        source = source.replace('`include "rv32_defs.vh"',
                                '`include "eq_reference_rv32_defs.vh"')
        write_text(destination, rename_identifiers(source, rename))
        if destination.suffix == '.v':
            references.append(destination)

    sources = soc_rtl_sources(ROOT)
    source_bytes = {p: p.read_bytes() for p in sources}
    headers = [p for p in (ROOT / 'rtl').rglob('*.vh') if p.is_file()]
    for path in headers:
        source_bytes[path] = path.read_bytes()
    results['sha256_nguon'] = {
        p.relative_to(ROOT).as_posix(): digest(data)
        for p, data in source_bytes.items()}
    results['sha256_qsf'] = digest((ROOT / 'quartus/riscv_soc.qsf').read_bytes())
    for path, data in source_bytes.items():
        destination = work / 'candidate' / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    candidates = [work / 'candidate' / p.relative_to(ROOT) for p in sources]

    builds = {}
    for target, relative in (
            ('rv32_core', 'rtl/core/rv32_core.v'),
            ('rv32_if_stage', 'rtl/core/if/rv32_if_stage.v')):
        candidate = work / 'candidate' / relative
        source = candidate.read_text(encoding='utf-8')
        ports = interface(source, target)
        if ports != interface(baseline_sources[relative], target):
            raise RuntimeError('Giao tiếp đã thay đổi: ' + target)
        renamed = work / (target + '_candidate.v')
        write_text(renamed, rename_identifiers(source, {target: 'eq_candidate_' + target}))
        wrapped = work / (target + '_wrapper.sv')
        write_text(wrapped, wrapper(target, ports))
        builds[target] = [p for p in candidates if p != candidate] + [renamed, wrapped] + references
    for name in BENCHES:
        path = ROOT / name
        destination = work / 'benches' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(path.read_bytes())
        results.setdefault('sha256_testbench', {})[name] = digest(path.read_bytes())
    return builds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='sau_tach',
                        help='Nhãn thư mục lưu log và kết quả, không ghi đè nhãn đã có')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        raise RuntimeError('Nhãn chỉ được chứa chữ, số, gạch ngang hoặc gạch dưới')
    for tool in ('iverilog', 'vvp'):
        if not shutil.which(tool):
            raise RuntimeError('Thiếu Icarus Verilog; hãy chạy trong Ubuntu/WSL đã cài công cụ')
    work = ROOT / 'sim/module_equivalence' / args.label
    if work.exists():
        raise RuntimeError('Nhãn đã tồn tại; dùng nhãn mới để giữ chứng cứ: ' + args.label)
    work.mkdir(parents=True)
    results = {
        'trang_thai': 'DANG_CHAY',
        'thoi_diem_utc': datetime.now(timezone.utc).isoformat(),
        'baseline': BASELINE.relative_to(ROOT).as_posix(),
        'baseline_sha256': BASELINE_SHA256,
        'sha256_cong_cu_doi_chieu': digest(Path(__file__).read_bytes()),
        'pham_vi': 'Tất cả output, cả payload invalid; sau hai cạnh clock kể từ reset.',
        'gioi_han': 'Kiểm thử vi sai hữu hạn, không phải chứng minh hình thức.',
        'ca_kiem_thu': [],
    }
    try:
        version = run_logged(['iverilog', '-V'], work, work / 'iverilog_version.log')
        results['iverilog'] = version.splitlines()[0]
        builds = prepare(work, results)
        jobs = [(name, None) for name in BENCHES]
        jobs += [('tb/core/tb_rv32_core.v', seed) for seed in range(1, 17)]
        for name, seed in jobs:
            bench = work / 'benches' / name
            top = bench.stem
            label = top if seed is None else top + '_seed_' + str(seed)
            target = 'rv32_if_stage' if top == 'tb_rv32_if_stage' else 'rv32_core'
            executable = work / (label + '.vvp')
            command = ['iverilog', '-g2012']
            for relative in ('rtl/core', 'rtl/bus', 'rtl/accelerator'):
                command += ['-I', str(work / 'candidate' / relative)]
            command += ['-I', str(work / 'reference/rtl/core')]
            command += ['-s', top, '-o', str(executable)]
            if seed is not None:
                command += ['-P', top + '.STRESS_SEED=' + str(seed)]
            command += list(map(str, builds[target])) + [str(bench)]
            run_logged(command, work, work / ('compile_' + label + '.log'))
            output = run_logged(['vvp', str(executable)], work, work / (label + '.log'))
            comparisons = [int(value) for value in re.findall(r'DOI_CHIEU [^\n]*: (\d+) lần', output)]
            if (re.search(r'\b(?:FAIL|ERROR|FATAL)\b', output, re.I)
                    or not re.search(r'\bPASS\b', output)
                    or not comparisons or min(comparisons) == 0):
                raise RuntimeError('Thiếu PASS/đối chiếu hoặc có lỗi: ' + label)
            results['ca_kiem_thu'].append({
                'ten': label, 'trang_thai': 'PASS',
                'so_instance': len(comparisons),
                'so_lan_doi_chieu': sum(comparisons),
            })
            print(f'{label}: PASS ({sum(comparisons)} lần đối chiếu)', flush=True)
        results['trang_thai'] = 'PASS'
        results['tong_ca'] = len(jobs)
        results['tong_lan_doi_chieu'] = sum(
            case['so_lan_doi_chieu'] for case in results['ca_kiem_thu'])
        print(f"PASS: {len(jobs)}/{len(jobs)} ca; {results['tong_lan_doi_chieu']} lần đối chiếu.")
    except (OSError, RuntimeError, ValueError, KeyError, zipfile.BadZipFile) as error:
        results['trang_thai'] = 'FAIL'
        results['loi'] = str(error)
        raise
    finally:
        write_text(work / 'results.json', json.dumps(results, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit('FAIL: ' + str(error)) from None
