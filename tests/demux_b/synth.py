# Builds Matroska and Ogg files by hand for demux_b's tests: the features
# ffmpeg's muxers never write (Xiph/EBML/fixed lacing, unknown-size live
# WebM clusters, header stripping, zlib, legacy AAC CodecIDs, nested and
# hidden chapters, BCP 47 languages, damaged bytes, Theora granules, Ogg
# packets across pages, bad CRCs, METADATA_BLOCK_PICTURE covers). Each
# file F gets F.ref.json in testkit's Ref form with the exact answers;
# its "format" starts with "synth" so the test compares packet offsets
# exactly (they are the frames' own offsets, not ffprobe's block starts).
#
# Usage: python3 -I tests/demux_b/synth.py <folder>
#
# Author: Alexius Academia
# Date: 2026-10-25
import base64, json, os, struct, sys, zlib

NO = -9223372036854775807
out = sys.argv[1]


# ---------- EBML ----------
def vid(i):
    n = (i.bit_length() + 7) // 8
    return i.to_bytes(n, "big")


def vsize(n, width=None):
    if width is None:
        width = 1
        while n >= (1 << (7 * width)) - 1:
            width += 1
    return ((1 << (7 * width)) | n).to_bytes(width, "big")


UNKNOWN = b"\x01\xff\xff\xff\xff\xff\xff\xff"


def el(i, body):
    return vid(i) + vsize(len(body)) + body


