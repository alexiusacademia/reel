# Writes MPEG audio layer I and layer II test streams that no encoder on
# hand makes (there is no layer I encoder here, and ffmpeg's mp2 encoder
# never uses joint stereo): syntactically valid frames with pseudo-random
# bit allocations, scale factors and samples, in every channel mode,
# joint-stereo bound, MPEG-1 and MPEG-2 LSF rate and with or without the
# CRC word. ffmpeg decodes them to make the reference samples; the content
# is noise-like, which exercises every quantizer class.
#
#   python3 -I gen_layer12.py <layer 1|2> <rate> <mode 0-3> <modeext 0-3>
#                             <kbps> <frames> <crc 0|1> <seed> <out>
#
# The allocation tables are read from mpa/tables.tsl; ffmpeg's decoding of
# the result is the independent check that they (and the decoder) are right.
#
# Author: Alexius Academia
# Date: 2026-10-25
import random, re, sys, os

layer, rate, mode, modeext, kbps, nframes, crc, seed = (int(a) for a in sys.argv[1:9])
out = sys.argv[9]
rnd = random.Random(seed)
here = os.path.dirname(os.path.abspath(__file__))
tables = open(os.path.join(here, "..", "..", "mpa", "tables.tsl")).read()


def table(name):
    m = re.search(r"let " + name + r" = \[(.*?)\]", tables, re.S)
    return [int(x) for x in re.split(r"[\s,]+", re.sub(r"//[^\n]*", "", m.group(1))) if x]


