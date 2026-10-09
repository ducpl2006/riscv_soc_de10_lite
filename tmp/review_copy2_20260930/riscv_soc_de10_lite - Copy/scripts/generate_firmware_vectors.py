#!/usr/bin/env python3
"""Independent integer reference: raw samples -> features -> trained QNN -> UART.

Generated assets are checked in so ModelSim regression needs no cross compiler.
Use run_firmware_tests.py to rebuild firmware images as well.
"""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'tb/soc/firmware_assets'
MODEL=ROOT/'firmware/model'


def signed(value, bits):
    return (value+(1<<(bits-1)))%(1<<bits)-(1<<(bits-1))


def numbers(name, bits):
    return [signed(int(v,16),bits) for v in (MODEL/name).read_text().split()]


def qnn(features):
    manifest=json.loads((MODEL/'model_manifest.json').read_text())
    # Hardware export explicitly uses 8,7,1 shifts; guard against model changes.
    config=(ROOT/'rtl/accelerator/qnn_model_config.vh').read_text()
    import re
    shifts=[int(re.search(r'QNN_MODEL_'+n+r'_SHIFT\s+(\d+)',config)[1]) for n in ['L1','L2','OUT']]
    x=features
    for name,count,shift,limit in [('l1',16,shifts[0],127),('l2',8,shifts[1],127),('out',1,shifts[2],1000)]:
        weights=numbers(name+'_weights.hex',8)
        biases=numbers(name+('_bias.hex' if name=='out' else '_biases.hex'),32)
        y=[]
        for n in range(count):
            acc=biases[n]
            for j,value in enumerate(x): acc=signed(acc+value*weights[n*len(x)+j],32)
            y.append(max(0,min(limit,acc>>shift)))
        x=y
    return x[0]


def write_hex(path, values, digits):
    path.write_text(''.join(f'{value & ((1<<(4*digits))-1):0{digits}x}\n' for value in values))


def generate():
    ASSETS.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((MODEL/'model_manifest.json').read_text())
    center,scale=manifest['feature_center'],manifest['feature_scale']
    for mode in ['fake','ina228']:
        samples=[]; bus_words=[]; current_words=[]; shunt_words=[]
        for n in range(25):
            v=3402+5*(n-10); current=-1000+24*(n%7-3); temperature=225+2*(n%5-2)
            bus_raw=v*128//25
            if mode=='ina228': v=bus_raw*25//128
            bus_words.append(bus_raw<<4)
            current_words.append((current*100 & 0xfffff)<<4) # Test config: 10 uA/count.
            shunt_words.append((current*32 & 0xfffff)<<4) # Test shunt: 10 milliohm.
            samples.append([v,current,temperature,10000])
        all_features=[]; results=[]
        for end in range(20,26):
            features=[]
            for sample in samples[end-20:end]:
                for value,c,s in zip(sample,center,scale):
                    delta=value-c
                    q=(abs(delta)//s)*(1 if delta>=0 else -1)
                    features.append(max(-128,min(127,q)))
            all_features.extend(features); results.append(qnn(features))
        message='SIM\n'+''.join(f'SOC={r//10}.{r%10}%\n' for r in results)+'DONE\n'
        write_hex(ASSETS/(mode+'_features.hex'),all_features,2)
        write_hex(ASSETS/(mode+'_results.hex'),results,8)
        write_hex(ASSETS/(mode+'_uart.hex'),list(message.encode())+[0]*(128-len(message)),2)
        write_hex(ASSETS/(mode+'_uart_length.hex'),[len(message)],8)
        if mode=='ina228':
            for name,values in [('bus',bus_words),('current',current_words),('shunt',shunt_words)]:
                write_hex(ASSETS/(name+'_raw.hex'),values,6)
        (ASSETS/(mode+'_reference.json')).write_text(json.dumps(dict(model_id=manifest['model_id'],samples=samples,
            results=results,uart=message),indent=2)+'\n')


if __name__=='__main__': generate()
