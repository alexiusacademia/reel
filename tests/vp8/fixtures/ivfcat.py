# Joins IVF files into one (the first file's header, every file's frames,
# the frame count fixed up). Used by make.sh for a size change mid-stream.
#
# Author: Alexius Academia
# Date: 2026-10-25
import struct, sys
out = bytearray()
frames = 0
for i, path in enumerate(sys.argv[1:-1]):
    d = open(path, 'rb').read()
    hs = struct.unpack('<H', d[6:8])[0]
    if i == 0:
        out += d[:hs]
    p = hs
    while p + 12 <= len(d):
        sz = struct.unpack('<I', d[p:p + 4])[0]
        out += struct.pack('<I', sz) + struct.pack('<Q', frames) + d[p + 12:p + 12 + sz]
        frames += 1
        p += 12 + sz
out[24:28] = struct.pack('<I', frames)
open(sys.argv[-1], 'wb').write(out)