def u(i, v):
    n = max(1, (v.bit_length() + 7) // 8)
    return el(i, v.to_bytes(n, "big"))


def s(i, text):
    return el(i, text.encode())


def f(i, v):
    return el(i, struct.pack(">d", v))


def ebml_header(doctype):
    return el(0x1A45DFA3, u(0x4286, 1) + u(0x42F7, 1) + u(0x42F2, 4) + u(0x42F3, 8) + s(0x4282, doctype) + u(0x4287, 4) + u(0x4285, 2))


class Ref:
    def __init__(self, fmt):
        self.r = {"format": fmt, "duration": -1.0, "tags": {}, "tracks": [], "packets": [], "chapters": []}

    def track(self, **kw):
        t = {"index": len(self.r["tracks"]), "kind": "other", "codec": "", "timescale": 1000, "duration": NO,
             "extraHex": "", "width": 0, "height": 0, "sarNum": 1, "sarDen": 1, "fpsNum": 0, "fpsDen": 1,
             "sampleRate": 0, "channels": 0, "language": "", "title": "", "isDefault": False}
        t.update(kw)
        self.r["tracks"].append(t)

    def packet(self, track, pts, offset, size, key=True, duration=0):
        self.r["packets"].append({"track": track, "pts": pts, "dts": NO, "duration": duration, "key": key, "pos": offset, "size": size})

    def save(self, name):
        with open(os.path.join(out, name + ".ref.json"), "w") as fh:
            json.dump(self.r, fh, indent=1)


def frame(n, seed):
    return bytes((seed * 31 + k * 7) & 0xFF for k in range(n))


def block_header(track, offset, flags, simple=True):
    return vsize(track) + struct.pack(">h", offset) + bytes([flags])


def xiph_sizes(sizes):
    outb = b""
    for n in sizes:
        outb += b"\xff" * (n // 255) + bytes([n % 255])
    return outb


def ebml_lace(sizes):
    outb = vsize(sizes[0])
    for a, b in zip(sizes, sizes[1:]):
        d = b - a
        width = 1
        while not (-(1 << (7 * width - 1)) + 1 <= d <= (1 << (7 * width - 1)) - 1):
            width += 1
        outb += vsize(d + (1 << (7 * width - 1)) - 1, width)
    return outb


# ---------- features.mkv ----------
def features_mkv():
    ref = Ref("synth-mkv")
    # Tracks: 1 Xiph-laced AC-3, 2 EBML-laced AC-3, 3 fixed-laced AC-3,
    # 4 VP8 in BlockGroups, 5 header-stripped SRT, 6 zlib-compressed SRT,
    # 7 legacy AAC with SBR (no CodecPrivate), 8 vorbis? no: MS/ACM mp3.
    dd = u(0x23E383, 32000000)
    audio = el(0xE1, f(0xB5, 48000.0) + u(0x9F, 2))
    t1 = el(0xAE, u(0xD7, 1) + u(0x73C5, 101) + u(0x83, 2) + s(0x86, "A_AC3") + dd + audio + s(0x22B59C, "ger"))
    t2 = el(0xAE, u(0xD7, 2) + u(0x73C5, 102) + u(0x83, 2) + s(0x86, "A_AC3") + dd + audio + s(0x22B59D, "fr-CA") + u(0x88, 0))
    t3 = el(0xAE, u(0xD7, 3) + u(0x73C5, 103) + u(0x83, 2) + s(0x86, "A_AC3") + dd + audio + u(0x55AA, 1) + s(0x536E, "Fixed"))
    video = el(0xE0, u(0xB0, 64) + u(0xBA, 48) + u(0x54B0, 4) + u(0x54BA, 3))
    t4 = el(0xAE, u(0xD7, 4) + u(0x73C5, 104) + u(0x83, 1) + s(0x86, "V_VP8") + u(0x23E383, 40000000) + video)
    strip = b"Hi: "
    enc = el(0x6D80, el(0x6240, u(0x5032, 1) + u(0x5033, 0) + el(0x5034, u(0x4254, 3) + el(0x4255, strip))))
    t5 = el(0xAE, u(0xD7, 5) + u(0x73C5, 105) + u(0x83, 0x11) + s(0x86, "S_TEXT/UTF8") + enc)
    encz = el(0x6D80, el(0x6240, el(0x5034, u(0x4254, 0))))
    t6 = el(0xAE, u(0xD7, 6) + u(0x73C5, 106) + u(0x83, 0x11) + s(0x86, "S_TEXT/UTF8") + encz)
    t7 = el(0xAE, u(0xD7, 7) + u(0x73C5, 107) + u(0x83, 2) + s(0x86, "A_AAC/MPEG4/LC/SBR") + el(0xE1, f(0xB5, 24000.0) + f(0x78B5, 48000.0) + u(0x9F, 2)))
    wfx = struct.pack("<HHIIHHH", 0x55, 2, 44100, 16000, 1, 0, 0)
    t8 = el(0xAE, u(0xD7, 8) + u(0x73C5, 108) + u(0x83, 2) + s(0x86, "A_MS/ACM") + el(0x63A2, wfx) + el(0xE1, f(0xB5, 44100.0) + u(0x9F, 2)))
    tracks = el(0x1654AE6B, t1 + t2 + t3 + t4 + t5 + t6 + t7 + t8)
    info = el(0x1549A966, u(0x2AD7B1, 1000000) + f(0x4489, 2000.0) + s(0x7BA9, "Features") + s(0x4D80, "synth.py"))
    tags = el(0x1254C367,
              el(0x7373, el(0x63C0, u(0x68CA, 50)) + el(0x67C8, s(0x45A3, "ARTIST") + s(0x4487, "Reel")) + el(0x67C8, s(0x45A3, "DATE_RELEASED") + s(0x4487, "2026")))
              + el(0x7373, el(0x63C0, u(0x63C5, 104)) + el(0x67C8, s(0x45A3, "DURATION") + s(0x4487, "00:00:01.500000000"))))
    def atom(uid, start, end, title, hidden=False, children=b""):
        body = u(0x73C4, uid) + u(0x91, start) + (u(0x92, end) if end is not None else b"") + (u(0x98, 1) if hidden else b"")
        return el(0xB6, body + el(0x80, s(0x85, title) + s(0x437C, "eng")) + children)
    chapters = el(0x1043A770,
                  el(0x45B9, u(0x45BC, 1) + atom(9, 0, 500000000, "Other edition"))
                  + el(0x45B9, u(0x45BC, 2) + u(0x45DB, 1) + atom(1, 0, 1000000000, "One", children=atom(2, 250000000, 500000000, "One.a")) + atom(3, 1000000000, None, "Two") + atom(4, 1500000000, None, "Hidden", hidden=True)))
    png = b"\x89PNG\r\n\x1a\n" + b"fakepng" * 10
    attach = el(0x1941A469, el(0x61A7, s(0x466E, "font.ttf") + s(0x4660, "font/ttf") + el(0x465C, b"FONT" * 8) + u(0x46AE, 1))
                + el(0x61A7, s(0x466E, "cover.png") + s(0x4660, "image/png") + el(0x465C, png) + u(0x46AE, 2)))
    head = info + tracks + tags + chapters + attach
    seg_body_start_prefix = ebml_header("matroska")
    # Clusters are built with knowledge of absolute offsets.
    clusters = []
    pos0 = len(seg_body_start_prefix) + 12 + len(head)   # Segment ID 4 + size 8 bytes
    cur = pos0
    cluster_offsets = []

    def cluster(time, children_fn):
        nonlocal cur
        cluster_offsets.append(cur - (len(seg_body_start_prefix) + 12))
        # Cluster ID 4 bytes + 8-byte size, so the body start is known.
        body_start = cur + 4 + 8
        body = children_fn(body_start)
        c = vid(0x1F43B675) + vsize(len(body), 8) + body
        cur += len(c)
        clusters.append(c)

    def c1(at):
        b = u(0xE7, 0)
        # Track 1: Xiph lacing, 3 frames (one bigger than 255).
        sizes = [300, 17, 40]
        hdr = block_header(1, 0, 0x80 | 0x02) + bytes([len(sizes) - 1]) + xiph_sizes(sizes[:-1])
        data = b"".join(frame(n, i) for i, n in enumerate(sizes))
        body = hdr + data
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(body)))
        o = sb_body + len(hdr)
        for k, n in enumerate(sizes):
            ref.packet(0, 0 + 32 * k, o, n, True, 32)
            o += n
        b += el(0xA3, body)
        # Track 2: EBML lacing, 4 frames.
        sizes = [100, 90, 300, 5]
        hdr = block_header(2, 10, 0x80 | 0x06) + bytes([len(sizes) - 1]) + ebml_lace(sizes[:-1])
        data = b"".join(frame(n, i + 9) for i, n in enumerate(sizes))
        body = hdr + data
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(body)))
        o = sb_body + len(hdr)
        for k, n in enumerate(sizes):
            ref.packet(1, 10 + 32 * k, o, n, True, 32)
            o += n
        b += el(0xA3, body)
        # Track 3: fixed lacing, 3 frames of 50.
        hdr = block_header(3, 20, 0x80 | 0x04) + bytes([2])
        body = hdr + frame(150, 3)
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(body)))
        o = sb_body + len(hdr)
        for k in range(3):
            ref.packet(2, 20 + 32 * k, o + 50 * k, 50, True, 32)
        b += el(0xA3, body)
        # Track 4: a keyframe BlockGroup (no ReferenceBlock) and one with.
        for i, (t, refb) in enumerate([(0, None), (40, -40)]):
            blk = block_header(4, t, 0) + frame(60, 20 + i)
            inner = el(0xA1, blk) + (el(0xFB, struct.pack(">b", refb)) if refb is not None else b"")
            grp_body = at + len(b) + len(vid(0xA0)) + len(vsize(len(inner)))
            blk_body = grp_body + len(vid(0xA1)) + len(vsize(len(blk)))
            ref.packet(3, t, blk_body + 4, 60, refb is None, 40)
            b += el(0xA0, inner)
        # Track 5: header-stripped subtitle with a BlockDuration.
        blk = block_header(5, 100, 0) + b"there"
        inner = el(0xA1, blk) + u(0x9B, 900)
        grp_body = at + len(b) + len(vid(0xA0)) + len(vsize(len(inner)))
        ref.packet(4, 100, grp_body + len(vid(0xA1)) + len(vsize(len(blk))) + 4, 5, True, 900)
        b += el(0xA0, inner)
        # Track 6: zlib frame (listed, codec unknown:zlib).
        z = zlib.compress(b"compressed text")
        blk = block_header(6, 100, 0x80) + z
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(blk)))
        ref.packet(5, 100, sb_body + 4, len(z), True, 0)
        b += el(0xA3, blk)
        # Track 7: AAC (1024 samples at the 24 kHz core rate = 42 ms).
        blk = block_header(7, 0, 0x80) + frame(30, 7)
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(blk)))
        ref.packet(6, 0, sb_body + 4, 30, True, 42)
        b += el(0xA3, blk)
        # Track 8: an MP3 frame header (MPEG-1 layer III: 1152 samples).
        mp3 = bytes([0xFF, 0xFB, 0x90, 0x64]) + frame(40, 8)
        blk = block_header(8, 0, 0x80) + mp3
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(blk)))
        ref.packet(7, 0, sb_body + 4, len(mp3), True, 26)
        b += el(0xA3, blk)
        return b

    def c2(at):
        b = u(0xE7, 1000)
        # A negative block offset and a 2-byte track number vint.
        blk = vsize(4, 2) + struct.pack(">h", -5) + bytes([0x00]) + frame(33, 44)
        sb_body = at + len(b) + len(vid(0xA3)) + len(vsize(len(blk)))
        ref.packet(3, 995, sb_body + 5, 33, False, 40)
        b += el(0xA3, blk)
        # A block for a track that doesn't exist (skipped, with a warning).
        b += el(0xA3, block_header(9, 0, 0x80) + b"zz")
        return b

    cluster(0, c1)
    cluster(1000, c2)
    # Cues: one right, one pointing nowhere.
    cues = el(0x1C53BB6B, el(0xBB, u(0xB3, 0) + el(0xB7, u(0xF7, 1) + u(0xF1, cluster_offsets[0])))
              + el(0xBB, u(0xB3, 1000) + el(0xB7, u(0xF7, 1) + u(0xF1, 12345))))
    body = head + b"".join(clusters) + cues
    data = seg_body_start_prefix + vid(0x18538067) + vsize(len(body), 8) + body
    with open(os.path.join(out, "features.mkv"), "wb") as fh:
        fh.write(data)
    ref.r["duration"] = 2.0
    ref.r["tags"] = {"title": "Features", "artist": "Reel", "date": "2026"}
    ref.track(kind="audio", codec="ac3", sampleRate=48000, channels=2, language="ger", isDefault=True)
    ref.track(kind="audio", codec="ac3", sampleRate=48000, channels=2, language="fre", isDefault=False)
    ref.track(kind="audio", codec="ac3", sampleRate=48000, channels=2, language="eng", isDefault=True, title="Fixed")
    ref.track(kind="video", codec="vp8", width=64, height=48, sarNum=1, sarDen=1, fpsNum=25, fpsDen=1, language="eng", isDefault=True, duration=1500)
    ref.track(kind="subtitle", codec="srt", language="eng", isDefault=True)
    ref.track(kind="subtitle", codec="unknown:zlib", language="eng", isDefault=True)
    ref.track(kind="audio", codec="aac", sampleRate=48000, channels=2, language="eng", isDefault=True, extraHex="131056e598")
    ref.track(kind="audio", codec="mp3", sampleRate=44100, channels=2, language="eng", isDefault=True)
    # 64x48 shown at 4:3 is square pixels.
    ref.r["chapters"] = [{"start": 0.0, "end": 1.0, "title": "One"}, {"start": 0.25, "end": 0.5, "title": "One.a"}, {"start": 1.0, "end": -1.0, "title": "Two"}]
    ref.save("features.mkv")


