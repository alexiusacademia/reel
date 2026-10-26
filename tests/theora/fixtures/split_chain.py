# Splits a chained Ogg file into its links (a new link starts at a BOS
# page after an EOS). Usage: split_chain.py in.ogg outprefix
# Author: Alexius Academia
# Date: 2026-10-25
import sys
d = open(sys.argv[1], 'rb').read()
links = []
cur = bytearray()
open_streams = set()
seen_eos = False
p = 0
while p + 27 <= len(d) and d[p:p+4] == b'OggS':
    flags = d[p+5]
    serial = int.from_bytes(d[p+14:p+18], 'little')
    nseg = d[p+26]
    size = 27 + nseg + sum(d[p+27:p+27+nseg])
    page = d[p:p+size]
    if flags & 2 and not open_streams and cur:
        links.append(bytes(cur)); cur = bytearray()
    if flags & 2:
        open_streams.add(serial)
    cur += page
    if flags & 4:
        open_streams.discard(serial)
    p += size
if cur:
    links.append(bytes(cur))
for i, l in enumerate(links):
    open(f"{sys.argv[2]}{i}.ogg", 'wb').write(l)
print(len(links), "links")
