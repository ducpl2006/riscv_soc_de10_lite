import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BACKUP = Path(__file__).resolve().parent
# Preserve strings and Verilog operators; ignore only comments and whitespace.
LEX = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|\s+|'
                 r'===|!==|>>>|<<<|==|!=|<=|>=|&&|\|\||<<|>>|'
                 r'\*\*|~\^|\^~|~&|~\||\+:|-:|[A-Za-z_$][\w$]*|\d+|.', re.S)


def tokens(path):
    return [s for s in LEX.findall(path.read_text(encoding='utf-8'))
            if not s.isspace() and not s.startswith(('//', '/*'))]


for before in sorted((BACKUP / 'rtl').rglob('*.v')):
    relative = before.relative_to(BACKUP)
    assert tokens(before) == tokens(ROOT / relative), str(relative)
    print('PASS identical RTL tokens:', relative)

for record in json.loads((BACKUP / 'boot_hashes.json').read_text(encoding='utf-8-sig')):
    name = record['Path'].replace('\\', '/').split('/')[-1]
    actual = hashlib.sha256((ROOT / 'firmware/build' / name).read_bytes()).hexdigest()
    assert actual.upper() == record['Hash'], name
    print('PASS unchanged board image:', name)
