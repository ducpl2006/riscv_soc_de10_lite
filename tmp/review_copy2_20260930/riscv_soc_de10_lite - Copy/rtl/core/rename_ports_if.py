import re

def rename_ports(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Rename ports
    content = re.sub(r'\bifid_([a-zA-Z0-9_]+)_i\b', r'\1_id_i', content)
    content = re.sub(r'\bifid_([a-zA-Z0-9_]+)_o\b', r'\1_id_o', content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

rename_ports(r'c:\FPGA\riscv_soc_de10_lite - Copy\rtl\core\if\rv32_if_stage.v')
