#!/bin/bash
# Downloads the Theora samples tests/theora decodes into
# build/conformance/vp8theora/theora and makes ffmpeg's framemd5 for each:
# the FATE samples (vp3/, ogg/), the Xiph Theora test suite (from the Web
# Archive's copy of v2v.cc/~j/theora_testsuite), and a 240-frame cut of
# the 1080p Big Buck Bunny Theora (from the start of Blender's zip, which
# stores the file uncompressed). Chained Ogg links get one framemd5 each.
#
# Author: Alexius Academia
# Date: 2026-10-25

cd "$(dirname "$0")/../../.."
C=build/conformance/vp8theora/theora
mkdir -p "$C"
for f in vp3/coeff_level64.mkv vp3/offset_test.ogv ogg/bear.ogv ogg/empty_theora_packets.ogv; do
    [ -f "$C/$(basename $f)" ] || curl -sfL -o "$C/$(basename $f)" "https://fate-suite.ffmpeg.org/$f"
done
for f in 320x240.ogg pixel_aspect_ratio.ogg videotestsrc-720x576-16-15.ogg \
         322x242_not-divisible-by-sixteen-framesize.ogg chained_streams.ogg multi2.ogg \
         mobile_itu601_i_422.ogg stockholm-vfr.ogg ducks_take_off_444_720p25.ogg sign_irene_cif-3qi-b.ogg; do
    [ -f "$C/$f" ] || curl -sfL -o "$C/$f" "http://web.archive.org/web/2009id_/http://v2v.cc/~j/theora_testsuite/$f"
done
if [ ! -f "$C/bbb_1080p_cut.ogg" ]; then
    tmp=$(mktemp -d)
    curl -sL https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_1080p_stereo.ogg.zip | head -c 20000000 > "$tmp/head.zip"
    # A stored zip entry: 30-byte local header + name, then the file.
    python3 -I -c "
import struct,sys
d=open(sys.argv[1],'rb').read()
n,e=struct.unpack('<HH',d[26:30])
open(sys.argv[2],'wb').write(d[30+n+e:])" "$tmp/head.zip" "$tmp/cut.ogg"
    ffmpeg -v error -i "$tmp/cut.ogg" -map 0:v:0 -c copy -frames:v 240 -y "$C/bbb_1080p_cut.ogg"
    rm -rf "$tmp"
fi
for f in "$C"/*.ogg "$C"/*.ogv "$C"/*.mkv tests/theora/fixtures/*.ogg tests/theora/fixtures/*.mkv; do
    [ -f "$f.framemd5" ] || ffmpeg -v quiet -threads 1 -i "$f" -map 0:v:0 -fps_mode passthrough -f framemd5 -y "$f.framemd5"
done
if [ ! -f "$C/chained_streams.ogg.link0.framemd5" ]; then
    tmp=$(mktemp -d)
    python3 -I tests/theora/fixtures/split_chain.py "$C/chained_streams.ogg" "$tmp/link"
    for l in "$tmp"/link*.ogg; do
        i=$(basename "$l" .ogg | sed 's/link//')
        ffmpeg -v quiet -threads 1 -i "$l" -map 0:v:0 -fps_mode passthrough -f framemd5 -y "$C/chained_streams.ogg.link$i.framemd5"
    done
    rm -rf "$tmp"
fi
echo "done: $(ls "$C" | wc -l) files in $C"
