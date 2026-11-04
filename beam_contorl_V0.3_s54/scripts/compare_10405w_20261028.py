"""Read-only comparison of the updated codebook with RTL's init-frame oracle."""
from pathlib import Path
import hashlib
import re
import sys
import openpyxl

ROOT = Path(__file__).resolve().parents[1]
BOOK = Path(r"D:\beam_control\软件\软件\芯片资料\10405W_12_18_HP_SPI裸片详测码表_20261028.xlsx")
OLD = Path(r"D:\beam_control\软件\软件\芯片资料\CCAR10405L详测码表_202609.xlsx")
ORACLE = ROOT / "ccar10405l_expected_frames.mem"
RTL = ROOT / "rtl" / "beam_ctrl_core.sv"


def bits(sheet, row, first, last):
    vals = [sheet.cell(row, col).value for col in range(first, last + 1)]
    assert all(v in (0, 1) for v in vals), (sheet.title, row, vals)
    return int("".join(str(v) for v in vals), 2)


def extract(book, check_e_column=False):
    w = openpyxl.load_workbook(book, read_only=False, data_only=True)
    control = []
    for address in range(128):
        s = w["Control_Reg"]
        assert s.cell(address + 2, 3).value == address
        value = s.cell(address + 2, 6).value
        assert isinstance(value, int) and 0 <= value <= 255
        e_text = s.cell(address + 2, 5).value
        e_value = int(e_text.split("b", 1)[1].replace("_", ""), 2)
        if check_e_column:
            assert e_value == value, (address, e_text, value)
        control.append(value)
    txps = [bits(w["TXPS"], i + 2, 2, 17) for i in range(64)]
    rxps = [bits(w["RXPS"], i + 2, 2, 17) for i in range(64)]
    txatt = [bits(w["TXATT"], i + 2, 2, 11) for i in range(64)]
    rxatt = [bits(w["RXATT"], i + 2, 2, 11) for i in range(64)]
    return dict(control=control, txps=txps, rxps=rxps, txatt=txatt, rxatt=rxatt)


def control_e_values(book):
    workbook = openpyxl.load_workbook(book, read_only=True, data_only=True)
    sheet = workbook["Control_Reg"]
    return [int(sheet.cell(address + 2, 5).value.split("b", 1)[1].replace("_", ""), 2)
            for address in range(128)]


def frames(data):
    out = []
    out += [0x040000 | (i << 8) | v for i, v in enumerate(data["control"])]
    for i, value in enumerate(data["txps"]):
        out += [0x050000 | (2 * i << 8) | (value >> 8),
                0x050000 | ((2 * i + 1) << 8) | (value & 255)]
    out += [0x060000 | (i << 10) | v for i, v in enumerate(data["txatt"])]
    for i, value in enumerate(data["rxps"]):
        out += [0x050000 | ((128 + 2 * i) << 8) | (value >> 8),
                0x050000 | ((129 + 2 * i) << 8) | (value & 255)]
    out += [0x070000 | (i << 10) | v for i, v in enumerate(data["rxatt"])]
    return out


def main():
    current, previous = extract(BOOK, check_e_column=True), extract(OLD)
    print("BOOK_SHA256", hashlib.sha256(BOOK.read_bytes()).hexdigest())
    for key in current:
        changes = [(i, a, b) for i, (a, b) in enumerate(zip(previous[key], current[key])) if a != b]
        print("OLD_NEW", key, "count", len(changes), "changes", changes[:16])
    old_e, new_e = control_e_values(OLD), control_e_values(BOOK)
    e_changes = [(i, f"{a:02X}", f"{b:02X}")
                 for i, (a, b) in enumerate(zip(old_e, new_e)) if a != b]
    print("OLD_NEW_CONTROL_E", len(e_changes), e_changes)
    generated = frames(current)
    expected = [int(line.strip(), 16) for line in ORACLE.read_text().splitlines() if line.strip()]
    assert len(generated) == len(expected) == 512
    differences = [(i, f"{a:06X}", f"{b:06X}") for i, (a, b) in enumerate(zip(expected, generated)) if a != b]
    print("RTL_ORACLE_FRAMES", len(expected), "DIFFERENCES", len(differences), differences[:32])
    rtl_text = RTL.read_text(encoding="utf-8")
    block_match = re.search(r"localparam logic \[1023:0\] CONTROL_DEFAULTS = \{(.*?)\};", rtl_text, re.S)
    assert block_match
    hex_chunks = re.findall(r"256'h([0-9A-Fa-f]{64})", block_match.group(1))
    assert len(hex_chunks) == 4
    rtl_controls = list(int("".join(hex_chunks), 16).to_bytes(128, "little"))
    rtl_changes = [(i, a, b) for i, (a, b) in enumerate(zip(rtl_controls, current["control"])) if a != b]
    print("RTL_CONTROL_DIFFERENCES", len(rtl_changes), rtl_changes[:16])
    for key in ("control", "txps", "rxps", "txatt", "rxatt"):
        print("EXAMPLES", key, [(i, f"{current[key][i]:X}") for i in (0, 1, 10, 31, 63)])
    for first in (96, 64, 32, 0):
        chunk = current["control"][first:first + 32]
        print("CONTROL_DEFAULTS_CHUNK", first, f"{int.from_bytes(bytes(chunk), 'little'):064X}")
    if "--apply" in sys.argv:
        raw = RTL.read_bytes()
        newline = b"\r\n" if b"\r\n" in raw else b"\n"
        pattern = rb"    localparam logic \[1023:0\] CONTROL_DEFAULTS = \{.*?    \};"
        chunks = [f"        256'h{int.from_bytes(bytes(current['control'][i:i+32]), 'little'):064X}".encode()
                  for i in (96, 64, 32, 0)]
        block = b"    localparam logic [1023:0] CONTROL_DEFAULTS = {" + newline
        block += (b"," + newline).join(chunks) + newline + b"    };"
        updated, count = re.subn(pattern, lambda _: block, raw, count=1, flags=re.S)
        assert count == 1, "CONTROL_DEFAULTS block not found"
        RTL.write_bytes(updated)
        ORACLE.write_text("".join(f"{frame:06X}\n" for frame in generated), encoding="ascii")
        print("APPLIED", RTL, ORACLE)


if __name__ == "__main__":
    main()
