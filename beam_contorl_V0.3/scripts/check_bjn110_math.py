"""Build independent math vectors for the preserved BJN110 calculation sources.

Uses only the Python standard library. COE is original data, never regenerated
from the golden formula. The RTL is compiled unchanged by run_bjn110_math.ps1.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import random
import re

ROOT = Path(__file__).resolve().parents[1]


def coe(name):
    text = (ROOT / 'reference/bjn110_cal_phase/coe' / name).read_text()
    radix = int(re.search(r'RADIX\s*=\s*(\d+)', text, re.I)[1])
    body = re.split(r'VECTOR\s*=', text, flags=re.I)[1].split(';')[0]
    return [int(v.strip(), radix) for v in body.split(',') if v.strip()]


def trunc_div(n, d):
    return (abs(n) // d) * (-1 if n < 0 else 1)


def phase_float(f, fw, fy, x, y):
    # Algebraic independent reference, using source scale/coordinate convention.
    a, b = math.radians(fw / 100), math.radians(fy / 100)
    return f * 167 / 9375 * (-x * math.sin(a) * math.cos(b) + y * math.sin(b))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    tri, fs, js = coe('tri_data.coe'), coe('fuxing_fs.coe'), coe('fuxing_js.coe')
    assert len(tri) >= 9001 and len(fs) == len(js) == 32
    errors = [abs(tri[a] - math.sin(math.radians(a / 100)) * 2**20)
              for a in range(9001)]
    assert max(errors) <= 1, 'Original trig ROM differs from sine by >1 LSB'
    for name, values, width in [('tri', tri, 6), ('fs', fs, 48), ('js', js, 48)]:
        (out / (name + '.mem')).write_text(''.join(f'{v:0{width}x}\n' for v in values))

    # All valid 0.01-degree inputs: RTL trig module compared to independent math.
    trig_lines = []
    for fw in range(-9000, 9001):
        fy = -fw
        values = [round(math.sin(math.radians(fw / 100)) * 2**20),
                  round(math.cos(math.radians(fw / 100)) * 2**20),
                  round(math.sin(math.radians(fy / 100)) * 2**20),
                  round(math.cos(math.radians(fy / 100)) * 2**20)]
        trig_lines.append(' '.join(map(str, [fw, fy, *values])) + '\n')
    (out / 'trig_vectors.txt').write_text(''.join(trig_lines))

    angles = [(0, 0), (1000, 0), (-1000, 0), (0, 1000), (0, -1000),
              (3000, 1500), (-3000, 1500), (3000, -1500), (-3000, -1500),
              (9000, 0), (-9000, 0), (0, 9000), (0, -9000), (8999, -8999),
              (1, -1)]
    cases = [(f, a, b, w) for f in (890, 980, 1070, 1650)
             for a, b in angles for w in (0, 1)]
    rng = random.Random(110)
    cases += [(rng.randint(800, 1800), rng.randint(-9000, 9000),
               rng.randint(-9000, 9000), rng.randrange(2)) for _ in range(64)]
    expected_rx, expected_tx, case_lines = [], [], []
    float_mismatches, max_circular = 0, 0
    differences = []
    for f, fw, fy, wave in cases:
        # Deliberately distinct unused TX inputs: test original shared RX behavior.
        case_lines.append(f'{f} {fw} {fy} {-fw} {-fy} {wave}\n')
        sfw = tri[abs(fw)] * (-1 if fw < 0 else 1)
        sfy = tri[abs(fy)] * (-1 if fy < 0 else 1)
        cfy = tri[9000 - abs(fy)]
        left = trunc_div(sfw * cfy * 167 * f, 9375)
        right = trunc_div(sfy * 2**20 * 167 * f, 9375)
        for row in range(32):
            rx, tx = 0, 0
            for col in range(32):
                x, y = 2 * row - 31, 2 * col - 31
                code = ((-left * x + right * y + 2**39) // 2**40) % 64
                ideal = math.floor(phase_float(f, fw, fy, x, y) + 0.5) % 64
                distance = min((code-ideal) % 64, (ideal-code) % 64)
                float_mismatches += distance != 0
                max_circular = max(max_circular, distance)
                if distance:
                    differences.append(dict(frequency=f, azimuth=fw, elevation=fy,
                                            row=row, column=col, fixed=code, ideal=ideal))
                rx_weight = (js[row] >> (6*col)) & 63 if wave else 0
                tx_weight = (fs[row] >> (6*col)) & 63 if wave else 0
                rx |= ((code + rx_weight) % 64) << (6*col)
                tx |= ((code + tx_weight) % 64) << (6*col)
            expected_rx.append(f'{rx:048x}\n')
            expected_tx.append(f'{tx:048x}\n')
    (out / 'cases.txt').write_text(''.join(case_lines))
    (out / 'expected_rx.mem').write_text(''.join(expected_rx))
    (out / 'expected_tx.mem').write_text(''.join(expected_tx))
    result = dict(cases=len(cases), groups_per_case=32, channels_per_group=32,
                  phase_values_per_direction=len(cases)*1024,
                  trig_cases=len(trig_lines), trig_rom_entries=len(tri),
                  trig_rom_max_error_lsb=max(errors),
                  fixed_vs_float_different_codes=float_mismatches,
                  fixed_vs_float_max_circular_code_error=max_circular,
                  fixed_vs_float_examples=differences,
                  source_parameters=dict(X_DIS=167, Y_DIS=167, GROUP=32),
                  note='Reference convention only; not an assertion of current array geometry.')
    (out / 'math_reference_summary.json').write_text(json.dumps(result, indent=2))
    files=list((ROOT/'reference/bjn110_cal_phase').glob('*.v')) + list((ROOT/'reference/bjn110_cal_phase/coe').glob('*.coe'))
    (out/'source_hashes.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
