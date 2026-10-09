import re

def rename_ports(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Rename ports
    content = re.sub(r'\bidex_([a-zA-Z0-9_]+)_i\b', r'\1_ex_i', content)
    content = re.sub(r'\bexmem_([a-zA-Z0-9_]+)_i\b', r'\1_mem_i', content)
    content = re.sub(r'\bmemwb_([a-zA-Z0-9_]+)_i\b', r'\1_wb_i', content)
    content = re.sub(r'\bifid_([a-zA-Z0-9_]+)_i\b', r'\1_id_i', content)
    
    # special case for consumed
    content = content.replace('consumed_id_i', 'ifid_consumed_i') # Wait, ifid_consumed_o is an output.
    content = re.sub(r'\bifid_([a-zA-Z0-9_]+)_o\b', r'\1_id_o', content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

rename_ports(r'c:\FPGA\riscv_soc_de10_lite - Copy\rtl\core\control\rv32_pipeline_control.v')
rename_ports(r'c:\FPGA\riscv_soc_de10_lite - Copy\rtl\core\rv32_core.v')
