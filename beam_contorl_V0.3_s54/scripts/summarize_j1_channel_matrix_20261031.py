"""Summarize the 16 J1 chip/channel SPI write/read captures."""
import csv
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
records = []
for chip in range(4):
    for channel in range(4):
        path = directory / f'chip{chip}_channel{channel}_decoded.json'
        data = json.loads(path.read_text(encoding='utf-8'))
        records.append({
            'chip': chip, 'channel': channel, 'rf': f'RF{channel + 1}',
            'attenuation_index': (chip * 4 + channel + 1),
            'write_frame': data['write'][1]['sdi'][chip],
            'read_request': data['read'][0]['sdi'][chip],
            'dummy_frame': data['read'][1]['sdi'][chip],
            'sdo_return': data['read'][1]['sdo'],
            'fpga_read_value': data['fpga_read_value'][0],
            'expected': data['expected_read'],
            'match': data['write_read_match'],
        })
with (directory / 'summary.csv').open('w', newline='', encoding='utf-8-sig') as handle:
    writer = csv.DictWriter(handle, fieldnames=records[0].keys())
    writer.writeheader()
    writer.writerows(records)
summary = {
    'j_port': 'J1 RX', 'bitstream': 's52', 'tested': len(records),
    'matches': sum(r['match'] for r in records),
    'mismatches': sum(not r['match'] for r in records),
    'records': records,
}
(directory / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
for row in records:
    print(f"chip={row['chip']} {row['rf']} write={row['write_frame']} "
          f"read={row['read_request']} dummy={row['dummy_frame']} "
          f"return={row['sdo_return']} expected={row['expected']} "
          f"{'PASS' if row['match'] else 'FAIL'}")
print(f"TOTAL {summary['matches']}/{summary['tested']} match, {summary['mismatches']} mismatch")
