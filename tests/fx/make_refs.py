# Makes the fx test's reference data (run from ~/Dev/reel:
# python3 -I tests/fx/make_refs.py).
#
# 1. EBU Tech 3341 true-peak cases 20-23: a 0.5 FS sine at fs/6 holding
#    one period of a 1.0 FS sine at fs/4, synthesised at 4·fs, low-passed
#    (windowed sinc, 20 kHz) and taken every 4th sample from offsets 0..3.
#    Written mono, 48 kHz, f32 little-endian, 0.1 s, to
#    tests/fx/fixtures/tp20.f32 … tp23.f32 (the test feeds them as stereo).
# 2. Noise programmes made from the same LCG the test uses (see
#    tests/fx/loudness.tsl: lcgProgramme), measured by ffmpeg's ebur128
#    filter as a black-box oracle; the answers go to
#    tests/fx/fixtures/ebur128.txt as "name I LRA TP" lines.
#
# Author: Alexius Academia
# Date: 2026-10-26

import math, struct, subprocess, os, re, sys

FS = 48000
here = os.path.dirname(os.path.abspath(__file__))
fix = os.path.join(here, 'fixtures')
scratch = os.path.join(here, '..', '..', 'build', 'scratch', 'fx')
os.makedirs(fix, exist_ok=True)
os.makedirs(scratch, exist_ok=True)

def i0(x):
    s = 1.0; t = 1.0; q = x * x / 4; k = 1
    while k < 60:
        t = t * q / (k * k); s += t; k += 1
    return s

def tp_case(offset):
    up = 4 * FS
    n = int(0.1 * up)
    x = []
    burst_at = n // 2
    # fs/6 sine at 4fs: 24 samples a period; start the burst at a rising
    # zero crossing, keep the phase continuous after it.
    burst_at -= burst_at % 24
    for i in range(n):
        if burst_at <= i < burst_at + 16:
            x.append(1.0 * math.sin(2 * math.pi * (i - burst_at) / 16))
        else:
            j = i if i < burst_at else i - 16
            x.append(0.5 * math.sin(2 * math.pi * j / 24))
    # fades (10 ms) at both ends
    fade = int(0.01 * up)
    for i in range(fade):
        g = i / fade
        x[i] *= g
        x[n - 1 - i] *= g
    # low-pass: 20 kHz windowed sinc at 4fs, 257 taps, Kaiser beta 8
    half = 128
    fc = 20000.0 / up
    h = []
    for k in range(-half, half + 1):
        s = 2 * fc if k == 0 else math.sin(2 * math.pi * fc * k) / (math.pi * k)
        w = i0(8 * math.sqrt(1 - (k / (half + 1)) ** 2)) / i0(8)
        h.append(s * w)
    sh = sum(h)
    h = [v / sh * 1.0 for v in h]
    out = []
    for m in range(offset, n, 4):
        acc = 0.0
        for k in range(-half, half + 1):
            j = m - k
            if 0 <= j < n:
                acc += h[k + half] * x[j]
        out.append(acc)
    return out

for case, off in ((20, 0), (21, 1), (22, 2), (23, 3)):
    y = tp_case(off)
    with open(os.path.join(fix, 'tp%d.f32' % case), 'wb') as f:
        f.write(struct.pack('<%df' % len(y), *y))

# LCG noise programmes, exactly as the test makes them.
def lcg_programme(channels, levels, seed):
    x = seed
    data = []
    for lv in levels:
        amp = 10 ** (lv / 20.0)
        for _ in range(FS):
            for _c in range(channels):
                x = (1103515245 * x + 12345) % 2147483648
                data.append((x / 1073741824.0 - 1.0) * amp)
    return data

programmes = [
    ('stereo', 2, '', [-20, -26, -14, -30, -18, -22, -10, -40, -24, -16, -28, -20], 7),
    ('surround', 6, '5.1', [-24, -18, -30, -20, -26, -22], 11),
]
lines = []
for name, ch, layout, levels, seed in programmes:
    d = lcg_programme(ch, levels, seed)
    path = os.path.join(scratch, name + '.f32')
    with open(path, 'wb') as f:
        f.write(struct.pack('<%df' % len(d), *d))
    cmd = ['ffmpeg', '-hide_banner', '-nostats', '-f', 'f32le', '-ar', str(FS), '-ac', str(ch)]
    if layout:
        cmd += ['-channel_layout', layout]
    cmd += ['-i', path, '-af', 'ebur128=peak=true+sample:framelog=quiet', '-f', 'null', '-']
    r = subprocess.run(cmd, capture_output=True, text=True)
    txt = r.stderr
    summ = txt[txt.rfind('Summary:'):]
    i = float(re.search(r'I:\s+(-?[\d.]+) LUFS', summ).group(1))
    lra = float(re.search(r'LRA:\s+(-?[\d.]+) LU', summ).group(1))
    tp = float(re.search(r'True peak:\s+Peak:\s+(-?[\d.]+) dBFS', summ, re.S).group(1))
    sp = float(re.search(r'Sample peak:\s+Peak:\s+(-?[\d.]+) dBFS', summ, re.S).group(1))
    lines.append('%s %.2f %.2f %.2f %.2f' % (name, i, lra, tp, sp))
with open(os.path.join(fix, 'ebur128.txt'), 'w') as f:
    f.write('# name integrated(LUFS) LRA(LU) truePeak(dBTP) samplePeak(dBFS), by ffmpeg ebur128\n')
    f.write('\n'.join(lines) + '\n')
print('\n'.join(lines))
