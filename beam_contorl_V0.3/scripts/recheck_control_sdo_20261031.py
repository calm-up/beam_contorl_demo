"""Re-evaluate all saved J1 control-register ILA captures at RTL sample timing."""

import csv
from pathlib import Path

from verify_sdo_read_capture_20261031 import verify_capture


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "output" / "s50"
SOURCE_DIRS = (BASE / "sweep_20261031", BASE / "resume_after_power_20261031")
OUTPUT = BASE / "rechecked_all_control_20261031.csv"


def main() -> None:
    records: dict[tuple[int, int], tuple[bool, str, Path]] = {}
    for source in SOURCE_DIRS:
        with (source / "summary.csv").open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                chip = int(row["chip"])
                address = int(row["address"])
                if source == SOURCE_DIRS[0] and address >= 25:
                    continue  # The first sweep lost SDO at address 25.
                capture = source / f"chip{chip}_addr{address:03d}.csv"
                passed, detail = verify_capture(capture, chip, address,
                                                int(row["expected"], 16))
                key = (chip, address)
                if key in records:
                    raise RuntimeError(f"Duplicate capture {key}")
                records[key] = passed, detail, capture

    expected_keys = {(chip, address) for chip in range(4) for address in range(128)}
    if set(records) != expected_keys:
        raise RuntimeError(f"Missing {sorted(expected_keys - set(records))[:10]}; "
                           f"extra {sorted(set(records) - expected_keys)[:10]}")
    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("chip", "address", "status", "detail", "capture"))
        for chip, address in sorted(records):
            passed, detail, capture = records[chip, address]
            writer.writerow((chip, address, "PASS" if passed else "FAIL",
                             detail, str(capture)))
    failures = [(chip, address, detail) for (chip, address), (passed, detail, _)
                in sorted(records.items()) if not passed]
    print(f"TOTAL={len(records)} PASS={len(records)-len(failures)} "
          f"FAIL={len(failures)} OUTPUT={OUTPUT}")
    for failure in failures:
        print("FAILURE", failure)
    if failures:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
