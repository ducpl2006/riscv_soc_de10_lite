from pathlib import Path
import sys,re,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'scripts'))
from generate_firmware_vectors import qnn
from soc_rtl_sources import soc_rtl_sources
expected=qnn([3]+[0]*79)
converted={}
for rel in ['firmware/build/boot','firmware/model/l1_weights','firmware/model/l2_weights']:
 p=ROOT/(rel+'.mif');source=p.read_text()
 depth=int(re.search(r'DEPTH\s*=\s*(\d+)',source,re.I)[1]);width=int(re.search(r'WIDTH\s*=\s*(\d+)',source,re.I)[1])
 radix=16 if re.search(r'ADDRESS_RADIX\s*=\s*HEX',source,re.I) else 10
 data=[None]*depth
 for line in source.splitlines():
  m=re.fullmatch(r'\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+)\s*;\s*',line,re.I)
  if not m:continue
  a,b,s,v=m.groups();lo=int(s or a,radix);hi=int(s or b,radix)
  data[lo:hi+1]=[int(v,16)]*(hi-lo+1)
 assert all(x is not None for x in data),p
 hexdata=[int(x,16) for x in (ROOT/(rel+'.hex')).read_text().split()]
 assert data[:len(hexdata)]==hexdata,p
 dest=OUT/(p.stem+'_from_mif.hex');dest.write_text(''.join(f'{x:0{(width+3)//4}x}\n' for x in data));converted['../'+rel+'.mif']=str(dest)
top=(ROOT/'rtl/board/de10_lite_top.v').read_text()
top=top.replace('../accelerator/qnn_model_config.vh',str(ROOT/'rtl/accelerator/qnn_model_config.vh'))
for old,new in converted.items():top=top.replace(old,new)
for name in ['l1_biases','l2_biases','out_weights','out_bias']:
 top=top.replace('../firmware/model/'+name+'.hex',str(ROOT/'firmware/model'/(name+'.hex')))
(OUT/'de10_lite_top_sim.v').write_text(top)
bench=(OUT/'tb_board_baseline_template.sv').read_text().replace('EXPECTED_LED',str(expected&255)).replace('EXPECTED_RESULT',str(expected))
(OUT/'tb_board_baseline.sv').write_text(bench)
rtl=[str(p) for p in soc_rtl_sources(ROOT) if p.name!='de10_lite_top.v']
cmd=['iverilog','-g2012','-I',str(ROOT/'rtl/core'),'-I',str(ROOT/'rtl/bus'),'-I',str(ROOT/'rtl/accelerator'),'-s','tb_board_baseline','-o',str(OUT/'board_baseline.vvp'),*rtl,str(OUT/'de10_lite_top_sim.v'),str(OUT/'tb_board_baseline.sv')]
for command,name in [(cmd,'board_baseline_compile.log'),(['vvp',str(OUT/'board_baseline.vvp')],'board_baseline.log')]:
 r=subprocess.run(command,capture_output=True,text=True,timeout=120);(OUT/name).write_text(r.stdout+r.stderr);print(r.stdout+r.stderr)
 if r.returncode:raise SystemExit(r.returncode)
(OUT/'board_demo_expected.json').write_text(json.dumps({'qnn_result':expected,'ledr_7_0':expected&255,'ledr_9_0':512+(expected&255),'uart':'OK','clock_hz':50000000,'baud_div':434,'trap_cause':3,'trap_pc':72,'mif_hex_verified':True},indent=2)+'\n')
