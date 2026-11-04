"""Export the DXF mid4 RF order in the user-confirmed chip0-right view."""
import csv
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rf_left_to_right = (4, 3, 1, 2)
rows = []
for array, name in enumerate(('RX', 'TX')):
    for line in range(8):
        for chip in range(4):
            for channel in range(4):
                rf = channel + 1
                position = (3-chip)*4 + rf_left_to_right.index(rf)
                rows.append(dict(array=array, array_name=name,
                    connector=f'J{line+1}' if array == 0 else '',
                    line=line, sdi=f'SDI{chip+1}', chip=chip, cid=chip,
                    channel=channel, rf=f'RF{rf}',
                    element_from_left=position+1,
                    x_mm=f'{(position-7.5)*9.6:.1f}',
                    y_mm_index_convention=f'{(line-3.5)*9.6:.1f}',
                    orientation_basis='user photo: chip0 right; DXF mid4 RF4/RF3/RF1/RF2',
                    y_status='line-index convention; installed vertical direction unspecified'))
path = root/'docs'/'V03阵面通道坐标映射_20261029.csv'
with path.open('w', newline='', encoding='utf-8-sig') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
assert len(rows) == 256
for array in range(2):
    for line in range(8):
        group=[r for r in rows if r['array']==array and r['line']==line]
        assert sorted(r['element_from_left'] for r in group)==list(range(1,17))
print(f'Wrote {len(rows)} rows: {path}')
