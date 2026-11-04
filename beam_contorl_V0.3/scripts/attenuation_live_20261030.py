"""Send J1 attenuation test commands over COM5."""

import argparse
import time

import serial


def frame(cmd: int, payload: list[int], array: int = 0) -> bytes:
    body = bytes([1, 8 + len(payload), cmd, array, *payload])
    return bytes([0xAA, 0xDD]) + body + bytes([sum(body) & 0xFF, 0x55])


def read_frame(port: serial.Serial, timeout_s: float = 20) -> bytes:
    deadline = time.monotonic() + timeout_s
    data = bytearray()
    while time.monotonic() < deadline:
        data.extend(port.read(port.in_waiting or 1))
        start = data.find(b"\xAA\xDD")
        if start < 0:
            data.clear()
            continue
        if start:
            del data[:start]
        if len(data) >= 4 and len(data) >= data[3]:
            result = bytes(data[: data[3]])
            if result[-1] != 0x55 or sum(result[2:-2]) & 0xFF != result[-2]:
                raise RuntimeError(f"Invalid response frame: {result.hex(' ').upper()}")
            return result
    raise TimeoutError(f"No complete response: {data.hex(' ').upper()}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("step", choices=("status", "reset", "att0", "att31", "off",
                                         "group0", "group31", "groupoff", "set", "read"))
    parser.add_argument("--port", default="COM5")
    parser.add_argument("--no-ack", action="store_true", help="TX path unavailable; verify action with ILA")
    parser.add_argument("--channel", type=int, choices=range(4), default=0)
    parser.add_argument("--chip", type=int, choices=range(4), default=3)
    parser.add_argument("--att", type=int, choices=range(64), default=0)
    parser.add_argument("--disable", action="store_true")
    parser.add_argument("--function", type=int, choices=(1, 2, 4, 5, 6, 7), default=4)
    parser.add_argument("--address", type=int, choices=range(256), default=0)
    args = parser.parse_args()

    def one_channel(channel: int, attenuation: int, enabled: bool,
                    pulse: int | None = None) -> bytes:
        # line, chip, RF index, enable, TX phase, RX phase, TX attenuation,
        # RX attenuation, serial attenuation, parallel attenuation, pulse,
        # STC, window, frequency high, frequency low.
        payload = [0, args.chip, channel, int(enabled), 0, 0, 0, attenuation,
                   0, 0, 2 if pulse is None and enabled else
                   0 if pulse is None else pulse, 0, 0, 0, 0]
        return frame(0x40, payload)

    if args.step == "status":
        requests = [(0xE0, frame(0xE0, []))]
    elif args.step == "reset":
        requests = [(0x00, frame(0x00, [1, 0]))]
    elif args.step == "read":
        requests = [(0x41, frame(0x41, [0, args.chip, args.function, args.address]))]
    elif args.step.startswith("group"):
        enabled = args.step != "groupoff"
        attenuation = 31 if args.step == "group31" else 0
        requests = [(0x40, one_channel(channel, attenuation, enabled))
                    for channel in range(4)]
    elif args.step == "set":
        requests = [(0x40, one_channel(args.channel, args.att,
                                       not args.disable, pulse=2))]
    else:
        enabled = args.step != "off"
        attenuation = 31 if args.step == "att31" else 0
        requests = [(0x40, one_channel(0, attenuation, enabled))]

    with serial.Serial(args.port, 115200, timeout=0.2, write_timeout=2) as port:
        port.reset_input_buffer()
        for index, (cmd, request) in enumerate(requests):
            print(f"STEP={args.step} INDEX={index} TX={request.hex(' ').upper()}", flush=True)
            port.write(request)
            port.flush()
            if args.no_ack:
                time.sleep(0.25)
                print("RX=UNAVAILABLE; command execution requires ILA verification", flush=True)
                continue
            response = read_frame(port)
            print(f"RX={response.hex(' ').upper()}", flush=True)
            if response[4] != 0x7F or response[6] != cmd or response[7] != 0:
                raise RuntimeError("Command did not return success")


if __name__ == "__main__":
    main()
