"""Validate one directly probed FPGA read result against an independent value."""
import csv
import sys

path, chip, function, address, expected = sys.argv[1:]
chip, function, address = map(int, (chip, function, address))
expected = int(expected, 16)
with open(path, encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))[1:]
done = [r for r in rows if int(r["read_done"], 16)]
errors = [r for r in rows if int(r["read_error"], 16)]
if errors or len(done) != 1:
    raise SystemExit(f"INVALID done={len(done)} error={len(errors)}")
value = int(done[0]["read_value[23:0]"], 16)
header = (chip << 20) | ((8 | function) << 16)
if function in (4, 5):
    reference = header | (address << 8) | expected
elif function in (6, 7):
    reference = header | (address << 10) | expected
else:
    reference = header | (address << 12) | expected
if value != reference:
    raise SystemExit(f"FAIL got={value:06X} expected={reference:06X}")
print(f"PASS got={value:06X} expected={reference:06X}")