# ---------- live.webm: unknown sizes ----------
def live_webm():
    ref = Ref("synth-webm")
    head = ebml_header("webm")
    tracks = el(0x1654AE6B, el(0xAE, u(0xD7, 1) + u(0x73C5, 1) + u(0x83, 1) + s(0x86, "V_VP9") + u(0x23E383, 33333333) + el(0xE0, u(0xB0, 32) + u(0xBA, 32) + u(0x54B0, 64) + u(0x54BA, 32))))
    info = el(0x1549A966, u(0x2AD7B1, 1000000))
    seg = vid(0x18538067) + UNKNOWN
    data = head + seg + info + tracks
    n = 0
    for c in range(3):
        data += vid(0x1F43B675) + UNKNOWN + u(0xE7, c * 100)
        for k in range(3):
            fr = frame(20 + k + c, c * 3 + k)
            blk = block_header(1, k * 33, 0x80 if k == 0 else 0) + fr
            sb = vid(0xA3) + vsize(len(blk))
            ref.packet(0, c * 100 + k * 33, len(data) + len(sb) + 4, len(fr), k == 0, 33)
            data += sb + blk
            n += 1
    with open(os.path.join(out, "live.webm"), "wb") as fh:
        fh.write(data)
    ref.r["duration"] = (200 + 66 + 33) / 1000.0
    ref.track(kind="video", codec="vp9", width=32, height=32, sarNum=2, sarDen=1, fpsNum=30, fpsDen=1, language="eng", isDefault=True)
    ref.save("live.webm")


