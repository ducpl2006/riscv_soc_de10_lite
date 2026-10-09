#!/usr/bin/env python3
"""Đối chiếu token core với bản đóng băng trước đợt làm rõ mã 2026-09-29.

Chỉ cho phép đổi chú thích thông thường và khoảng trắng. Không thay thế
check_core_freeze.py: công cụ đó vẫn kiểm tra chính xác từng byte của bản chốt.
"""

import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'docs/core_readability_baseline_20260929.zip'
BASELINE_SHA256 = '3546d48583c452ca1c147f108d8f7c258b7ab53edfdf5eafdfaeb0fa4cf89dbd'

# Chuỗi và tên thoát phải được nhận diện trước khi bỏ chú thích.
LEXEME = re.compile(
    r'(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)'
    r'|(?P<string>"(?:\\[\s\S]|[^"\\])*")'
    r'|(?P<escaped>\\[^\s]+)'
    r'|(?P<space>\s+)'
    r'|(?P<number>(?:[0-9][0-9_]*[ \t]*)?\'[sS]?[bBoOdDhH][ \t]*[0-9a-fA-F_xXzZ?]+'
    r'|\'[01xXzZ]|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?)'
    r'|(?P<name>[$A-Za-z_][$A-Za-z_0-9]*)'
    r'|(?P<operator><<<|>>>|===|!==|==\?|!=\?|<<=|>>=|\*\*|&&|\|\||==|!='
    r'|<=|>=|<<|>>|~&|~\||~\^|\^~|\+\+|--|\+=|-=|\*=|/=|%=|&=|\|=|\^='
    r'|->|=>|\*>|\+:|-:|::|``)'
    r'|(?P<single>[^\s])'
)
TOOL_COMMENT = re.compile(
    r'\b(?:synthesis|synopsys|pragma|verilator|altera|translate_off|translate_on'
    r'|full_case|parallel_case)\b', re.I
)
DIRECTIVE = re.compile(
    r'^\s*`(?:define|undef|ifdef|ifndef|elsif|else|endif|include|timescale'
    r'|default_nettype|resetall|celldefine|endcelldefine|unconnected_drive'
    r'|nounconnected_drive)\b'
)


def tokens(source):
    """Giữ ranh giới token, chuỗi và kết thúc dòng của chỉ thị tiền xử lý."""
    clean = []
    tool_comments = []
    for match in LEXEME.finditer(source):
        value = match.group()
        if match.lastgroup == 'comment':
            if TOOL_COMMENT.search(value):
                tool_comments.append(value)
                clean.append(f' __chu_thich_cong_cu_{len(tool_comments)}__ ')
            clean.append(' ' + '\n' * value.count('\n'))
        else:
            clean.append(value)
    cleaned = ''.join(clean)
    # Macro phụ thuộc vị trí cần cách kiểm chứng riêng khi đổi số dòng.
    if re.search(r'`(?:__LINE__|__FILE__|line)\b', cleaned):
        raise ValueError('Không hỗ trợ chỉ thị/macro phụ thuộc vị trí mã nguồn')
    result = []
    continued_directive = False
    for line in cleaned.splitlines(keepends=True):
        is_directive = continued_directive or bool(DIRECTIVE.match(line))
        result.extend(m.group() for m in LEXEME.finditer(line)
                      if m.lastgroup != 'space')
        if is_directive:
            result.append('<kết thúc dòng chỉ thị>')
        continued_directive = is_directive and line.rstrip('\r\n').endswith('\\')
    return result, tool_comments


def main():
    if hashlib.sha256(BASELINE.read_bytes()).hexdigest() != BASELINE_SHA256:
        raise ValueError('Bản lưu gốc không khớp SHA256 đã ghi nhận')
    with zipfile.ZipFile(BASELINE) as archive:
        manifest = json.loads(archive.read('docs/core_frozen_manifest.json'))
        expected = manifest['files']
        actual = {p.relative_to(ROOT).as_posix(): p for p in
                  (ROOT / 'rtl/core').rglob('*') if p.is_file()}
        if actual.keys() != expected.keys():
            raise ValueError('Danh sách tệp core thay đổi: ' + ', '.join(
                sorted(actual.keys() ^ expected.keys())))
        changed = []
        for name, old_hash in expected.items():
            before = archive.read(name)
            after = actual[name].read_bytes()
            if hashlib.sha256(before).hexdigest() != old_hash:
                raise ValueError('Tệp gốc không khớp manifest: ' + name)
            if tokens(before.decode('utf-8')) != tokens(after.decode('utf-8')):
                raise ValueError('Token hoặc chỉ thị công cụ đã đổi: ' + name)
            if before != after:
                changed.append(name)
    print(f'PASS: {len(actual)}/{len(expected)} tệp giữ nguyên token Verilog.')
    print(f'Chỉ đổi cách trình bày ở {len(changed)} tệp:')
    for name in changed:
        print('  ' + name)


if __name__ == '__main__':
    # Console Windows có thể dùng bảng mã không biểu diễn đủ tiếng Việt.
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit('FAIL: ' + str(error)) from None
