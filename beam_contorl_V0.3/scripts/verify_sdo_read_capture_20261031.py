"""Check one J1 control-register read from an array-ILA CSV capture."""

import argparse
import csv
from pathlib import Path


def verify_capture(capture: Path, chip: int, address: int,
                   expected_data: int, final_sample: str = "after") -> tuple[bool, str]:
    with capture.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))[1:]  # Skip Vivado's radix row.

    def field(row: dict[str, str], name: str) -> int:
        return int(row[name], 16)

    frames: list[tuple[list[int], list[int], int]] = []
    old_csb = 1
    old_clk = 0
    sdi_bits: list[list[int]] = [[] for _ in range(4)]
    sdo_bits: list[int] = []
    for index, row in enumerate(rows):
        csb = field(row, "rx_csb_o_OBUF[0:0]")
        clk = field(row, "rx_clk_o_OBUF[0:0]")
        sdi = field(row, "rx_sdi_o_OBUF[3:0]")
        sdo = field(row, "rx_sdo_i_IBUF[0:0]")
        if old_csb and not csb:
            sdi_bits = [[] for _ in range(4)]
            sdo_bits = []
        if not csb and not old_clk and clk:
            for lane in range(4):
                sdi_bits[lane].append((sdi >> lane) & 1)
            sdo_bits.append(sdo)
        if not old_csb and csb:
            sample_index = index - 1 if final_sample == "before" else index + 1
            if sample_index < 0 or sample_index >= len(rows):
                raise SystemExit("INVALID_CAPTURE no final SDO sample")
            final_sdo = field(rows[sample_index], "rx_sdo_i_IBUF[0:0]")
            frames.append(([int("".join(map(str, bits)), 2) for bits in sdi_bits]
                           if all(bits for bits in sdi_bits) else [],
                           sdo_bits[:], final_sdo))
        old_csb, old_clk = csb, clk

    if len(frames) != 2 or any(len(bits) != 24 for _, bits, _ in frames):
        raise SystemExit(f"INVALID_CAPTURE frames={len(frames)} bit_counts={[len(x[1]) for x in frames]}")
    cid = chip
    expected_sdi = [0xF80000] * 4
    expected_sdi[chip] = (cid << 20) | 0x0C0000 | (address << 8)
    dummy_sdi = [0xF80000] * 4
    dummy_sdi[chip] = (cid << 20) | 0x080000
    if frames[0][0] != expected_sdi or frames[1][0] != dummy_sdi:
        raise SystemExit(f"INVALID_SDI got={[f[0] for f in frames]} expected={[expected_sdi, dummy_sdi]}")

    raw = int("".join(map(str, frames[1][1])), 2)
    observed = ((raw << 1) & 0xFFFFFF) | frames[1][2]
    expected = (cid << 20) | 0x0C0000 | (address << 8) | expected_data
    result = "PASS" if observed == expected else "FAIL"
    return result == "PASS", (f"{result} chip={cid} addr={address:03d} "
                              f"expected={expected:06X} raw={raw:06X} "
                              f"reconstructed={observed:06X}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("chip", type=int, choices=range(4))
    parser.add_argument("address", type=int, choices=range(128))
    parser.add_argument("expected", type=lambda value: int(value, 16))
    parser.add_argument("--final-sample", choices=("before", "after"), default="after")
    args = parser.parse_args()
    passed, result = verify_capture(args.capture, args.chip, args.address,
                                    args.expected, args.final_sample)
    print(result)
    if not passed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