# ---------- damaged.mkv: garbage between clusters ----------
def damaged_mkv():
    ref = Ref("synth-mkv")
    head = ebml_header("matroska")
    tracks = el(0x1654AE6B, el(0xAE, u(0xD7, 1) + u(0x83, 2) + s(0x86, "A_AC3") + u(0x23E383, 32000000) + el(0xE1, f(0xB5, 48000.0) + u(0x9F, 2))))
    body = tracks
    base = len(head) + 12
    def cl(t, fr):
        nonlocal body
        cbody = u(0xE7, t)
        blk = block_header(1, 0, 0x80) + fr
        at = base + len(body) + 12 + len(cbody) + len(vid(0xA3)) + len(vsize(len(blk))) + 4
        ref.packet(0, t, at, len(fr), True, 32)
        cbody += el(0xA3, blk)
        body += vid(0x1F43B675) + vsize(len(cbody), 8) + cbody
    cl(0, frame(10, 1))
    body += b"\x00\x00\x07garbage\x00"
    cl(32, frame(11, 2))
    data = head + vid(0x18538067) + vsize(len(body), 8) + body
    with open(os.path.join(out, "damaged.mkv"), "wb") as fh:
        fh.write(data)
    ref.r["duration"] = 0.064
    ref.track(kind="audio", codec="ac3", sampleRate=48000, channels=2, language="eng", isDefault=True)
    ref.save("damaged.mkv")


