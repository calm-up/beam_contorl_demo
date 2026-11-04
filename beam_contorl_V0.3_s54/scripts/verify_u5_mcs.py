"""Check Intel HEX structure, checksums and 16 MiB address boundary."""
from pathlib import Path
import hashlib
import os

ROOT = Path(__file__).resolve().parents[1]
FLAVOR = os.environ.get("V03_BUILD_FLAVOR", "base")
MCS = ROOT / "output" / FLAVOR / "beam_control_v03_u5_spix1_16m.mcs"
BIT = ROOT / "output" / FLAVOR / f"beam_control_v03_{FLAVOR}.bit"

upper = 0
count = 0
highest = -1
eof = False
with MCS.open("r", encoding="ascii") as stream:
    for number, line in enumerate(stream, 1):
        line = line.strip()
        if not line or not line.startswith(":"):
            raise ValueError(f"Invalid Intel HEX record at line {number}")
        record = bytes.fromhex(line[1:])
        length = record[0]
        if len(record) != length + 5 or sum(record) & 0xFF:
            raise ValueError(f"Invalid length/checksum at line {number}")
        address = (record[1] << 8) | record[2]
        kind = record[3]
        data = record[4:-1]
        if kind == 0:
            absolute = upper + address
            if absolute + length > 16 * 1024 * 1024:
                raise ValueError(f"Record beyond U5 capacity at line {number}")
            highest = max(highest, absolute + length - 1)
            count += length
        elif kind == 1:
            eof = True
            break
        elif kind == 4 and length == 2:
            upper = ((data[0] << 8) | data[1]) << 16
        else:
            raise ValueError(f"Unexpected record type {kind} at line {number}")
if not eof or not count:
    raise ValueError("Missing EOF or configuration bytes")
for path in (BIT, MCS):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"SHA256 {path.name} {digest}")
print(f"V03_U5_MCS_VERIFY_PASS bytes={count} highest=0x{highest:06X}")
