"""Decode the pin captures independently and compare the FPGA result probe."""
import csv
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
chip = int(sys.argv[2]) if len(sys.argv) > 2 else 3
channel = int(sys.argv[3]) if len(sys.argv) > 3 else 0
assert 0 <= chip <= 3 and 0 <= channel <= 3
attenuation = int(sys.argv[4]) if len(sys.argv) > 4 else 1
stem = f'chip{chip}_channel{channel}'

def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))[1:]

def decode(path):
    data = rows(path)
    frames = []
    old_cs, old_clk = 1, 0
    bits, received = [[] for _ in range(4)], []
    for i, row in enumerate(data):
        cs, clk, sdi, sdo = [int(row[key], 16) for key in
            ('rx_csb_o_OBUF[0:0]', 'rx_clk_o_OBUF[0:0]',
             'rx_sdi_o_OBUF[3:0]', 'rx_sdo_i_IBUF[0:0]')]
        if old_cs and not cs:
            bits, received = [[] for _ in range(4)], []
            start = i
        if not cs and not old_clk and clk:
            for c in range(4):
                bits[c].append((sdi >> c) & 1)
            received.append(sdo)
        if not old_cs and cs:
            if len(received) != 24:
                raise ValueError(f'{path}: incomplete frame {len(received)}')
            as_int = lambda sequence: int(''.join(map(str, sequence)), 2)
            # Match hardware sampling: discard the stale first sample, capture
            # the last bit while CS is still low, immediately before CS rises.
            final = int(data[i-1]['rx_sdo_i_IBUF[0:0]'], 16)
            frames.append(dict(start_sample=start, end_sample=i,
                sdi=[f'{as_int(b):06X}' for b in bits],
                sdo=f'{as_int(received[1:] + [final]):06X}'))
        old_cs, old_clk = cs, clk
    return frames

result = {name: decode(directory / f'{stem}_{name}_pins.csv') for name in ('write', 'read')}
done = [r for r in rows(directory / f'{stem}_read_result.csv') if int(r['read_done'], 16)]
errors = [r for r in rows(directory / f'{stem}_read_result.csv') if int(r['read_error'], 16)]
result['read_done_count'] = len(done)
result['read_error_count'] = len(errors)
result['fpga_read_value'] = [r['read_value[23:0]'].upper() for r in done]
assert len(result['write']) == 2 and len(result['read']) == 2
assert result['write'][1]['sdi'][chip] == f'{(chip << 20) | 0x20000 | (channel << 12) | (attenuation << 6):06X}'
assert result['read'][0]['sdi'][chip] == f'{(chip << 20) | 0xA0000 | (channel << 12):06X}'
assert result['read'][1]['sdi'][chip] == f'{(chip << 20) | 0x80000:06X}'
assert len(done) == 1 and not errors
assert result['read'][1]['sdo'] == result['fpga_read_value'][0]
result['chip'] = chip
result['channel_encoding'] = channel
result['expected_read'] = f'{(chip << 20) | 0xA0000 | (channel << 12) | (attenuation << 6):06X}'
result['write_read_match'] = result['fpga_read_value'] == [result['expected_read']]
output = json.dumps(result, ensure_ascii=False, indent=2)
(directory / f'{stem}_decoded.json').write_text(output, encoding='utf-8')
print(output)
