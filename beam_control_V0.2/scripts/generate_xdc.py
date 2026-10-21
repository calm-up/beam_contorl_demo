"""Generate the step-3 XDC from the reviewed pin matrix."""
from pathlib import Path
import csv

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "beam_control"
MATRIX = ROOT / "hardware_review" / "revision_final" / "pin_mapping.csv"
OUT = PROJECT / "constr" / "beam_ctrl.xdc"

with MATRIX.open(encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

assert len(rows) == 176
assert len({row["port"] for row in rows}) == 176
assert len({row["fpga_pin"] for row in rows}) == 176
assert {row["iostandard"] for row in rows} == {"LVCMOS33"}

# Reviewed external communication pins. Directions are from the FPGA/board
# viewpoint; the differential conversion is performed by U6/U7/U21.
comm_rows = [
    ("rs422_rx_i",        "C2", "J18 upstream RS422 receive via U6/MAX3490"),
    ("rs422_tx_o",        "D2", "J18 upstream RS422 transmit via U6/MAX3490"),
    ("debug_rs485_rx_i",  "B17", "J21 debug RS485 receive via U7/MAX3485"),
    ("debug_rs485_tx_o",  "B15", "J21 debug RS485 transmit via U7/MAX3485"),
    ("debug_rs485_dir_o", "B16", "J21 debug RS485 direction: 0=RX, 1=TX"),
    ("spare_rs485_rx_i",  "L6", "J18 spare RS485 receive via U21/MAX3485"),
    ("spare_rs485_tx_o",  "J6", "J18 spare RS485 transmit via U21/MAX3485"),
    ("spare_rs485_dir_o", "K6", "J18 spare RS485 direction: 0=RX, 1=TX"),
]
assert len({port for port, _, _ in comm_rows}) == len(comm_rows)
assert len({pin for _, pin, _ in comm_rows}) == len(comm_rows)
assert not ({pin for _, pin, _ in comm_rows} & {row["fpga_pin"] for row in rows})

lines = [
    "# Generated from hardware_review/revision_final/pin_mapping.csv.",
    "# Board-source evidence only; see the revision_final hardware report before use.",
    "# DRIVE/SLEW and external I/O delays remain open until loads/timing are confirmed.",
    "",
    "# U4.U8/CFGBVS is tied to DVCC3V3 and bank 0 VCCO is DVCC3V3.",
    "set_property CFGBVS VCCO [current_design]",
    "set_property CONFIG_VOLTAGE 3.3 [current_design]",
    "",
    "# 50 MHz oscillator: Y1.3 -> R10 (22 ohm) -> GCLK -> U4.V20",
    "set_property PACKAGE_PIN V20 [get_ports {sys_clk_i}]",
    "set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk_i}]",
    "create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk_i}]",
    "# Temporary board-validation route: V20 is the N side and has no direct",
    "# single-ended clock path. Only IBUF-to-BUFG is allowed to use fabric routing.",
    "set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sys_clk_i_IBUF]",
    "",
]

last = None
for row in rows:
    group = (row["array"], row["line_label"])
    if group != last:
        lines.extend(["", f'# {row["array"]} line {row["line_label"]}: {row["connector"]}'])
        last = group
    port = row["port"]
    lines.append(f'set_property PACKAGE_PIN {row["fpga_pin"]} [get_ports {{{port}}}]')
    lines.append(f'set_property IOSTANDARD {row["iostandard"]} [get_ports {{{port}}}]')

lines.extend(["", "# External communication interfaces; differential pairs terminate at board transceivers."])
for port, pin, note in comm_rows:
    lines.append(f"# {note}")
    lines.append(f"set_property PACKAGE_PIN {pin} [get_ports {{{port}}}]")
    lines.append(f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]")

lines.extend([
    "",
    "# JTAG uses dedicated configuration pins and therefore has no RTL/XDC remap.",
    "# No external user reset pin was found; reset policy is implemented in RTL later.",
    "# U4.U22/rx_sdi_o[17] is also PUDC_B. Resolve its pre-configuration bias before board use.",
])
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {OUT} with {len(rows) + len(comm_rows) + 1} user I/O constraints")
