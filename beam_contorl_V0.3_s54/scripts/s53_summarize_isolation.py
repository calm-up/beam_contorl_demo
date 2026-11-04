import csv, json, sys
from pathlib import Path

directory=Path(sys.argv[1])
def rows(path):
    with path.open(encoding='utf-8-sig',newline='') as f:
        return list(csv.DictReader(f))[1:]
def pin_frames(path):
    data=rows(path); oldcs=1; oldclk=0; frames=[]; bits=[]; sdo=[]
    for i,r in enumerate(data):
        cs,clk,di,do=[int(r[k],16) for k in ('rx_csb_o_OBUF[0:0]','rx_clk_o_OBUF[0:0]','rx_sdi_o_OBUF[3:0]','rx_sdo_i_IBUF[0:0]')]
        if oldcs and not cs: bits=[];sdo=[]
        if not cs and not oldclk and clk: bits.append((di>>3)&1);sdo.append(do)
        if not oldcs and cs:
            assert len(bits)==24
            val=lambda b:int(''.join(map(str,b)),2)
            final=int(data[i-1]['rx_sdo_i_IBUF[0:0]'],16)
            frames.append({'sdi':f'{val(bits):06X}','sdo':f'{val(sdo[1:]+[final]):06X}'})
        oldcs,oldclk=cs,clk
    falls=[i for i in range(1,len(data)) if data[i-1]['rx_ldb_o_OBUF[0:0]']=='1' and data[i]['rx_ldb_o_OBUF[0:0]']=='0']
    return frames,len(falls)
summary=[]
for rep in (1,2,3):
 for value in ('040','080'):
    stem=f'r{rep}_d{value}'
    writes,write_loads=pin_frames(directory/f'{stem}_write_pins.csv')
    loads,load_count=pin_frames(directory/f'{stem}_load_pins.csv')
    assert writes[0]['sdi']==f'321{value}' and len(writes)==1 and write_loads==0
    assert not loads and load_count==1
    record={'repeat':rep,'written':value,'write_frame':writes[0]['sdi'],'before':None,'after':None}
    for step in ('before','after'):
        raw,unused=pin_frames(directory/f'{stem}_{step}_pins.csv')
        result=rows(directory/f'{stem}_{step}_result.csv')
        done=[r for r in result if int(r['read_done'],16)]
        assert len(done)==1 and not any(int(r['read_error'],16) for r in result)
        observed=done[0]['read_value[23:0]'].upper()
        assert raw[0]['sdi']=='3A1000' and raw[1]['sdi']=='380000' and raw[1]['sdo']==observed
        record[step]=observed
    summary.append(record)
output=json.dumps(summary,indent=2)
(directory/'summary.json').write_text(output,encoding='utf-8')
print(output)
