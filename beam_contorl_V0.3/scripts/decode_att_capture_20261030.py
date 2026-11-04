"""Decode the four SDI lanes from a Vivado ILA CSV."""

import csv
import sys


with open(sys.argv[1], newline="") as handle:
    rows = list(csv.DictReader(handle))[1:]

frames = []
bits = [[] for _ in range(4)]
sdo_bits = []
sdo_fall_bits = []
old_csb = 1
old_clk = 0
start = 0
for row in rows:
    csb = int(row["rx_csb_o_OBUF[0:0]"], 16)
    clk = int(row["rx_clk_o_OBUF[0:0]"], 16)
    sdi = int(row["rx_sdi_o_OBUF[3:0]"], 16)
    sample = int(row["Sample in Buffer"])
    if old_csb == 1 and csb == 0:
        bits = [[] for _ in range(4)]
        sdo_bits = []
        sdo_fall_bits = []
        start = sample
    if csb == 0 and old_clk == 0 and clk == 1:
        for lane in range(4):
            bits[lane].append((sdi >> lane) & 1)
        sdo_bits.append(int(row["rx_sdo_i_IBUF[0:0]"], 16))
    if csb == 0 and old_clk == 1 and clk == 0:
        sdo_fall_bits.append(int(row["rx_sdo_i_IBUF[0:0]"], 16))
    if old_csb == 0 and csb == 1:
        words = [f"{int(''.join(map(str, lane_bits)), 2):06X}"
                 if lane_bits else "" for lane_bits in bits]
        sdo_word = (f"{int(''.join(map(str, sdo_bits)), 2):06X}"
                    if sdo_bits else "")
        sdo_fall_word = (f"{int(''.join(map(str, sdo_fall_bits)), 2):06X}"
                         if sdo_fall_bits else "")
        frames.append((start, sample, len(bits[0]), words, sdo_word,
                       len(sdo_fall_bits), sdo_fall_word))
    old_csb, old_clk = csb, clk

print("FRAMES", frames)
for name in ("core_error", "core_load_done", "core_write_done", "channel_start"):
    print(name, [int(row["Sample in Buffer"]) for row in rows if row[name] == "1"])
print("RX_GATE_HIGH_SAMPLES", sum(row["rx_r_o_OBUF[0:0]"] == "1" for row in rows))
print("LDB_LOW_SAMPLES", sum(row["rx_ldb_o_OBUF[0:0]"] == "0" for row in rows))

if len(sys.argv) > 2 and sys.argv[2] == "--sdo-offsets":
    edge_indices = [i for i in range(1, len(rows))
                    if rows[i]["rx_csb_o_OBUF[0:0]"] == "0"
                    and rows[i - 1]["rx_clk_o_OBUF[0:0]"] == "0"
                    and rows[i]["rx_clk_o_OBUF[0:0]"] == "1"]
    for offset in range(5):
        values = [int(rows[i + offset]["rx_sdo_i_IBUF[0:0]"], 16)
                  for i in edge_indices[-24:]]
        print("SDO_RISE_OFFSET", offset,
              f"{int(''.join(map(str, values)), 2):06X}")
    fall_indices = [i for i in range(1, len(rows))
                    if rows[i]["rx_csb_o_OBUF[0:0]"] == "0"
                    and rows[i - 1]["rx_clk_o_OBUF[0:0]"] == "1"
                    and rows[i]["rx_clk_o_OBUF[0:0]"] == "0"]
    for offset in range(5):
        values = [int(rows[i + offset]["rx_sdo_i_IBUF[0:0]"], 16)
                  for i in fall_indices[-23:]]
        print("SDO_FALL_OFFSET", offset,
              f"{int(''.join(map(str, values)), 2):06X}")
