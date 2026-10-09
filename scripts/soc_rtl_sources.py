"""Read the SoC's literal Verilog source assignments from its Quartus project.

Do not recursively collect RTL: standalone projects can contain different
implementations with the same module name. This supports literal unquoted or
double-quoted paths, not general Tcl evaluation.
"""
from pathlib import Path
import re


def soc_rtl_sources(root):
    project = Path(root) / 'quartus/riscv_soc.qsf'
    sources = []
    for line in project.read_text(encoding='utf-8').splitlines():
        assignment = re.match(
            r'^\s*set_global_assignment\s+-name\s+'
            r'(?:VERILOG_FILE|SYSTEMVERILOG_FILE)\s+(.+?)\s*$', line)
        if not assignment:
            continue
        literal = re.fullmatch(r'"([^"$\[\]]+)"|([^\s"${}\[\]]+)', assignment[1])
        if not literal:
            raise RuntimeError(f'Unsupported RTL path in {project}: {line}')
        source = (project.parent / (literal[1] or literal[2])).resolve()
        if not source.is_file() or source.suffix not in ('.v', '.sv'):
            raise RuntimeError(f'Missing or invalid RTL source: {source}')
        if source in sources:
            raise RuntimeError(f'Duplicate RTL source: {source}')
        sources.append(source)
    if not sources:
        raise RuntimeError(f'No RTL sources in {project}')
    return sources