alloc_tabs = {1: table("mpaAlloc1"), 3: table("mpaAlloc3"), 4: table("mpaAlloc4")}
sblimits = table("mpaSblimit")
qbits = table("mpaQuantBits")
qsteps = table("mpaQuantSteps")
brates = {
    (False, 1): [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    (False, 2): [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    (True, 1): [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
    (True, 2): [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
}
lsf = rate < 32000
base_rates = [44100, 48000, 32000]
rate_index = [r >> (1 if lsf else 0) for r in base_rates].index(rate)
bitrate_index = brates[(lsf, layer)].index(kbps)
nch = 1 if mode == 3 else 2


class Bits:
    def __init__(self):
        self.bits = []

    def put(self, v, n):
        for i in range(n - 1, -1, -1):
            self.bits.append((v >> i) & 1)

    def bytes(self, size):
        assert len(self.bits) <= size * 8, (len(self.bits), size * 8)
        b = self.bits + [0] * (size * 8 - len(self.bits))
        return bytes(int("".join(map(str, b[i:i + 8])), 2) for i in range(0, len(b), 8))


def l2_table():
    if lsf:
        return 4
    per = kbps // nch
    if (rate == 48000 and per >= 56) or (56 <= per <= 80):
        return 0
    if rate != 48000 and per >= 96:
        return 1
    if rate != 32000 and per <= 48:
        return 2
    return 3


def layer1_frame(w, budget):
    bound = (modeext + 1) * 4 if mode == 1 else 32
    alloc = [[0] * 32 for _ in range(2)]

    def cost():
        c = 4 * (bound * nch + (32 - bound))
        for i in range(32):
            for ch in range(nch if i < bound else 1):
                n = alloc[ch][i]
                if n:
                    c += 6 * (2 if i >= bound else 1) + 12 * (n + 1)
        return c

    for _ in range(400):
        i = rnd.randrange(32)
        ch = rnd.randrange(nch if i < bound else 1)
        old = alloc[ch][i]
        alloc[ch][i] = rnd.randrange(1, 15)
        if cost() > budget * 0.95:
            alloc[ch][i] = old
    for i in range(bound, 32):
        alloc[1][i] = alloc[0][i]
    for i in range(bound):
        for ch in range(nch):
            w.put(alloc[ch][i], 4)
    for i in range(bound, 32):
        w.put(alloc[0][i], 4)
    for i in range(32):
        for ch in range(nch):
            if alloc[ch][i]:
                w.put(rnd.randrange(8, 50), 6)
    for _ in range(12):
        for i in range(bound):
            for ch in range(nch):
                n = alloc[ch][i]
                if n:
                    w.put(rnd.randrange((1 << (n + 1)) - 1), n + 1)
        for i in range(bound, 32):
            n = alloc[0][i]
            if n:
                w.put(rnd.randrange((1 << (n + 1)) - 1), n + 1)


def layer2_frame(w, budget):
    t = l2_table()
    tab = alloc_tabs[{0: 1, 1: 1, 2: 3, 3: 3, 4: 4}[t]]
    sblimit = sblimits[t]
    bound = min((modeext + 1) * 4 if mode == 1 else sblimit, sblimit)
    starts = []
    j = 0
    for i in range(sblimit):
        starts.append(j)
        j += 1 << tab[j]
    alloc = [[0] * 32 for _ in range(2)]
    scfsi = [[rnd.randrange(4) for _ in range(32)] for _ in range(2)]

    def cost():
        c = 0
        for i in range(sblimit):
            c += tab[starts[i]] * (nch if i < bound else 1)
            for ch in range(nch):
                if alloc[ch][i]:
                    c += 2 + 6 * {0: 3, 1: 2, 2: 1, 3: 2}[scfsi[ch][i]]
            for ch in range(nch if i < bound else 1):
                b = alloc[ch][i]
                if b:
                    bits = qbits[tab[starts[i] + b]]
                    c += 12 * (-bits if bits < 0 else 3 * bits)
        return c

    for _ in range(600):
        i = rnd.randrange(sblimit)
        ch = rnd.randrange(nch if i < bound else 1)
        old = alloc[ch][i]
        alloc[ch][i] = rnd.randrange(1, 1 << tab[starts[i]])
        if i >= bound:
            alloc[1][i] = alloc[0][i]
        if cost() > budget * 0.95:
            alloc[ch][i] = old
            if i >= bound:
                alloc[1][i] = old
    for i in range(sblimit):
        bits = tab[starts[i]]
        if i < bound:
            for ch in range(nch):
                w.put(alloc[ch][i], bits)
        else:
            w.put(alloc[0][i], bits)
    for i in range(sblimit):
        for ch in range(nch):
            if alloc[ch][i]:
                w.put(scfsi[ch][i], 2)
    for i in range(sblimit):
        for ch in range(nch):
            if alloc[ch][i]:
                for _ in range({0: 3, 1: 2, 2: 1, 3: 2}[scfsi[ch][i]]):
                    w.put(rnd.randrange(6, 50), 6)
    for _ in range(12):
        for i in range(sblimit):
            for ch in range(nch if i < bound else 1):
                b = alloc[ch][i]
                if b:
                    q = tab[starts[i] + b]
                    bits = qbits[q]
                    steps = qsteps[q]
                    if bits < 0:
                        v = rnd.randrange(steps) + steps * (rnd.randrange(steps) + steps * rnd.randrange(steps))
                        w.put(v, -bits)
                    else:
                        for _ in range(3):
                            w.put(rnd.randrange((1 << bits) - 1), bits)


with open(out, "wb") as fh:
    for f in range(nframes):
        if layer == 1:
            size = (kbps * 12000 // rate) * 4
        else:
            size = kbps * 144000 // rate
        w = Bits()
        w.put(0xFFF, 12)
        w.put(0 if lsf else 1, 1)
        w.put(4 - layer, 2)
        w.put(0 if crc else 1, 1)
        w.put(bitrate_index, 4)
        w.put(rate_index, 2)
        w.put(0, 1)  # padding
        w.put(0, 1)  # private
        w.put(mode, 2)
        w.put(modeext, 2)
        w.put(0, 4)  # copyright, original, emphasis
        if crc:
            w.put(rnd.randrange(65536), 16)  # not checked by the decoders compared
        budget = size * 8 - len(w.bits)
        if layer == 1:
            layer1_frame(w, budget)
        else:
            layer2_frame(w, budget)
        fh.write(w.bytes(size))
