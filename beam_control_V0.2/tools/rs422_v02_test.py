#!/usr/bin/env python3
"""Build and optionally transmit one beam-control protocol V0.2 command."""

from __future__ import annotations

import argparse
import sys
import time


def ranged_int(name: str, lower: int, upper: int):
    def parse(value: str) -> int:
        number = int(value, 0)
        if not lower <= number <= upper:
            raise argparse.ArgumentTypeError(
                f"{name} must be in the range {lower}..{upper}"
            )
        return number

    return parse


def build_frame(
    array: int,
    line: int,
    chip: int,
    channel: int,
    enable: int,
    phase: int,
    attenuation: int,
) -> bytes:
    payload = [array, line, chip, channel, enable, phase, attenuation]
    checksum = sum(payload) & 0xFF
    return bytes([0xAA, *payload, checksum, 0x55])


def frame_text(frame: bytes) -> str:
    return " ".join(f"{byte:02X}" for byte in frame)


def list_ports() -> int:
    try:
        from serial.tools import list_ports as serial_list_ports
    except ImportError:
        print("pyserial is required: python -m pip install pyserial", file=sys.stderr)
        return 2

    ports = list(serial_list_ports.comports())
    if not ports:
        print("No serial ports found")
    for port in ports:
        print(f"{port.device}: {port.description}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Send a 10-byte protocol V0.2 frame through a USB-RS422 adapter"
    )
    parser.add_argument("--list-ports", action="store_true")
    parser.add_argument("--port", help="Windows COM port, for example COM5")
    parser.add_argument("--array", choices=("rx", "tx"), default="rx")
    parser.add_argument("--line", type=ranged_int("line", 0, 7), default=0)
    parser.add_argument("--chip", type=ranged_int("chip", 0, 3), default=0)
    parser.add_argument("--channel", type=ranged_int("channel", 0, 3), default=0)
    parser.add_argument("--enable", type=ranged_int("enable", 0, 1), default=1)
    parser.add_argument("--phase", type=ranged_int("phase", 0, 63), default=0)
    parser.add_argument("--att", type=ranged_int("attenuation", 0, 63), default=0)
    parser.add_argument("--repeat", type=ranged_int("repeat", 1, 100000), default=1)
    parser.add_argument("--interval", type=float, default=0.1, help="seconds between frames")
    parser.add_argument(
        "--dry-run", action="store_true", help="print bytes without opening a COM port"
    )
    args = parser.parse_args()

    if args.list_ports:
        return list_ports()
    if args.interval < 0:
        parser.error("--interval must be non-negative")
    if args.att > 31:
        print(
            "WARNING: attenuation codes 32..63 are accepted by RTL but are not "
            "confirmed by the current chip table",
            file=sys.stderr,
        )

    frame = build_frame(
        0 if args.array == "rx" else 1,
        args.line,
        args.chip,
        args.channel,
        args.enable,
        args.phase,
        args.att,
    )
    print(f"TX ({len(frame)} bytes): {frame_text(frame)}")

    if args.dry_run or not args.port:
        if not args.port and not args.dry_run:
            print("No --port supplied; dry-run only")
        return 0

    try:
        import serial
    except ImportError:
        print("pyserial is required: python -m pip install pyserial", file=sys.stderr)
        return 2

    # V0.2 is receive-only at the board: no ACK is expected on RS422 TX.
    with serial.Serial(
        port=args.port,
        baudrate=115200,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.1,
        write_timeout=1.0,
    ) as port:
        for index in range(args.repeat):
            port.write(frame)
            port.flush()
            print(f"sent {index + 1}/{args.repeat}")
            if index + 1 < args.repeat:
                time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
