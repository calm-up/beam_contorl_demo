"""Keep COM5 reserved while an ILA sweep sends read requests."""

import sys

import serial

from attenuation_live_20261030 import frame


with serial.Serial("COM5", 115200, timeout=0.2, write_timeout=2) as port:
    port.reset_input_buffer()
    print("READY", flush=True)
    for line in sys.stdin:
        parts = line.split()
        if len(parts) == 2:
            chip, address = map(int, parts)
            if chip not in range(4) or address not in range(128):
                raise ValueError(f"Invalid read target: {line.rstrip()}")
            request = frame(0x41, [0, chip, 4, address])
            acknowledgement = f"SENT {chip} {address}"
        elif len(parts) == 4 and parts[0] == "READ":
            chip, function, address = map(int, parts[1:])
            valid_address = (function in (1, 2) and address in range(4) or
                             function in (4, 5) and address in range(256) or
                             function in (6, 7) and address in range(64))
            if chip not in range(4) or not valid_address:
                raise ValueError(f"Invalid read target: {line.rstrip()}")
            request = frame(0x41, [0, chip, function, address])
            acknowledgement = f"SENT READ {chip} {function} {address}"
        elif len(parts) == 4 and parts[0] == "SET":
            chip, channel, attenuation = map(int, parts[1:])
            if chip not in range(4) or channel not in range(4) or attenuation not in range(64):
                raise ValueError(f"Invalid attenuation target: {line.rstrip()}")
            payload = [0, chip, channel, 1, 0, 0, 0, attenuation,
                       0, 0, 2, 0, 0, 0, 0]
            request = frame(0x40, payload)
            acknowledgement = f"SENT SET {chip} {channel} {attenuation}"
        elif len(parts) == 3 and parts[0] == "WRITE":
            chip, value = int(parts[1]), int(parts[2], 16)
            if chip not in range(4) or value >> 20 != chip or value & 0x80000:
                raise ValueError('Invalid diagnostic write')
            request = frame(0x42, [0, chip, value >> 16, (value >> 8) & 255, value & 255])
            acknowledgement = 'SENT ' + line.strip()
        elif len(parts) == 1 and parts[0] == "LOAD":
            request = frame(0x43, [0])
            acknowledgement = "SENT LOAD"
        elif len(parts) == 1 and parts[0] == "RESET":
            request = frame(0x00, [1, 0])
            acknowledgement = "SENT RESET"
        else:
            raise ValueError(f"Invalid command: {line.rstrip()}")
        port.write(request)
        port.flush()
        print(acknowledgement, flush=True)