# ---------- Ogg ----------
def crc32_ogg(data):
    crc = 0
    for b in data:
        crc ^= b << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return crc


class OggWriter:
    def __init__(self, serial):
        self.serial = serial
        self.seq = 0
        self.data = b""

    def page(self, segments_payload, lacing, granule, flags, break_crc=False):
        hdr = b"OggS" + bytes([0, flags]) + struct.pack("<qII", granule, self.serial, self.seq) + b"\0\0\0\0" + bytes([len(lacing)]) + bytes(lacing)
        page = hdr + segments_payload
        crc = crc32_ogg(page)
        if break_crc:
            crc ^= 1
        page = page[:22] + struct.pack("<I", crc) + page[26:]
        self.seq += 1
        start = len(self.data)
        self.data += page
        return start, start + len(hdr)

    def packets_page(self, packets, granule, flags=0, break_crc=False):
        # Whole packets on one page; returns each packet's body offset.
        lacing = []
        for p in packets:
            lacing += [255] * (len(p) // 255) + [len(p) % 255]
        start, body = self.page(b"".join(packets), lacing, granule, flags, break_crc)
        offs = []
        o = body
        for p in packets:
            offs.append(o)
            o += len(p)
        return start, offs


def comment_packet(prefix, tags, framing=False):
    vendor = b"synth"
    body = prefix + struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(tags))
    for t in tags:
        tb = t.encode()
        body += struct.pack("<I", len(tb)) + tb
    if framing:
        body += b"\x01"
    return body


