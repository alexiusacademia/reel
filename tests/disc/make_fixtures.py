#!/usr/bin/env python3
# Makes the disc test fixtures in tests/disc/fixtures/:
#   dvd/VIDEO_TS/     a small DVD-Video folder: VIDEO_TS.IFO/.BUP, two title
#                     sets (VTS_01: titles 1 and 2 over two VOB files; VTS_02:
#                     title 3 with two program chains and a 2-angle block)
#   bluray/BDMV/      a small Blu-ray folder: index.bdmv, MovieObject.bdmv,
#                     playlists (main, a duplicate, a trailer, decoys, a
#                     multi-angle one), clip infos with EP maps, m2ts clips
#   dvd.iso           hdiutil's ISO 9660 + Joliet + UDF 1.02 image of dvd/
#   bluray.iso        hdiutil's ISO 9660 + UDF 1.50 image of bluray/
#   bluray250.iso     a UDF 2.50 image (metadata partition) of bluray/,
#                     written here
#   expected_dvd.json, expected_bluray.json   what the parser should find
#
# The IFO / MPLS / CLPI / index / MovieObject / UDF layouts are written from
# the public format descriptions (see disc/*.tsl headers); the VOB and m2ts
# contents are made by ffmpeg, and their VOBU starts / keyframes are found
# here (VOB) or by ffprobe (m2ts) — the parser's answers are checked
# against these.
#
# Run from ~/Dev/reel: python3 -I tests/disc/make_fixtures.py
#
# Author: Alexius Academia
# Date: 2026-10-26

import json
import os
import shutil
import struct
import subprocess
import sys

OUT = os.path.join("tests", "disc", "fixtures")
TMP = os.path.join("build", "scratch", "disc", "gen")
NTSC = 30000 / 1001


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---------------------------------------------------------------- DVD

def make_vob(path, seconds, freq):
    run("ffmpeg", "-y", "-f", "lavfi", "-i", f"testsrc=size=352x240:rate=30000/1001:duration={seconds}",
        "-f", "lavfi", "-i", f"sine=frequency={freq}:sample_rate=48000:duration={seconds}",
        "-target", "ntsc-dvd", "-s", "352x240", "-b:v", "50k", "-maxrate", "200k", "-bufsize", "224k",
        "-c:a", "ac3", "-b:a", "32k", "-ac", "2", path)
    return open(path, "rb").read()


def vobus(vob):
    """(sector, seconds) of each VOBU start: a pack whose first packet is a
    system header (the NAV pack), with the first video PTS that follows."""
    n = len(vob) // 2048
    starts = []
    first_pts = None
    for s in range(n):
        p = vob[s * 2048:(s + 1) * 2048]
        if p[:4] != b"\x00\x00\x01\xba":
            continue
        h = 14 + (p[13] & 7)
        if p[h:h + 4] == b"\x00\x00\x01\xbb":
            starts.append([s, None])
        if p[h:h + 4] == b"\x00\x00\x01\xe0" and p[h + 7] & 0x80:
            b = p[h + 9:h + 14]
            pts = ((b[0] >> 1) & 7) << 30 | b[1] << 22 | (b[2] >> 1) << 15 | b[3] << 7 | b[4] >> 1
            if first_pts is None:
                first_pts = pts
            if starts and starts[-1][1] is None:
                starts[-1][1] = pts
    out = []
    for s, pts in starts:
        out.append((s, 0.0 if pts is None else (pts - first_pts) / 90000))
    return out, n


