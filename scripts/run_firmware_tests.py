#!/usr/bin/env python3
"""Rebuild RV32I C images, golden assets and run firmware tests in Linux/WSL."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from generate_firmware_vectors import generate, ASSETS
from soc_rtl_sources import soc_rtl_sources

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'sim/iverilog/work'
LOGS=ROOT/'sim/firmware'


def run(command, log, cwd=ROOT):
    p=subprocess.run(list(map(str,command)),cwd=cwd,capture_output=True,text=True,timeout=180)
    log.write_text(p.stdout+p.stderr,encoding='utf-8')
    if p.returncode: raise RuntimeError(f'{command[0]} failed; {log}\n'+p.stdout+p.stderr)
    return p.stdout


def main():
    WORK.mkdir(parents=True,exist_ok=True); LOGS.mkdir(parents=True,exist_ok=True)
    generate()
    images=[]
    for name,mode in [('fake',1),('ina228',2),('board',0)]:
        output=ROOT/'firmware/build'/('verify_'+name)
        args=[sys.executable,ROOT/'scripts/build_firmware.py','--prefix','riscv64-unknown-elf-',
              '--output-dir',output,'--define',f'FIRMWARE_SENSOR_MODE={mode}']
        if mode: args+=['--define','SOC_CLOCK_HZ=1000000']
        if mode==2:
            args+=['--define','BOARD_INA228_ADDRESS=64','--define','BOARD_SHUNT_UOHM=10000',
                   '--define','BOARD_CURRENT_LSB_NA=10000']
        run(args,LOGS/(name+'_build.log'))
        data=(output/'boot.bin').read_bytes()
        # Fill the entire ROM image to keep simulator reads deterministic.
        words=(output/'boot.hex').read_text().splitlines()
        if mode: (ASSETS/(name+'.hex')).write_text('\n'.join(words+['00000013']*(8192-len(words)))+'\n')
        images.append(dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
    run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-Ifirmware/include',
         'tb/firmware/test_pipeline_ina228.c','firmware/sample_pipeline.c','firmware/ina228.c',
         '-o',LOGS/'test_host'],LOGS/'host_build.log')
    host=run([LOGS/'test_host'],LOGS/'host.log')
    if host.count('PASS firmware')!=2: raise RuntimeError('Missing host PASS')
    print(host,end='',flush=True)
    rtl=soc_rtl_sources(ROOT)
    results=[]
    for mode,fault in [(1,0)]+[(2,f) for f in range(8)]:
        name=f'sensor{mode}_fault{fault}'
        exe=LOGS/(name+'.vvp')
        run(['iverilog','-g2012','-I',ROOT/'rtl/core','-I',ROOT/'rtl/bus','-I',ROOT/'rtl/accelerator',
             '-s','tb_rv32_firmware_e2e',f'-Ptb_rv32_firmware_e2e.SENSOR_MODE={mode}',
             f'-Ptb_rv32_firmware_e2e.FAULT_MODE={fault}','-o',exe,*rtl,
             ROOT/'tb/soc/tb_rv32_firmware_e2e.sv'],LOGS/(name+'_compile.log'))
        output=run(['vvp',exe],LOGS/(name+'.log'),WORK)
        if not re.search(r'PASS tb_rv32_firmware_e2e',output) or re.search(r'\b(FAIL|FATAL|ERROR)\b',output):
            raise RuntimeError(name+': '+output)
        results.append(dict(name=name,status='PASS',detail=output.strip()))
        print(f'PASS {name}',flush=True)
    sources={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
             for base in ['firmware','tb/firmware'] for p in (ROOT/base).rglob('*')
             if p.is_file() and 'build' not in p.parts and p.suffix in ['.c','.h','.S','.ld']}
    (LOGS/'results.json').write_text(json.dumps(dict(images=images,sources=sources,host_groups=2,results=results),indent=2)+'\n')
    (ASSETS/'build_manifest.json').write_text(json.dumps(dict(images=images,sources=sources),indent=2)+'\n')
    print('RESULT: PASS 9/9 firmware RTL scenarios + 2 host test groups')


if __name__=='__main__': main()
