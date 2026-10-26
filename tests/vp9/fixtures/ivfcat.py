# Joins IVF files: the first file's header (frame count fixed up), then the
# frames of all of them with running timestamps. Used by make.sh.
#
# Author: Alexius Academia
# Date: 2026-10-25
import struct, sys
ins, out = sys.argv[1:-1], sys.argv[-1]
frames = []
header = None
for path in ins:
    d = open(path, 'rb').read()
    if header is None:
        header = bytearray(d[:32])
    at = struct.unpack('<H', d[6:8])[0]
    while at + 12 <= len(d):
        size = struct.unpack('<I', d[at:at + 4])[0]
        frames.append(d[at + 12:at + 12 + size])
        at += 12 + size
struct.pack_into('<I', header, 24, len(frames))
with open(out, 'wb') as f:
    f.write(header)
    for i, fr in enumerate(frames):
        f.write(struct.pack('<IQ', len(fr), i))
        f.write(fr)
