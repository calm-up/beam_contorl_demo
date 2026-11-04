"""Export independent expected register values from the updated workbook."""
import csv
import hashlib
from pathlib import Path
from compare_10405w_20261028 import BOOK, extract

data = extract(BOOK, check_e_column=True)
out = Path(__file__).resolve().parents[1] / "output" / "register_baseline_20261031.csv"
with out.open("w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["chip", "table", "function", "address", "expected", "bits"])
    for chip in range(4):
        for address, value in enumerate(data["control"]):
            w.writerow([chip, "Control_Reg", 4, address, f"{value:02X}", 8])
        for table, base in (("txps", 0), ("rxps", 128)):
            for k, value in enumerate(data[table]):
                w.writerow([chip, table.upper(), 5, base + 2*k, f"{value >> 8:02X}", 8])
                w.writerow([chip, table.upper(), 5, base + 2*k + 1, f"{value & 255:02X}", 8])
        for table, function in (("txatt", 6), ("rxatt", 7)):
            for address, value in enumerate(data[table]):
                w.writerow([chip, table.upper(), function, address, f"{value:03X}", 10])
print("WORKBOOK_SHA256", hashlib.sha256(BOOK.read_bytes()).hexdigest())
print("BASELINE", out, "ROWS", 4 * 512)
