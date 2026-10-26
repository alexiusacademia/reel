# Makes ASF variants for tests/asf from a file ffmpeg wrote, for things
# ffmpeg's ASF muxer can't write:
#   cover SRC DST JPEG   adds a WM/Picture (cover art) to the extended
#                        content description object
#   drm SRC DST          adds a content encryption object (a DRM file)
#   noindex SRC DST      drops the objects after the data object (index)
#   cut SRC DST N        keeps only the first N bytes (a damaged download)
#
# Author: Alexius Academia
# Date: 2026-10-25
import struct, sys, uuid

HEADER = bytes.fromhex("3026B2758E66CF11A6D900AA0062CE6C")
DATA = bytes.fromhex("3626B2758E66CF11A6D900AA0062CE6C")
EXT_CONTENT = bytes.fromhex("40A4D0D207E3D21197F000A0C95EA850")
ENCRYPTION = bytes.fromhex("FBB3112223BDD211B4B700A0C955FC6E")


def utf16z(s):
    return s.encode("utf-16-le") + b"\0\0"


def split(asf):
    assert asf[:16] == HEADER
    size, count = struct.unpack_from("<QI", asf, 16)
    objs, at = [], 30
    while at < size:
        osize = struct.unpack_from("<Q", asf, at + 16)[0]
        objs.append(asf[at:at + osize])
        at += osize
    return objs, asf[size:]


FILE_PROPS = bytes.fromhex("A1DCAB8C47A9CF118EE400C00C205365")


def join(objs, rest, reserved=b"\x01\x02"):
    # The file properties' file size follows the new length (a tagger
    # rewriting the header does the same).
    size = 30 + sum(len(o) for o in objs) + len(rest)
    objs = [o[:40] + struct.pack("<Q", size) + o[48:] if o[:16] == FILE_PROPS else o for o in objs]
    body = b"".join(objs)
    return HEADER + struct.pack("<QI", 30 + len(body), len(objs)) + reserved + body + rest


def cover(src, dst, jpeg):
    asf = open(src, "rb").read()
    pic = open(jpeg, "rb").read()
    objs, rest = split(asf)
    value = bytes([3]) + struct.pack("<I", len(pic)) + utf16z("image/jpeg") + utf16z("Front") + pic
    name = utf16z("WM/Picture")
    desc = struct.pack("<H", len(name)) + name + struct.pack("<HH", 1, len(value)) + value
    for i, o in enumerate(objs):
        if o[:16] == EXT_CONTENT:
            n = struct.unpack_from("<H", o, 24)[0]
            body = struct.pack("<H", n + 1) + o[26:] + desc
            objs[i] = EXT_CONTENT + struct.pack("<Q", 24 + len(body)) + body
            break
    else:
        body = struct.pack("<H", 1) + desc
        objs.append(EXT_CONTENT + struct.pack("<Q", 24 + len(body)) + body)
    open(dst, "wb").write(join(objs, rest))


def drm(src, dst):
    asf = open(src, "rb").read()
    objs, rest = split(asf)
    def lstr(b):
        return struct.pack("<I", len(b)) + b
    body = lstr(b"\x11" * 8) + lstr(b"DRM\0") + lstr(b"key-id\0") + lstr(b"http://example.invalid/license\0")
    objs.append(ENCRYPTION + struct.pack("<Q", 24 + len(body)) + body)
    open(dst, "wb").write(join(objs, rest))


def noindex(src, dst):
    asf = open(src, "rb").read()
    objs, rest = split(asf)
    assert rest[:16] == DATA
    dsize = struct.unpack_from("<Q", rest, 16)[0]
    open(dst, "wb").write(asf[:len(asf) - len(rest)] + rest[:dsize])


def cut(src, dst, n):
    open(dst, "wb").write(open(src, "rb").read()[:int(n)])


op = sys.argv[1]
if op == "cover":
    cover(*sys.argv[2:5])
elif op == "drm":
    drm(*sys.argv[2:4])
elif op == "noindex":
    noindex(*sys.argv[2:4])
elif op == "cut":
    cut(*sys.argv[2:5])
