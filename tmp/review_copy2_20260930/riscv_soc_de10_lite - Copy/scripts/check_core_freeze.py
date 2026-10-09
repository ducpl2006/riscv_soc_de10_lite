#!/usr/bin/env python3
"""Fail if any frozen core file changes, disappears, or is added."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
expected = json.loads((root/'docs/core_frozen_manifest.json').read_text())['files']
actual = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (root/'rtl/core').rglob('*') if p.is_file()}
if actual != expected:
    changed = sorted(k for k in actual.keys() | expected.keys() if actual.get(k) != expected.get(k))
    raise SystemExit('CORE FREEZE MISMATCH: '+', '.join(changed))
print(f'PASS CORE BASELINE FROZEN: {len(actual)} files unchanged')