def theora_ogv():
    ref = Ref("synth-ogg")
    w = OggWriter(77)
    ident = bytearray(42)
    ident[0:7] = b"\x80theora"
    ident[7:10] = bytes([3, 2, 1])
    ident[10:12] = struct.pack(">H", 4)        # 64 px wide in macroblocks
    ident[12:14] = struct.pack(">H", 3)
    ident[14:17] = (64).to_bytes(3, "big")
    ident[17:20] = (48).to_bytes(3, "big")
    ident[22:26] = struct.pack(">I", 25)
    ident[26:30] = struct.pack(">I", 1)
    ident[30:33] = (1).to_bytes(3, "big")
    ident[33:36] = (1).to_bytes(3, "big")
    shift = 6
    ident[40] = (shift >> 3) & 3
    ident[41] = (shift & 7) << 5
    comment = comment_packet(b"\x81theora", ["TITLE=Theora Test", "ARTIST=Reel"])
    setup = b"\x82theora" + b"\x00" * 20
    w.packets_page([bytes(ident)], 0, 2)
    w.packets_page([comment, setup], 0)
    # Frames: keyframe every 4; granule = key << shift | since-key, counted
    # from 1 (Theora 3.2.1).
    frames = []
    for i in range(10):
        key = i % 4 == 0
        frames.append(bytes([0x00 if key else 0x40]) + frame(30 + i, i))
    def gran(i):  # granule of frame i (0-based)
        k = (i // 4) * 4
        return ((k + 1) << shift) | (i - k)
    pages = [[0, 1, 2], [3, 4], [5, 6, 7, 8]]
    for pi, idx in enumerate(pages):
        start, offs = w.packets_page([frames[i] for i in idx], gran(idx[-1]), 0, break_crc=(pi == 1))
        for i, o in zip(idx, offs):
            ref.packet(0, i, o, len(frames[i]), i % 4 == 0, 1)
    # Frame 9: one big packet across three pages (continued pages).
    big = bytes([0x40]) + frame(140000, 99)
    chunks = [big[:255 * 255], big[255 * 255:2 * 255 * 255], big[2 * 255 * 255:]]
    parts = []
    s1, b1 = w.page(chunks[0], [255] * 255, -1, 0)
    s2, b2 = w.page(chunks[1], [255] * 255, -1, 1)
    last = chunks[2]
    s3, b3 = w.page(last, [255] * (len(last) // 255) + [len(last) % 255], gran(9), 1 | 4)
    ref.packet(0, 9, b1, len(big), False, 1)
    with open(os.path.join(out, "theora.ogv"), "wb") as fh:
        fh.write(w.data)
    ref.r["duration"] = 10 / 25.0
    ref.r["tags"] = {"title": "Theora Test", "artist": "Reel"}
    core = b"".join(struct.pack(">I", len(h)) + h for h in [bytes(ident), comment, setup])
    ref.track(kind="video", codec="theora", timescale=25, duration=10, width=64, height=48, fpsNum=25, fpsDen=1, extraHex=core.hex(), title="Theora Test")
    ref.save("theora.ogv")


def cover_opus():
    ref = Ref("synth-ogg")
    w = OggWriter(5)
    head = b"OpusHead" + bytes([1, 2]) + struct.pack("<HIhB", 100, 48000, 0, 0)
    jpeg = b"\xff\xd8\xff\xe0" + frame(100, 5) + b"\xff\xd9"
    pic = struct.pack(">I", 3) + struct.pack(">I", 10) + b"image/jpeg" + struct.pack(">I", 0) + struct.pack(">IIII", 1, 1, 24, 0) + struct.pack(">I", len(jpeg)) + jpeg
    tags = comment_packet(b"OpusTags", ["TITLE=Cover", "TRACKNUMBER=3", "METADATA_BLOCK_PICTURE=" + base64.b64encode(pic).decode()])
    w.packets_page([head], 0, 2)
    w.packets_page([tags], 0)
    # CELT 20 ms frames (config 31, code 0: 960 samples) and one code-3
    # packet of 3 × 10 ms frames (config 30: 480 each).
    pk = [bytes([31 << 3]) + frame(20, i) for i in range(3)] + [bytes([(30 << 3) | 3, 3]) + frame(20, 9)]
    total = 960 * 3 + 1440
    start, offs = w.packets_page(pk, total, 4)
    t = -100
    for p, o, d in zip(pk, offs, [960, 960, 960, 1440]):
        ref.packet(0, t, o, len(p), True, d)
        t += d
    with open(os.path.join(out, "cover.opus vorbis_blocks.ogg"), "wb") as fh:
        fh.write(w.data)
    ref.r["duration"] = total / 48000.0
    ref.r["tags"] = {"title": "Cover", "track": "3"}
    ref.track(kind="audio", codec="opus", timescale=48000, duration=total, sampleRate=48000, channels=2, extraHex=head.hex(), title="Cover")
    ref.save("cover.opus vorbis_blocks.ogg")
    with open(os.path.join(out, "cover.opus.jpg"), "wb") as fh:
        fh.write(jpeg)


features_mkv()
live_webm()
damaged_mkv()
theora_ogv()
cover_opus()

def vorbis_blocks_ogg():
    # A Vorbis stream with short (256) and long (2048) blocks: the setup
    # header is filler bits ending in a real mode section (2 modes: block
    # flags 0 and 1), so packet lengths need the modes read from its end.
    ref = Ref("synth-ogg")
    w = OggWriter(9)
    ident = b"\x01vorbis" + struct.pack("<IBIiii", 0, 2, 44100, 0, 128000, 0) + bytes([(11 << 4) | 8, 1])
    comment = comment_packet(b"\x03vorbis", ["ARTIST=Reel"], framing=True)
    bits = []
    def put(v, n):
        for k in range(n):
            bits.append((v >> k) & 1)
    seed = 12345
    for _ in range(300):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        put(seed >> 16, 8)
    put(1, 6)                     # mode count - 1
    for flag in (0, 1):
        put(flag, 1); put(0, 16); put(0, 16); put(0, 8)
    put(1, 1)                     # framing bit
    while len(bits) % 8:
        bits.append(0)
    setup = b"\x05vorbis" + bytes(sum(bits[i + k] << k for k in range(8)) for i in range(0, len(bits), 8))
    w.packets_page([ident], 0, 2)
    w.packets_page([comment, setup], 0)
    modes = [1, 1, 0, 0, 1, 0, 1, 1]
    blocks = [256, 2048]
    prev = 2048
    durs = []
    for m in modes:
        cur = blocks[m]
        durs.append((prev + cur) // 4)
        prev = cur
    pk = [bytes([m << 1]) + frame(20, i) for i, m in enumerate(modes)]
    g1 = sum(durs[1:4])
    _, offs1 = w.packets_page(pk[:4], g1)
    end = g1 + sum(durs[4:]) - 100
    _, offs2 = w.packets_page(pk[4:], end, 4)
    t = g1 - sum(durs[:4])
    for i, (p, o) in enumerate(zip(pk, offs1 + offs2)):
        d = durs[i] - (100 if i == len(pk) - 1 else 0)
        ref.packet(0, t, o, len(p), True, d)
        t += durs[i]
    with open(os.path.join(out, "vorbis_blocks.ogg"), "wb") as fh:
        fh.write(w.data)
    ref.r["duration"] = end / 44100.0
    core = b"".join(struct.pack(">I", len(h)) + h for h in [ident, comment, setup])
    ref.track(kind="audio", codec="vorbis", timescale=44100, duration=end, sampleRate=44100, channels=2, extraHex=core.hex())
    ref.save("vorbis_blocks.ogg")


vorbis_blocks_ogg()
print("synth: made features.mkv live.webm damaged.mkv theora.ogv cover.opus vorbis_blocks.ogg")