def bcd(v):
    return (v // 10) << 4 | (v % 10)


def dvd_time(seconds):
    """BCD playback time at 29.97 (frame-rate bits 11) and the seconds it
    stands for, as the parser computes them."""
    frames = int(round(seconds * NTSC))
    s, f = divmod(frames, 30)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    raw = bytes([bcd(h), bcd(m), bcd(s), 0xC0 | bcd(f)])
    return raw, h * 3600 + m * 60 + s + f / NTSC


class Buf:
    def __init__(self, size=0):
        self.b = bytearray(size)

    def put(self, at, data):
        if at + len(data) > len(self.b):
            self.b.extend(bytes(at + len(data) - len(self.b)))
        self.b[at:at + len(data)] = data

    def u8(self, at, v):
        self.put(at, bytes([v]))

    def u16(self, at, v):
        self.put(at, struct.pack(">H", v))

    def u32(self, at, v):
        self.put(at, struct.pack(">I", v))


def sectors(tables):
    """Lays tables out one after another, each starting on a sector;
    returns (bytes, list of their sector numbers)."""
    out = bytearray()
    where = []
    for t in tables:
        where.append(len(out) // 2048)
        out += t
        out += bytes((-len(out)) % 2048)
    return bytes(out), where


def pgc_bytes(cells, programs, audio_ctl, sub_ctl, palette, nxt=0, prev=0):
    """cells: dicts with flags, time (4 raw bytes), first, last, vob, cell."""
    b = Buf(0xEC)
    total = sum(c["seconds"] for c in cells if c.get("counts", True))
    b.u8(2, len(programs))
    b.u8(3, len(cells))
    b.put(4, dvd_time(total)[0])
    for i, v in enumerate(audio_ctl):
        b.u16(0x0C + 2 * i, v)
    for i, v in enumerate(sub_ctl):
        b.u32(0x1C + 4 * i, v)
    b.u16(0x9C, nxt)
    b.u16(0x9E, prev)
    for i, (y, cr, cb) in enumerate(palette):
        b.put(0xA4 + 4 * i, bytes([0, y, cr, cb]))
    pmap = 0xEC
    b.put(pmap, bytes(programs))
    cplay = pmap + len(programs) + (-(pmap + len(programs)) % 4)
    for i, c in enumerate(cells):
        e = cplay + 24 * i
        b.u8(e, c["flags"])
        b.put(e + 4, c["time"])
        b.u32(e + 8, c["first"])
        b.u32(e + 12, 0)
        b.u32(e + 16, c["lastvobu"])
        b.u32(e + 20, c["last"])
    cpos = cplay + 24 * len(cells)
    for i, c in enumerate(cells):
        b.u16(cpos + 4 * i, c["vob"])
        b.u8(cpos + 4 * i + 3, c["cell"])
    b.u16(0xE4, 0)
    b.u16(0xE6, pmap)
    b.u16(0xE8, cplay)
    b.u16(0xEA, cpos)
    return bytes(b.b)


def make_cell(vob_list, a, b, total_sectors, flags=0, vob=1, cell=1):
    """A cell over VOBUs a..b-1 of `vob_list` (index b may be len = end)."""
    first = vob_list[a][0]
    last = (vob_list[b][0] if b < len(vob_list) else total_sectors) - 1
    t_end = vob_list[b][1] if b < len(vob_list) else vob_list[-1][1] + 0.6
    raw, secs = dvd_time(t_end - vob_list[a][1])
    return {"flags": flags, "time": raw, "seconds": secs, "first": first, "last": last,
            "lastvobu": vob_list[b - 1][0], "vob": vob, "cell": cell}


def vts_ifo(video_attr, audio, subs, ptts, pgcs, tmaps, vobu_list, cells_adt, vob_sectors):
    mat = Buf(0x400)
    mat.put(0, b"DVDVIDEO-VTS")
    mat.u16(0x20, 0x0010)
    mat.put(0x200, video_attr)
    mat.u16(0x202, len(audio))
    for i, a in enumerate(audio):
        mat.put(0x204 + 8 * i, a)
    mat.u16(0x254, len(subs))
    for i, s in enumerate(subs):
        mat.put(0x256 + 6 * i, s)
    # VTS_PTT_SRPT
    ptt = Buf(8 + 4 * len(ptts))
    ptt.u16(0, len(ptts))
    at = 8 + 4 * len(ptts)
    for i, lst in enumerate(ptts):
        ptt.u32(8 + 4 * i, at)
        for pgcn, pgn in lst:
            ptt.u16(at, pgcn)
            ptt.u16(at + 2, pgn)
            at += 4
    ptt.u32(4, len(ptt.b) - 1)
    # VTS_PGCI
    pgci = Buf(8 + 8 * len(pgcs))
    pgci.u16(0, len(pgcs))
    at = len(pgci.b)
    for i, (cat, body) in enumerate(pgcs):
        pgci.u32(8 + 8 * i, cat)
        pgci.u32(8 + 8 * i + 4, at)
        pgci.put(at, body)
        at += len(body)
    pgci.u32(4, len(pgci.b) - 1)
    # VTS_TMAPTI
    tm = Buf(8 + 4 * len(tmaps))
    tm.u16(0, len(tmaps))
    at = len(tm.b)
    for i, (unit, secs) in enumerate(tmaps):
        tm.u32(8 + 4 * i, at)
        tm.u8(at, unit)
        tm.u16(at + 2, len(secs))
        for k, s in enumerate(secs):
            tm.u32(at + 4 + 4 * k, s)
        at += 4 + 4 * len(secs)
    tm.u32(4, len(tm.b) - 1)
    # VTS_C_ADT
    ca = Buf(8 + 12 * len(cells_adt))
    ca.u16(0, 1)
    for i, (vob, cell, first, last) in enumerate(cells_adt):
        e = 8 + 12 * i
        ca.u16(e, vob)
        ca.u8(e + 2, cell)
        ca.u32(e + 4, first)
        ca.u32(e + 8, last)
    ca.u32(4, len(ca.b) - 1)
    # VTS_VOBU_ADMAP
    am = Buf(4 + 4 * len(vobu_list))
    for i, s in enumerate(vobu_list):
        am.u32(4 + 4 * i, s)
    am.u32(0, len(am.b) - 1)
    body, where = sectors([bytes(mat.b), bytes(ptt.b), bytes(pgci.b), bytes(tm.b), bytes(ca.b), bytes(am.b)])
    b = Buf()
    b.put(0, body)
    n = len(body) // 2048
    b.u32(0x0C, 2 * n + vob_sectors - 1)
    b.u32(0x1C, n - 1)
    b.u32(0x80, 0x3FF)
    b.u32(0xC0, 0)
    b.u32(0xC4, n)
    b.u32(0xC8, where[1])
    b.u32(0xCC, where[2])
    b.u32(0xD4, where[3])
    b.u32(0xE0, where[4])
    b.u32(0xE4, where[5])
    return bytes(b.b)


def vmg_ifo(titles, title_sets):
    mat = Buf(0x400)
    mat.put(0, b"DVDVIDEO-VMG")
    mat.u16(0x20, 0x0010)
    mat.u16(0x26, 1)
    mat.u16(0x28, 1)
    mat.u16(0x3E, title_sets)
    mat.put(0x40, b"REEL TEST DISC".ljust(32, b"\x00"))
    tt = Buf(8 + 12 * len(titles))
    tt.u16(0, len(titles))
    for i, (angles, chapters, vts, ttn, start) in enumerate(titles):
        e = 8 + 12 * i
        tt.u8(e, 0x3C)
        tt.u8(e + 1, angles)
        tt.u16(e + 2, chapters)
        tt.u8(e + 6, vts)
        tt.u8(e + 7, ttn)
        tt.u32(e + 8, start)
    tt.u32(4, len(tt.b) - 1)
    body, where = sectors([bytes(mat.b), bytes(tt.b)])
    b = Buf()
    b.put(0, body)
    n = len(body) // 2048
    b.u32(0x0C, 2 * n - 1)
    b.u32(0x1C, n - 1)
    b.u32(0x80, 0x3FF)
    b.u32(0xC4, where[1])
    return bytes(b.b)


def ycrcb_to_rgba(y, cr, cb):
    yy = 1.164383 * (y - 16)
    r = yy + 1.596027 * (cr - 128)
    g = yy - 0.391762 * (cb - 128) - 0.812968 * (cr - 128)
    b = yy + 2.017232 * (cb - 128)
    c = [max(0, min(255, int(round(v)))) for v in (r, g, b)]
    return c[0] << 24 | c[1] << 16 | c[2] << 8 | 0xFF


def tmap_for(vob_list, cells_in_order, unit=1):
    """Time map of a PGC: for each `unit` seconds, the VOBU sector at or
    before that time on the PGC's time line."""
    # The PGC's time line: the cells' VOBUs one after the other.
    line = []
    t0 = 0.0
    for c in cells_in_order:
        for s, t in vob_list:
            if c["first"] <= s <= c["last"]:
                line.append((t0 + t - c["vstart"], s))
        t0 += c["seconds"]
    out = []
    k = 1
    while k * unit < t0:
        best = None
        for t, s in line:
            if t <= k * unit + 1e-9:
                best = s
        out.append(best)
        k += 1
    return out


def make_dvd():
    root = os.path.join(OUT, "dvd", "VIDEO_TS")
    os.makedirs(root, exist_ok=True)
    a = make_vob(os.path.join(TMP, "a.vob"), 4, 440)
    b = make_vob(os.path.join(TMP, "b.vob"), 4, 660)
    va, na = vobus(a)
    vb, nb = vobus(b)
    assert len(va) >= 5 and len(vb) >= 5, (len(va), len(vb))

    palette = [(16, 128, 128), (235, 128, 128), (81, 240, 90), (145, 34, 54), (41, 110, 240),
               (210, 146, 16), (170, 16, 166), (106, 222, 202), (128, 128, 128), (60, 128, 128),
               (180, 128, 128), (100, 200, 100), (150, 60, 200), (90, 100, 100), (200, 120, 140), (30, 130, 125)]
    palette2 = [(235 - 10 * i, 128, 128) for i in range(16)]

    # ---- VTS 1: title VOBs A, split over two files mid-cell.
    c1 = make_cell(va, 0, 2, na, vob=1, cell=1)
    c2 = make_cell(va, 2, 4, na, vob=1, cell=2)
    c3 = make_cell(va, 4, len(va), na, vob=1, cell=3)
    for c, i in ((c1, 0), (c2, 2), (c3, 4)):
        c["vstart"] = va[i][1]
    split = c2["first"] + 3  # VTS_01_1.VOB ends 3 sectors into cell 2
    with open(os.path.join(root, "VTS_01_1.VOB"), "wb") as f:
        f.write(a[:split * 2048])
    with open(os.path.join(root, "VTS_01_2.VOB"), "wb") as f:
        f.write(a[split * 2048:])
    # Audio: AC-3 English (stream 0), AC-3 French director's comments
    # (stream 1, not in the VOB). Subpictures: English, Spanish forced.
    aud = [bytes([0 << 5 | 1 << 2, 0 << 6 | 0 << 4 | 1]) + b"en" + bytes([0, 0, 0, 0]),
           bytes([0 << 5 | 1 << 2, 0 << 6 | 0 << 4 | 5]) + b"fr" + bytes([0, 3, 0, 0])]
    sub = [bytes([0 << 5 | 1, 0]) + b"en" + bytes([0, 1]),
           bytes([0 << 5 | 1, 0]) + b"es" + bytes([0, 9])]
    actl = [0x8000 | 0 << 8, 0x8000 | 1 << 8]
    sctl = [0x80000000 | 0 << 24, 0x80000000 | 1 << 24]
    video1 = bytes([1 << 6 | 0 << 4 | 0 << 2, 3 << 3])  # MPEG-2 NTSC 4:3 352x240
    pgc1 = pgc_bytes([c1, c2, c3], [1, 3], actl, sctl, palette)
    pgc2 = pgc_bytes([dict(c2, cell=1)], [1], actl, sctl, palette)
    tm1 = tmap_for(va, [c1, c2, c3])
    tm2 = tmap_for(va, [c2])
    vts1 = vts_ifo(video1, aud, sub, [[(1, 1), (1, 2)], [(2, 1)]],
                   [(0x80000000 | 1 << 24, pgc1), (0x80000000 | 2 << 24, pgc2)],
                   [(1, tm1), (1, tm2)], [s for s, _ in va],
                   [(1, 1, c1["first"], c1["last"]), (1, 2, c2["first"], c2["last"]), (1, 3, c3["first"], c3["last"])],
                   na)
    for ext in ("IFO", "BUP"):
        open(os.path.join(root, f"VTS_01_0.{ext}"), "wb").write(vts1)

    # ---- VTS 2: title 3 = PGC 1 (cell over VOBU 0) then PGC 2 (angle
    # block: angle 1 = VOBU 1, angle 2 = VOBU 2; then VOBUs 3…).
    d1 = make_cell(vb, 0, 1, nb, vob=1, cell=1)
    d2 = make_cell(vb, 1, 2, nb, flags=1 << 6 | 1 << 4, vob=1, cell=2)
    d3 = make_cell(vb, 2, 3, nb, flags=3 << 6 | 1 << 4, vob=1, cell=3)
    d4 = make_cell(vb, 3, len(vb), nb, vob=1, cell=4)
    d4["flags"] = 1 << 1  # STC discontinuity
    # Both angle cells play the same length.
    d3["time"], d3["seconds"] = d2["time"], d2["seconds"]
    open(os.path.join(root, "VTS_02_1.VOB"), "wb").write(b)
    aud2 = [bytes([0 << 5 | 1 << 2, 1]) + b"ja" + bytes([0, 1, 0, 0])]
    sub2 = [bytes([1, 0]) + b"de" + bytes([0, 1])]
    actl2 = [0x8000]
    sctl2 = [0x80000000 | 0 << 24 | 2 << 16 | 1 << 8 | 3]
    video2 = bytes([1 << 6 | 0 << 4 | 3 << 2, 3 << 3])  # 16:9
    p21 = pgc_bytes([d1], [1], actl2, sctl2, palette2, nxt=2)
    d2c = dict(d2)
    d2c["counts"] = True
    d3c = dict(d3)
    d3c["counts"] = False
    p22 = pgc_bytes([d2c, d3c, d4], [1, 3], actl2, sctl2, palette2, prev=1)
    vts2 = vts_ifo(video2, aud2, sub2, [[(1, 1), (2, 1), (2, 2)]],
                   [(0x80000000 | 1 << 24, p21), (0 | 1 << 24, p22)],
                   [], [s for s, _ in vb], [], nb)
    for ext in ("IFO", "BUP"):
        open(os.path.join(root, f"VTS_02_0.{ext}"), "wb").write(vts2)

    # ---- VTS 3: title 4, a 2-angle block of interleaved cells: the VOB
    # area alternates the VOBUs of A (angle 1) and B (angle 2), one VOBU
    # per ILVU, each NAV pack's DSI saying where its ILVU ends and the
    # next one of the same angle starts.
    def chunks(vob, vl, n):
        out = []
        for i, (s0, _) in enumerate(vl):
            s1 = vl[i + 1][0] if i + 1 < len(vl) else n
            out.append(bytearray(vob[s0 * 2048:s1 * 2048]))
        return out
    ca, cb = chunks(a, va, na), chunks(b, vb, nb)
    k = min(3, len(ca), len(cb))
    order = []
    for i in range(k):
        order.append(("A", i, ca[i]))
        order.append(("B", i, cb[i]))
    start = {}
    at = 0
    for name, i, ch in order:
        start[(name, i)] = at
        at += len(ch) // 2048
    area = bytearray()
    for name, i, ch in order:
        n = len(ch) // 2048
        dsi = 0x407
        cat = 0x4000 | (0x2000 if i == 0 else 0) | (0x1000 if i == k - 1 else 0)
        nxt = start[(name, i + 1)] - start[(name, i)] if i + 1 < k else 0x7FFFFFFF
        struct.pack_into(">I", ch, dsi + 0x08, n - 1)
        struct.pack_into(">HII", ch, dsi + 0x20, cat, n - 1, nxt)
        area += ch
    open(os.path.join(root, "VTS_03_1.VOB"), "wb").write(area)
    na3 = len(area) // 2048
    secs_a = sum(len(c) for c in ca[:k]) // 2048
    raw3, sec3 = dvd_time(va[-1][1] + 0.6) if k == len(ca) else dvd_time(va[k][1])
    def ilv_cell(name, mode, cell):
        first = start[(name, 0)]
        last = start[(name, k - 1)] + len((ca if name == "A" else cb)[k - 1]) // 2048 - 1
        return {"flags": mode << 6 | 1 << 4 | 1 << 2, "time": raw3, "seconds": sec3, "first": first,
                "last": last, "lastvobu": start[(name, k - 1)], "vob": 1, "cell": cell}
    e1 = ilv_cell("A", 1, 1)
    e2 = ilv_cell("B", 3, 2)
    e2c = dict(e2)
    e2c["counts"] = False
    p31 = pgc_bytes([e1, e2c], [1], actl2, sctl2, palette2)
    vts3 = vts_ifo(video2, aud2, sub2, [[(1, 1)]], [(0x80000000 | 1 << 24, p31)], [],
                   [start[(n, i)] for n, i, _ in order], [], na3)
    for ext in ("IFO", "BUP"):
        open(os.path.join(root, f"VTS_03_0.{ext}"), "wb").write(vts3)

    vmg = vmg_ifo([(1, 2, 1, 1, 0), (1, 1, 1, 2, 0), (2, 3, 2, 1, 0), (2, 1, 3, 1, 0)], 3)
    for ext in ("IFO", "BUP"):
        open(os.path.join(root, f"VIDEO_TS.{ext}"), "wb").write(vmg)

    # ---- What the parser should find.
    f1 = os.path.getsize(os.path.join(root, "VTS_01_1.VOB"))

    def pieces(c, files):
        """(file, from, to, start offset within the cell)"""
        lo, hi = c["first"] * 2048, (c["last"] + 1) * 2048
        out = []
        base = 0
        for name, size in files:
            a0, b0 = max(lo, base), min(hi, base + size)
            if b0 > a0:
                out.append([name, a0 - base, b0 - base])
            base += size
        return out

    files1 = [("VTS_01_1.VOB", f1), ("VTS_01_2.VOB", len(a) - f1)]
    files2 = [("VTS_02_1.VOB", len(b))]

    def title(number, cells, files, chapters_at, streams, pal, angles=1, w=352, h=240, aspect="4:3"):
        segs = []
        t = 0.0
        for c in cells:
            ps = pieces(c, files)
            total = (c["last"] - c["first"] + 1) * 2048
            at = t
            for p in ps:
                d = c["seconds"] * (p[2] - p[1]) / total if len(ps) > 1 else c["seconds"]
                segs.append({"file": p[0], "from": p[1], "to": p[2], "start": at})
                at += d
            t += c["seconds"]
        return {"number": number, "duration": t, "chapters": chapters_at, "segments": segs,
                "streams": streams, "palette": [ycrcb_to_rgba(*p) for p in pal], "angles": angles,
                "width": w, "height": h, "aspect": aspect}

    vid = {"kind": "video", "codec": "mpeg2", "id": 0xE0, "language": "", "note": ""}
    st1 = [vid, {"kind": "audio", "codec": "ac3", "id": 0xBD80, "language": "eng", "note": "", "channels": 2},
           {"kind": "audio", "codec": "ac3", "id": 0xBD81, "language": "fre", "note": "Director's comments", "channels": 6},
           {"kind": "subtitle", "codec": "dvdsub", "id": 0xBD20, "language": "eng", "note": ""},
           {"kind": "subtitle", "codec": "dvdsub", "id": 0xBD21, "language": "spa", "note": "Forced"}]
    st2 = [vid, {"kind": "audio", "codec": "ac3", "id": 0xBD80, "language": "jpn", "note": "", "channels": 2},
           {"kind": "subtitle", "codec": "dvdsub", "id": 0xBD22, "language": "ger", "note": ""}]
    t1 = title(1, [c1, c2, c3], files1, [0.0, c1["seconds"] + c2["seconds"]], st1, palette)
    t2 = title(2, [c2], files1, [0.0], st1, palette)
    t3 = title(3, [d1, d2, d4], files2, [0.0, d1["seconds"], d1["seconds"] + d2["seconds"]], st2, palette2,
               angles=2, aspect="16:9")
    t3b = title(3, [d1, d3, d4], files2, [0.0, d1["seconds"], d1["seconds"] + d2["seconds"]], st2, palette2,
                angles=2, aspect="16:9")
    exp = {"titles": [t1, t2, t3], "angle2": t3b, "main": 0,
           "interleaved": {"duration": sec3, "angle1Bytes": sum(len(c) for c in ca[:k]),
                           "angle2Bytes": sum(len(c) for c in cb[:k]), "ilvus": k,
                           "angle1Md5": __import__("hashlib").md5(b"".join(bytes(c) for c in ca[:k])).hexdigest(),
                           "angle2Md5": __import__("hashlib").md5(b"".join(bytes(c) for c in cb[:k])).hexdigest(),
                           "unresolvedTo": (e1["last"] + 1) * 2048},
           "vobus1": [s for s, _ in va], "vobus2": [s for s, _ in vb], "provider": "REEL TEST DISC"}
    json.dump(exp, open(os.path.join(OUT, "expected_dvd.json"), "w"), indent=1)


# ---------------------------------------------------------------- Blu-ray

def make_m2ts(path, seconds, freq, size="320x240"):
    run("ffmpeg", "-y", "-f", "lavfi", "-i", f"testsrc=size={size}:rate=24000/1001:duration={seconds}",
        "-f", "lavfi", "-i", f"sine=frequency={freq}:sample_rate=48000:duration={seconds}",
        "-c:v", "libx264", "-preset", "veryfast", "-b:v", "40k", "-g", "12", "-bf", "0", "-pix_fmt", "yuv420p",
        "-c:a", "ac3", "-b:a", "32k", "-streamid", "0:4113", "-streamid", "1:4352",
        "-f", "mpegts", "-mpegts_m2ts_mode", "1", path)
    # Keyframes (ffprobe): PTS (90 kHz) and the source packet they start in.
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "packet=pts,pos,flags",
                        "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    keys = []
    pts_all = []
    for line in r.stdout.split():
        pts, pos, flags = line.split(",")[:3]
        pts_all.append(int(pts))
        if "K" in flags:
            # The EP map keeps PTS bits 32…9 only.
            keys.append((int(pts) & ~511, int(pos) // 192))
    return keys, min(pts_all), max(pts_all) + 3754  # one frame at 23.976


def clpi_bytes(keys, packets, video_pid=0x1011, audio_pid=0x1100, start=0, end=0):
    seq = Buf(4)
    seq.put(4, bytes([0, 1]))
    seq.u32(6, 0)
    seq.put(10, bytes([1, 0]))
    seq.u16(12, video_pid)
    seq.u32(14, 0)
    seq.u32(18, start)
    seq.u32(22, end)
    seq.u32(0, len(seq.b) - 4)
    prog = Buf(4)
    prog.put(4, bytes([0, 1]))
    prog.u32(6, 0)
    prog.u16(10, 0x0100)
    prog.put(12, bytes([2, 0]))
    # Video: H.264 1080p? No: format 1 is 480i; use 6 (1080p) / 23.976 as
    # a real disc would say for its main video.
    prog.put(14, struct.pack(">HB", video_pid, 5) + bytes([0x1B, 6 << 4 | 1, 0x30, 0, 0]))
    prog.put(len(prog.b), struct.pack(">HB", audio_pid, 5) + bytes([0x81, 3 << 4 | 1]) + b"eng")
    prog.u32(0, len(prog.b) - 4)
    # EP map: one stream; a coarse entry every 3 fine entries.
    fine = []
    coarse = []
    for i, (pts, spn) in enumerate(keys):
        if i % 3 == 0:
            coarse.append((i, (pts >> 19) & 0x3FFF, spn))
        fine.append(((pts >> 9) & 0x7FF) << 17 | (spn & 0x1FFFF))
    one = Buf(4)
    for ref, pc, spn in coarse:
        one.put(len(one.b), struct.pack(">II", ref << 14 | pc, spn))
    one.u32(0, len(one.b))
    for f in fine:
        one.put(len(one.b), struct.pack(">I", f))
    ep = Buf(2 + 12)
    ep.put(0, bytes([0, 1]))
    ep.u16(2, video_pid)
    word = (1 << 34) | (len(coarse) << 18) | len(fine)   # stream type 1
    ep.put(4, word.to_bytes(6, "big"))
    ep.u32(10, 14)
    ep.put(14, bytes(one.b))
    cpi = Buf(6)
    cpi.u16(4, 1)
    cpi.put(6, bytes(ep.b))
    cpi.u32(0, len(cpi.b) - 4)
    info = Buf(4)
    info.put(4, bytes([0, 0, 1, 1]))
    info.u32(8, 0)
    info.u32(12, 48000 * 24)
    info.u32(16, packets)
    info.put(20, bytes(128))
    info.u32(0, len(info.b) - 4)
    h = Buf(40)
    h.put(0, b"HDMV0200")
    body = bytes(h.b)
    at_info = len(body)
    body += bytes(info.b)
    at_seq = len(body)
    body += bytes(seq.b)
    at_prog = len(body)
    body += bytes(prog.b)
    at_cpi = len(body)
    body += bytes(cpi.b)
    b = bytearray(body)
    struct.pack_into(">IIIII", b, 8, at_seq, at_prog, at_cpi, 0, 0)
    assert at_info == 40
    return bytes(b)


def stn_bytes(streams):
    """streams: (kind, coding, pid, lang)"""
    kinds = ["video", "audio", "pg", "ig"]
    counts = [sum(1 for s in streams if s[0] == k) for k in kinds]
    body = bytearray()
    for k in kinds:
        for kind, coding, pid, lang in streams:
            if kind != k:
                continue
            entry = bytes([9, 1]) + struct.pack(">H", pid) + bytes(6)
            if kind == "video":
                attr = bytes([coding, 6 << 4 | 1])
            elif kind == "audio":
                attr = bytes([coding, 6 << 4 | 1]) + lang.encode()
            else:
                attr = bytes([coding]) + lang.encode()
            attr = bytes([len(attr)]) + attr
            body += entry + attr
    head = struct.pack(">HH", 16 - 2 + len(body), 0) + bytes(counts + [0, 0, 0]) + bytes(5)
    return head + bytes(body)


STREAMS = [("video", 0x1B, 0x1011, ""), ("audio", 0x81, 0x1100, "eng"), ("audio", 0x83, 0x1101, "fra"),
           ("pg", 0x90, 0x1200, "eng"), ("pg", 0x90, 0x1201, "deu"), ("ig", 0x91, 0x1400, "")]


def mpls_bytes(items, marks, streams=STREAMS):
    """items: (clip, in45, out45, angle_clips)"""
    pl = bytearray()
    for clip, tin, tout, angles in items:
        it = bytearray()
        it += clip.encode() + b"M2TS"
        it += struct.pack(">H", (1 << 4 if angles else 0) | 1)
        it += bytes([0])
        it += struct.pack(">II", tin, tout)
        it += bytes(8) + bytes([0x80, 0]) + bytes(2)
        if angles:
            it += bytes([1 + len(angles), 0])
            for a in angles:
                it += a.encode() + b"M2TS" + bytes([0])
        it += stn_bytes(streams)
        pl += struct.pack(">H", len(it)) + it
    playlist = struct.pack(">IHHH", 6 + len(pl), 0, len(items), 0) + bytes(pl)
    mk = bytearray()
    for mtype, item, t in marks:
        mk += bytes([0, mtype]) + struct.pack(">HIHI", item, t, 0xFFFF, 0)
    marktab = struct.pack(">IH", 2 + len(mk), len(marks)) + bytes(mk)
    app = struct.pack(">IBBH", 14, 0, 1, 0) + bytes(8) + bytes(2)
    head_len = 40
    at_pl = head_len + len(app)
    at_mk = at_pl + len(playlist)
    head = b"MPLS0200" + struct.pack(">III", at_pl, at_mk, 0) + bytes(20)
    return head + app + playlist + marktab


def index_bytes(titles):
    """titles: ("hdmv", mobj) or ("bdj", "00000")"""
    def entry(t):
        if t[0] == "hdmv":
            return bytes([1 << 6, 0, 0, 0]) + struct.pack(">HH", 0, t[1]) + bytes(4)
        return bytes([2 << 6, 0, 0, 0]) + struct.pack(">H", 0) + t[1].encode() + bytes(1)
    app = struct.pack(">I", 34) + bytes(34)
    body = entry(("hdmv", 0xFFFF)) + entry(("hdmv", 0xFFFF)) + struct.pack(">H", len(titles))
    for t in titles:
        body += entry(t)
    idx = struct.pack(">I", len(body)) + body
    at = 40 + len(app)
    return b"INDX0200" + struct.pack(">II", at, 0) + bytes(24) + app + idx


def mobj_bytes(objects):
    """objects: lists of (opcode bytes, op1, op2)"""
    body = bytearray()
    for cmds in objects:
        body += struct.pack(">HH", 0x8000, len(cmds))
        for op, a, b in cmds:
            body += op + struct.pack(">II", a, b)
    tab = struct.pack(">II", 6 + len(body), 0) + struct.pack(">H", len(objects)) + bytes(body)
    return b"MOBJ0200" + struct.pack(">I", 0) + bytes(28) + tab


def make_bluray():
    root = os.path.join(OUT, "bluray", "BDMV")
    for sub in ("PLAYLIST", "CLIPINF", "STREAM", "BACKUP", "AUXDATA"):
        os.makedirs(os.path.join(root, sub), exist_ok=True)
    clips = {}
    for name, secs, freq in (("00001", 4, 330), ("00002", 2, 550), ("00003", 3, 770)):
        path = os.path.join(root, "STREAM", name + ".m2ts")
        keys, first, last = make_m2ts(path, secs, freq)
        packets = os.path.getsize(path) // 192
        clips[name] = {"keys": keys, "in": first // 2, "out": last // 2, "size": os.path.getsize(path)}
        open(os.path.join(root, "CLIPINF", name + ".clpi"), "wb").write(
            clpi_bytes(keys, packets, start=first // 2, end=last // 2))
    c1, c2, c3 = clips["00001"], clips["00002"], clips["00003"]
    mid1 = c1["in"] + 2 * 45000
    main = [("00001", c1["in"], c1["out"], []), ("00003", c3["in"], c3["out"], [])]
    main_marks = [(1, 0, c1["in"]), (1, 0, mid1), (2, 0, mid1 + 4500), (1, 1, c3["in"])]
    pls = {
        0: (main, main_marks),
        1: (main, main_marks),                                          # duplicate
        2: ([("00002", c2["in"], c2["out"], [])], [(1, 0, c2["in"])]),  # trailer
        # Decoys with the main feature's length: its pieces out of order.
        3: ([("00003", c3["in"], c3["out"], []), ("00001", c1["in"], c1["out"], [])], [(1, 0, c3["in"])]),
        4: ([("00001", mid1, c1["out"], []), ("00003", c3["in"], c3["out"], []), ("00001", c1["in"], mid1, [])], []),
        5: ([("00001", c1["in"], mid1, []), ("00003", c3["in"], c3["out"], []), ("00001", mid1, c1["out"], [])], []),
        # Longer, but plays the same clip twice.
        8: ([("00001", c1["in"], c1["out"], []), ("00001", c1["in"], c1["out"], []), ("00003", c3["in"], c3["out"], [])], []),
        # Two angles: 00001 or 00003 (cut to the same length).
        9: ([("00001", c1["in"], c1["in"] + 3 * 45000, ["00003"])], [(1, 0, c1["in"])]),
    }
    for n, (items, marks) in pls.items():
        data = mpls_bytes(items, marks)
        open(os.path.join(root, "PLAYLIST", f"{n:05d}.mpls"), "wb").write(data)
    idx = index_bytes([("hdmv", 0), ("hdmv", 1), ("bdj", "00000")])
    mob = mobj_bytes([
        [(bytes([0x50, 0x00, 0x00, 0x00]), 1, 2),                     # a SET command
         (bytes([0x22, 0x80, 0x00, 0x00]), 0, 0)],                    # PlayPL 0
        [(bytes([0x22, 0x82, 0x00, 0x00]), 2, 0)],                    # PlayPL 2 at a mark
    ])
    open(os.path.join(root, "index.bdmv"), "wb").write(idx)
    open(os.path.join(root, "MovieObject.bdmv"), "wb").write(mob)
    os.makedirs(os.path.join(root, "BACKUP", "PLAYLIST"), exist_ok=True)
    shutil.copy(os.path.join(root, "index.bdmv"), os.path.join(root, "BACKUP", "index.bdmv"))

    def dur(items):
        return sum(o - i for _, i, o, _ in items) / 45000

    def segs(items, angle=1):
        out = []
        t = 0.0
        for clip, tin, tout, angles in items:
            name = clip if angle == 1 else angles[angle - 2]
            c = clips[name]
            frm = 0
            to = None
            for pts, spn in c["keys"]:
                if pts <= tin * 2:
                    frm = spn
                if pts > tout * 2 and to is None:
                    to = spn
            out.append({"file": name + ".m2ts", "from": frm * 192,
                        "to": c["size"] if to is None else to * 192, "start": t})
            t += (tout - tin) / 45000
        return out

    def chapters(items, marks):
        starts = []
        acc = [0.0]
        for _, i, o, _ in items:
            acc.append(acc[-1] + (o - i) / 45000)
        for mtype, item, t in marks:
            if mtype == 1:
                starts.append(acc[item] + (t - items[item][1]) / 45000)
        return sorted(starts)

    exp = {"playlists": {}, "main": 0, "titlePlaylists": [0, 2, -1],
           "keys": {k: v["keys"] for k, v in clips.items()}}
    for n, (items, marks) in pls.items():
        exp["playlists"][str(n)] = {"duration": dur(items), "segments": segs(items),
                                    "chapters": chapters(items, marks), "items": len(items)}
    exp["angle2"] = {"segments": segs(pls[9][0], angle=2)}
    exp["listed"] = [0, 2, 3, 4, 5, 8, 9]
    exp["clipInfo"] = {k: {"start": v["in"], "end": v["out"], "packets": v["size"] // 192} for k, v in clips.items()}
    json.dump(exp, open(os.path.join(OUT, "expected_bluray.json"), "w"), indent=1)


# ---------------------------------------------------------------- UDF 2.50

def crc_itu(data):
    """CRC-CCITT (x^16 + x^12 + x^5 + 1), initial 0, as ECMA-167 7.2.6."""
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def tag(ident, location, body):
    """Fills in a 16-byte descriptor tag in front of `body` (which starts
    with 16 bytes of room for it)."""
    b = bytearray(body)
    crc_len = len(b) - 16
    struct.pack_into("<HHBBHHHI", b, 0, ident, 3, 0, 0, 1, crc_itu(b[16:]), crc_len, location)
    b[4] = sum(b[0:4] + b[5:16]) & 0xFF
    return bytes(b)


def dstring(text, size):
    raw = bytes([8]) + text.encode("latin-1")
    out = raw + bytes(size - len(raw))
    return out[:size - 1] + bytes([len(raw)])


def regid(ident, suffix=b""):
    return bytes([0]) + ident.encode().ljust(23, b"\x00") + suffix.ljust(8, b"\x00")


def make_udf250(src, out_path, volume="REEL_BD"):
    """A UDF 2.50 image of folder `src`: one physical partition (number 0)
    holding the file data, and a metadata partition (map 1) whose
    metadata file holds the file set descriptor, every file entry and the
    directories."""
    S = 2048
    files = []   # (relpath, is_dir)
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames.sort()
        rel = os.path.relpath(dirpath, src)
        rel = "" if rel == "." else rel
        for d in dirnames:
            files.append((os.path.join(rel, d) if rel else d, True))
        for f in sorted(filenames):
            if not f.startswith("."):
                files.append((os.path.join(rel, f) if rel else f, False))
    part_start = 272          # partition 0 starts at sector 272
    # Partition layout (blocks relative to part_start):
    #   0      metadata file's file entry (in the physical partition)
    #   1      metadata mirror file entry (same extents)
    #   2…     metadata content (metadata partition blocks 0…M−1)
    #   then   file data
    dirs = [""] + [p for p, d in files if d]
    entries = {}              # path → metadata block of its file entry
    meta_blocks = []          # metadata partition block contents
    meta_blocks.append(None)  # block 0: file set descriptor
    for p in dirs + [p for p, d in files if not d]:
        entries[p] = len(meta_blocks)
        meta_blocks.append(None)
    # Directory contents get their own metadata blocks (one each, enough
    # for these small folders).
    dir_data_block = {}
    for p in dirs:
        dir_data_block[p] = len(meta_blocks)
        meta_blocks.append(None)
    meta_count = len(meta_blocks)
    data_block = 2 + meta_count
    file_extent = {}
    for p, d in files:
        if not d:
            size = os.path.getsize(os.path.join(src, p))
            file_extent[p] = (data_block, size)
            data_block += (size + S - 1) // S
    part_len = data_block

    def long_ad(length, block, ref):
        return struct.pack("<IIH", length, block, ref) + bytes(6)

    def file_entry(location, ftype, info_len, ads, ad_type):
        b = bytearray(216)
        # ICB tag: strategy 4, file type, flags = allocation type.
        struct.pack_into("<IHHHBB", b, 16, 0, 4, 0, 1, 0, ftype)
        struct.pack_into("<H", b, 34, ad_type)
        struct.pack_into("<IIIHBBI", b, 36, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFF, 1, 0, 0, 0)
        struct.pack_into("<QQ", b, 56, info_len, info_len)
        struct.pack_into("<QQ", b, 64, info_len, (info_len + S - 1) // S)
        struct.pack_into("<II", b, 208, 0, len(ads))
        return tag(266, location, bytes(b) + ads)

    # Metadata blocks.
    def children(p):
        out = []
        for q, d in files:
            if os.path.dirname(q) == p:
                out.append((q, d))
        return out

    for p in dirs:
        fids = bytearray()
        # Parent entry first.
        parent = os.path.dirname(p) if p else ""
        body = bytearray(38)
        struct.pack_into("<HBB", body, 16, 1, 0x0A, 0)
        body[20:36] = long_ad(S, entries[parent], 1)
        body += bytes((-len(body)) % 4)
        fids += tag(257, dir_data_block[p], bytes(body))
        for q, d in children(p):
            name = bytes([8]) + os.path.basename(q).encode("latin-1")
            body = bytearray(38)
            struct.pack_into("<HBB", body, 16, 1, 0x02 if d else 0, len(name))
            body[20:36] = long_ad(S, entries[q], 1)
            body += name
            body += bytes((-len(body)) % 4)
            fids += tag(257, dir_data_block[p], bytes(body))
        assert len(fids) <= S
        meta_blocks[dir_data_block[p]] = bytes(fids)
        ads = struct.pack("<II", len(fids), dir_data_block[p])
        meta_blocks[entries[p]] = file_entry(entries[p], 4, len(fids), ads, 0)
    for p, d in files:
        if not d:
            blk, size = file_extent[p]
            ads = long_ad(size, blk, 0) if size else b""
            meta_blocks[entries[p]] = file_entry(entries[p], 5, size, ads, 1)
    fsd = bytearray(512)
    fsd[400:416] = long_ad(S, entries[""], 1)
    meta_blocks[0] = tag(256, 0, bytes(fsd))

    total = part_start + part_len + 257
    img = bytearray(total * S)

    def put(sector, data):
        img[sector * S:sector * S + len(data)] = data

    # Volume recognition: BEA01, NSR03, TEA01 at sectors 16–18.
    for i, ident in enumerate((b"BEA01", b"NSR03", b"TEA01")):
        put(16 + i, bytes([0]) + ident + bytes([1]))
    # Volume descriptor sequence at 32.
    pvd = bytearray(512)
    pvd[24:56] = dstring(volume, 32)
    put(32, tag(1, 32, bytes(pvd)))
    pd = bytearray(512)
    struct.pack_into("<IHH", pd, 16, 1, 1, 0)
    pd[24:56] = regid("+NSR03")
    struct.pack_into("<III", pd, 184, 1, part_start, part_len)
    put(33, tag(5, 33, bytes(pd)))
    lvd = bytearray(440)
    struct.pack_into("<I", lvd, 16, 2)
    lvd[84:212] = dstring(volume, 128)
    struct.pack_into("<I", lvd, 212, S)
    lvd[216:248] = regid("*OSTA UDF Compliant", b"\x50\x02")
    lvd[248:264] = long_ad(S, 0, 1)            # FSD: metadata block 0
    maps = struct.pack("<BBHH", 1, 6, 1, 0)
    m2 = bytearray(64)
    m2[0], m2[1] = 2, 64
    m2[4:36] = regid("*UDF Metadata Partition", b"\x50\x02")
    struct.pack_into("<HHIIIIHB", m2, 36, 1, 0, 0, 1, 0xFFFFFFFF, 32, 1, 0)
    maps += bytes(m2)
    struct.pack_into("<II", lvd, 264, len(maps), 2)
    put(34, tag(6, 34, bytes(lvd) + maps))
    put(35, tag(8, 35, bytes(512)))
    # Anchors.
    for s in (256, total - 1):
        av = bytearray(512)
        struct.pack_into("<IIII", av, 16, 6 * S, 32, 6 * S, 32)
        put(s, tag(2, s, bytes(av)))
    # Partition: metadata file entries (type 250 / 251), then contents.
    meta_ads = struct.pack("<II", meta_count * S, 2)
    put(part_start + 0, file_entry(0, 250, meta_count * S, meta_ads, 0))
    put(part_start + 1, file_entry(1, 251, meta_count * S, meta_ads, 0))
    for i, blk in enumerate(meta_blocks):
        put(part_start + 2 + i, blk)
    for p, (blk, size) in file_extent.items():
        put(part_start + blk, open(os.path.join(src, p), "rb").read())
    open(out_path, "wb").write(bytes(img))
    return {p: (part_start + blk) * S for p, (blk, size) in file_extent.items()}


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    os.makedirs(TMP, exist_ok=True)
    make_dvd()
    make_bluray()
    run("hdiutil", "makehybrid", "-o", os.path.join(OUT, "dvd.iso"), os.path.join(OUT, "dvd"),
        "-iso", "-joliet", "-udf", "-udf-version", "1.02", "-default-volume-name", "REEL_DVD")
    run("hdiutil", "makehybrid", "-o", os.path.join(OUT, "bluray.iso"), os.path.join(OUT, "bluray"),
        "-iso", "-udf", "-udf-version", "1.50", "-default-volume-name", "REEL_BD")
    offs = make_udf250(os.path.join(OUT, "bluray"), os.path.join(OUT, "bluray250.iso"))
    json.dump({k.replace(os.sep, "/"): v for k, v in offs.items()},
              open(os.path.join(OUT, "expected_udf250.json"), "w"), indent=1)
    # The images are mostly zero padding: keep them gzipped (the test
    # unpacks them with Data.decompressed("gzip")).
    import gzip
    for name in ("dvd.iso", "bluray.iso", "bluray250.iso"):
        path = os.path.join(OUT, name)
        with open(path, "rb") as f, gzip.open(path + ".gz", "wb", compresslevel=9) as g:
            g.write(f.read())
        os.remove(path)
    total = 0
    for dirpath, _, names in os.walk(OUT):
        for n in names:
            total += os.path.getsize(os.path.join(dirpath, n))
    print(f"fixtures: {total // 1024} KB")


if __name__ == "__main__":
    main()
