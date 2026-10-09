#!/usr/bin/env python3
"""Build unmodified upstream RV32UI tests and run the frozen core in Icarus.

Run in Linux/WSL. No downloads or package installs occur in this script.
The local adapter replaces only the privileged execution environment.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'sim/isa'
ENV = ROOT / 'tb/core/isa/env'
UPSTREAM = ROOT / 'third_party/riscv-tests'
PREFIX = 'riscv64-unknown-elf-'
UPSTREAM_COMMIT = 'bcffa2b3188b040c611f90dc0b6e422f54775a09'


def run(command, log=None):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True,
                            text=True, timeout=120)
    if log:
        log.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(' '.join(map(str, command)) + '\n' + result.stdout + result.stderr)
    return result.stdout


def local_tests():
    """Explicit trap expectations; forbidden extensions must trap, never retire."""
    result = []
    cases = {
        'ecall': ('ecall', 11), 'ebreak': ('ebreak', 3),
        'illegal_zero': ('.word 0', 2), 'illegal_m': ('.word 0x022081b3', 2),
        'illegal_c': ('.word 0x00010001', 2), 'illegal_csr': ('.word 0x30001073', 2),
        'illegal_mret': ('.word 0x30200073', 2), 'illegal_fence_i': ('.word 0x0000100f', 2),
        'jal_misaligned': ('jal ra, .+2', 0),
        'jalr_misaligned': ('jalr ra,t0,2', 0),
        'branch_misaligned': ('beq zero,zero,.+2', 0),
        'lh_misaligned': ('lh t1,1(t0)', 4), 'lhu_misaligned': ('lhu t1,1(t0)', 4),
        'lw_misaligned_1': ('lw t1,1(t0)', 4), 'lw_misaligned_2': ('lw t1,2(t0)', 4),
        'lw_misaligned_3': ('lw t1,3(t0)', 4),
        'sh_misaligned': ('sh t1,1(t0)', 6),
        'sw_misaligned_1': ('sw t1,1(t0)', 6), 'sw_misaligned_2': ('sw t1,2(t0)', 6),
        'sw_misaligned_3': ('sw t1,3(t0)', 6),
        'load_access': ('lw t1,0(t0)', 5), 'store_access': ('sw t1,0(t0)', 7),
        'load_x0_access': ('lw zero,0(t0)', 5),
    }
    for name, (instruction, cause) in cases.items():
        setup = 'li t0,0x10000' if 'access' in name else 'li t0,0x8000'
        body = f'li a0,1\nli t2,0xff00\nli t1,99\n{setup}\n.globl expected_trap\nexpected_trap:\n{instruction}\nsb t1,0(t2)\nebreak\n'
        result.append((name, body, cause, 'expected_trap'))
    result.append(('instruction_access', 'li a0,1\nli t0,0x10000\njr t0\nebreak\n', 1, 0x10000))
    # Bit zero is cleared; link must remain the address after JALR. Also test
    # not-taken misaligned branch (must not trap) and FENCE with pending store.
    result.append(('jalr_bit0_fence', '''
li a0,0
la t0,target
ori t0,t0,1
jalr ra,t0,0
link: j fail
target:
la t1,link
bne ra,t1,fail
bne zero,zero,.+2
li t0,0x8000
li t1,-1
sw t1,0(t0)
fence iorw,iorw
lw t2,0(t0)
bne t1,t2,fail
addi zero,t1,4
bne zero,zero,fail
li a0,1
.globl expected_trap
expected_trap: ebreak
fail: li a0,0
ebreak
''', 3, 'expected_trap'))
    return result


def main():
    for tool in [PREFIX+'gcc', PREFIX+'objcopy', PREFIX+'nm', 'iverilog', 'vvp']:
        if not shutil.which(tool):
            raise RuntimeError('Missing '+tool)
    if not (UPSTREAM / 'isa/rv32ui/Makefrag').exists():
        raise RuntimeError('Missing third_party/riscv-tests; see docs/isa_verification_vi.md')
    commit = run(['git','-C',UPSTREAM,'rev-parse','HEAD']).strip()
    if commit != UPSTREAM_COMMIT:
        raise RuntimeError('Unexpected riscv-tests revision: '+commit)
    run(['git','-C',UPSTREAM,'diff','--exit-code','HEAD','--','isa'])
    OUT.mkdir(parents=True, exist_ok=True)
    rtl = sorted((ROOT / 'rtl/core').rglob('*.v'))
    run(['iverilog', '-g2012', '-I', ROOT/'rtl/core', '-s', 'isa_core_harness',
         '-o', OUT/'isa.vvp', *rtl, ROOT/'tb/core/isa/isa_core_harness.sv'], OUT/'compile.log')
    excluded = {'fence_i': 'Zifencei is not implemented; illegal encoding tested locally',
                'ma_data': 'EEI traps misaligned data instead of emulating it; local trap cases replace this test'}
    tests = [(p.stem, p, 3, 'rvtest_pass', 'upstream')
             for p in sorted((UPSTREAM/'isa/rv32ui').glob('*.S')) if p.stem not in excluded]
    for name, body, cause, symbol in local_tests():
        path = OUT/(name+'.S')
        path.write_text('.option norvc\n.option norelax\n.section .text.init\n.globl _start\n_start:\n'+body)
        tests.append((name, path, cause, symbol, 'local'))
    results = []
    for name, source, cause, symbol, origin in tests:
        elf, binary, image = (OUT/(name+suffix) for suffix in ['.elf', '.bin', '.hex'])
        run([PREFIX+'gcc', '-march=rv32i', '-mabi=ilp32', '-nostdlib', '-nostartfiles',
             '-mno-relax', '-I', ENV, '-I', UPSTREAM/'isa/macros/scalar',
             '-Wl,-T,'+str(ENV/'link.ld'), '-Wl,--no-relax', source, '-o', elf], OUT/(name+'.build.log'))
        run([PREFIX+'objcopy', '-O', 'binary', elf, binary])
        data = binary.read_bytes()
        assert len(data) < 0xf000
        image.write_text(''.join(f'{b:02x}\n' for b in data.ljust(65536, b'\0')))
        symbols = run([PREFIX+'nm', elf])
        address = symbol if isinstance(symbol, int) else int(re.search(r'^([0-9a-f]+) \w '+symbol+r'$', symbols, re.M)[1], 16)
        case_count = len(re.findall(r'\btest_\d+$', symbols, re.M)) if origin=='upstream' else 1
        for seed in [0, 17, 20260927]:
            log = OUT/f'{name}_seed{seed}.log'
            output = run(['vvp', OUT/'isa.vvp', f'+IMAGE={image}', f'+PC={address:x}',
                          f'+CAUSE={cause}', f'+SEED={seed}'], log)
            if 'PASS ISA' not in output or re.search(r'\b(FATAL|FAIL|ERROR)\b', output):
                raise RuntimeError(f'{name} failed: '+output)
            results.append(dict(name=name, origin=origin, seed=seed, cases=case_count,
                                status='PASS', detail=output.strip(), sha256=hashlib.sha256(data).hexdigest()))
        print(f'PASS {name}: {case_count} cases x 3 schedules', flush=True)
    report = dict(upstream_commit=commit,
                  compiler=run([PREFIX+'gcc','--version']).splitlines()[0],
                  excluded=excluded, results=results)
    (OUT/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'RESULT: PASS {len(results)}/{len(results)} ISA runs')


if __name__ == '__main__':
    main()
