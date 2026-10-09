#!/usr/bin/env python3
"""Build firmware RV32I bằng toolchain trên PATH; chỉ dùng thư viện chuẩn Python."""

import argparse
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', help='Ví dụ: riscv32-unknown-elf-')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'firmware/build')
    parser.add_argument('--rom-words', type=int, default=8192)
    parser.add_argument('--define', action='append', default=[], help='Preprocessor NAME=VALUE (repeatable)')
    args = parser.parse_args()
    if not 1 <= args.rom_words <= 8192:
        parser.error('--rom-words phải trong khoảng 1..8192')
    prefix = args.prefix or next((p for p in (
        'riscv32-unknown-elf-', 'riscv64-unknown-elf-',
    ) if shutil.which(p + 'gcc')), None)
    if prefix is None:
        parser.error('Thiếu GNU RISC-V compiler trên PATH')
    for tool in ('gcc', 'objcopy', 'objdump'):
        if not shutil.which(prefix + tool):
            parser.error(f'Thiếu {prefix}{tool} trên PATH')

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    firmware = ROOT / 'firmware'
    elf = output / 'boot.elf'
    binary = output / 'boot.bin'
    subprocess.run([
        prefix + 'gcc', '-march=rv32i', '-mabi=ilp32', '-mcmodel=medany',
        '-Os', '-ffreestanding', '-fno-builtin', '-fno-common',
        '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
        '-nostartfiles', '-nostdlib', f'-Wl,-T,{firmware / "linker.ld"}',
        f'-Wl,-Map,{output / "boot.map"}', '-Wl,--gc-sections',
        '-msmall-data-limit=0', '-mno-relax', '-Wl,--no-relax',
        *['-D'+item for item in args.define],
        str(firmware / 'start.S'), str(firmware / 'main.c'),
        str(firmware / 'sample_pipeline.c'), str(firmware / 'soc_platform.c'),
        str(firmware / 'ina228.c'), str(firmware / 'runtime.c'), '-lgcc', '-o', str(elf),
    ], check=True)
    subprocess.run([prefix + 'objcopy', '-O', 'binary', str(elf), str(binary)], check=True)
    with (output / 'boot.disasm').open('w', encoding='utf-8') as stream:
        subprocess.run([prefix + 'objdump', '-d', '-S', str(elf)], stdout=stream, check=True)

    data = binary.read_bytes()
    if len(data) > args.rom_words * 4:
        parser.error(f'Firmware {len(data)} byte vượt ROM {args.rom_words * 4} byte')
    words = [int.from_bytes(data[i:i + 4].ljust(4, b'\0'), 'little')
             for i in range(0, len(data), 4)]
    (output / 'boot.hex').write_text(
        ''.join(f'{word:08X}\n' for word in words), encoding='utf-8')
    mif = [f'DEPTH = {args.rom_words};', 'WIDTH = 32;',
           'ADDRESS_RADIX = HEX;', 'DATA_RADIX = HEX;', 'CONTENT BEGIN']
    mif.extend(f'    {i:04X} : {word:08X};' for i, word in enumerate(words))
    if len(words) < args.rom_words:
        mif.append(f'    [{len(words):04X}..{args.rom_words - 1:04X}] : 00000013;')
    mif.append('END;')
    (output / 'boot.mif').write_text('\n'.join(mif) + '\n', encoding='utf-8')
    print(f'Firmware OK: {len(data)} byte, {len(words)}/{args.rom_words} word ROM.')
    print(f'Output: {output}')


if __name__ == '__main__':
    main()
