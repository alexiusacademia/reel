# Builds damaged and unusual variants of small container files for
# tests/demux_c, which ffmpeg doesn't write itself:
#   avi-noidx   SRC DST   idx1 renamed to JUNK (the demuxer must scan movi)
#   avi-absidx  SRC DST   idx1 offsets counted from the file's start
#   avi-odml    SRC DST   OpenDML: indx super indexes, ix## standard
#                         indexes, the second half of the chunks in a
#                         RIFF 'AVIX'
#   ts-junk     SRC DST   garbage bytes between two TS packets (lost sync)
#   ts-204      SRC DST   204-byte packets (16 parity bytes after each)
#
# Author: Alexius Academia
# Date: 2026-10-25
import struct, sys

def chunks(d, a, b):
    out = []
    while a + 8 <= b:
        cc = d[a:a+4]; sz = struct.unpack('<I', d[a+4:a+8])[0]
        out.append((a, cc, sz))
        a += 8 + sz + (sz & 1)
    return out

def find(d, a, b, cc, kind=None):
    for (p, c, sz) in chunks(d, a, b):
        if c == cc and (kind is None or d[p+8:p+12] == kind):
            return p, sz
    raise SystemExit("no %r" % cc)

def avi_parts(d):
    riff_end = 8 + struct.unpack('<I', d[4:8])[0]
    hdrl, hsz = find(d, 12, riff_end, b'LIST', b'hdrl')
    movi, msz = find(d, 12, riff_end, b'LIST', b'movi')
    idx1, isz = find(d, 12, riff_end, b'idx1')
    return riff_end, hdrl, hsz, movi, msz, idx1, isz

def noidx(d):
    _, _, _, _, _, idx1, _ = avi_parts(d)
    return d[:idx1] + b'JUNK' + d[idx1+4:]

def absidx(d):
    _, _, _, movi, _, idx1, isz = avi_parts(d)
    out = bytearray(d)
    base = movi + 8
    for k in range(isz // 16):
        e = idx1 + 8 + k * 16
        off = struct.unpack('<I', d[e+8:e+12])[0]
        out[e+8:e+12] = struct.pack('<I', off + base)
    return bytes(out)

def odml(d):
    riff_end, hdrl, hsz, movi, msz, idx1, isz = avi_parts(d)
    # The data chunks in order, with their idx1 flags.
    entries = []
    for k in range(isz // 16):
        e = idx1 + 8 + k * 16
        cc = d[e:e+4]; flags, off, size = struct.unpack('<III', d[e+4:e+16])
        entries.append((cc, flags, movi + 8 + off, size))
    nstreams = len({cc[:2] for (cc, _, _, _) in entries})
    half = len(entries) // 2
    groups = [entries[:half], entries[half:]]

    def movi_list(group, base):
        # LIST movi with the group's chunks, then one ix## per stream.
        body = bytearray(b'movi')
        where = []
        for (cc, flags, at, size) in group:
            pos = base + 8 + len(body)
            body += cc + struct.pack('<I', size) + d[at+8:at+8+size]
            if size & 1: body += b'\0'
            where.append((cc, flags, pos + 8, size))
        ix = []
        for s in range(nstreams):
            mine = [w for w in where if int(w[0][:2]) == s]
            if not mine: ix.append(None); continue
            cid = mine[0][0]
            qbase = min(w[2] for w in mine)
            ent = b''.join(struct.pack('<II', w[2] - qbase, w[3] | (0 if w[1] & 0x10 else 0x80000000)) for w in mine)
            head = struct.pack('<HBBI', 2, 0, 1, len(mine)) + cid + struct.pack('<QI', qbase, 0)
            ixc = ('ix%02d' % s).encode() + struct.pack('<I', len(head) + len(ent)) + head + ent
            ix.append((base + 8 + len(body), len(ixc), len(mine)))
            body += ixc
        return b'LIST' + struct.pack('<I', len(body)) + bytes(body), ix

    # First RIFF: everything before movi (hdrl with indx in place of the
    # strl JUNK), movi with the first half, idx1 of the first half.
    pre = bytearray(d[12:movi])
    movi1, ix1 = movi_list(groups[0], movi)
    idx = bytearray()
    for (cc, flags, at, size) in groups[0]:
        pass
    # Offsets of idx1 entries are from the 'movi' fourcc.
    p = 4
    for (cc, flags, at, size) in groups[0]:
        idx += cc + struct.pack('<III', flags, p, size)
        p += 8 + size + (size & 1)
    idx1c = b'idx1' + struct.pack('<I', len(idx)) + bytes(idx)
    riff1_body = b'AVI ' + bytes(pre) + movi1 + idx1c
    riff1 = b'RIFF' + struct.pack('<I', len(riff1_body)) + riff1_body
    base2 = len(riff1) + 12
    movi2, ix2 = movi_list(groups[1], base2)
    riff2_body = b'AVIX' + movi2
    riff2 = b'RIFF' + struct.pack('<I', len(riff2_body)) + riff2_body
    out = bytearray(riff1 + riff2)
    # indx super indexes, written over each strl's JUNK.
    strls = [p for (p, c, sz) in chunks(d, hdrl + 12, hdrl + 8 + hsz) if c == b'LIST' and d[p+8:p+12] == b'strl']
    for s, sp in enumerate(strls):
        sz = struct.unpack('<I', d[sp+4:sp+8])[0]
        junk = [(p, c, z) for (p, c, z) in chunks(d, sp + 12, sp + 8 + sz) if c == b'JUNK'][0]
        jp, _, jz = junk
        cid = None
        for (cc, _, _, _) in entries:
            if int(cc[:2]) == s: cid = cc; break
        ents = [x[s] for x in (ix1, ix2) if x[s] is not None]
        body = struct.pack('<HBBI', 4, 0, 0, len(ents)) + cid + b'\0' * 12
        for (off, size, n) in ents:
            body += struct.pack('<QII', off, size, n)
        body = body.ljust(jz, b'\0')
        at = jp - 12 + 12   # same place in the new file (pre starts at 12)
        out[at:at+8+jz] = b'indx' + struct.pack('<I', jz) + body
    # dmlh: total frames (put in the hdrl JUNK after the strls if any).
    return bytes(out)

def ts_junk(d):
    at = 188 * 40
    return d[:at] + bytes(range(7, 7 + 61)) + d[at:]

def ts_204(d):
    out = bytearray()
    for i in range(0, len(d) - 187, 188):
        out += d[i:i+188] + b'\xff' * 16
    return bytes(out)

op, src, dst = sys.argv[1:4]
data = open(src, 'rb').read()
fn = {'avi-noidx': noidx, 'avi-absidx': absidx, 'avi-odml': odml, 'ts-junk': ts_junk, 'ts-204': ts_204}[op]
open(dst, 'wb').write(fn(data))
