#!/bin/bash
# Makes the extra files tests/demux_c reads (small, into
# tests/demux_c/fixtures/) and their references (make_refs.py), and the
# big synthetic files for speed measurements (build/scratch/demux_c/,
# not kept). Run from anywhere; FORCE=1 remakes them.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/demux_c/fixtures
big=build/scratch/demux_c
mkdir -p "$out" "$big"
q="-hide_banner -loglevel error -y"
fx=tests/fixtures
v="-f lavfi -i testsrc2=size=96x64:rate=25:duration=1"
a="-f lavfi -i sine=frequency=440:sample_rate=44100:duration=1"
made=()

make() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    made+=("$out/$name")
}
variant() { # op source name
    if [ -f "$out/$3" ] && [ -z "$FORCE" ]; then return; fi
    python3 -I tests/demux_c/variants.py "$1" "$out/$2" "$out/$3"
    made+=("$out/$3")
}

# AVI: MPEG-4 with B-frames and VBR MP3; its index variants.
make small.avi $v $a -c:v mpeg4 -vtag XVID -bf 2 -g 10 -q:v 8 -c:a libmp3lame -b:a 64k
variant avi-noidx small.avi small_noidx.avi
variant avi-absidx small.avi small_absidx.avi
variant avi-odml small.avi small_odml.avi
# AVI with H.264 and 16-bit PCM, and with AC-3.
make h264_pcm.avi $v $a -c:v libx264 -pix_fmt yuv420p -g 12 -c:a pcm_s16le -metadata title="AVI Title" -metadata artist="Reel"
make ac3.avi $v $a -c:v mjpeg -c:a ac3 -b:a 96k

# TS: several audio codecs with languages; M2TS; HEVC;
# MPEG-4 Part 2; damaged sync; 204-byte packets; timestamps that wrap.
# (ffmpeg encodes DVB and DVD subtitles only from bitmaps, so there are
# no subtitle tracks here.)
make multi.ts $v $a -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=1" -map 0 -map 1 -map 2 -c:v libx264 -pix_fmt yuv420p -c:a:0 mp2 -c:a:1 eac3 -metadata:s:a:0 language=eng -metadata:s:a:1 language=fre
make small.m2ts $v $a -c:v libx264 -pix_fmt yuv420p -c:a ac3 -f mpegts -mpegts_m2ts_mode 1
make hevc.ts $v -c:v libx265 -x265-params log-level=error
make mpeg4.ts $v $a -c:v mpeg4 -bf 1 -c:a libmp3lame
make wrap.ts $v $a -c:v libx264 -pix_fmt yuv420p -c:a aac -output_ts_offset 95441.8
variant ts-junk multi.ts multi_junk.ts
variant ts-204 multi.ts multi_204.ts

# PS: DVD-style VOB with AC-3 (MPEG-2 packs), LPCM, and
# H.264 in a program stream.
make dvd.vob $v $a -c:v mpeg2video -c:a ac3 -f vob
make lpcm.vob $v $a -c:v mpeg2video -c:a pcm_dvd -f vob
make h264.mpg $v -c:v libx264 -pix_fmt yuv420p -f mpeg

for f in "${made[@]}"; do
    python3 -I tests/demux_c/make_refs.py "$f"
    echo "made $(basename "$f")"
done
for f in mjpeg.avi mjpeg422.avi mpeg4.avi h264.ts h264_interlaced.ts mpeg2.ts mpeg1.mpg mpeg2.mpg; do
    [ -f "$out/$f.hashes.json" ] && [ -z "$FORCE" ] && continue
    python3 -I tests/demux_c/make_refs.py "$fx/$f"
done

# Big files for speed (not compared packet by packet).
if [ ! -f "$big/big.ts" ]; then
    ffmpeg $q -stream_loop 1499 -i $fx/h264.ts -c copy -f mpegts "$big/big.ts"
    echo "made big.ts ($(du -h "$big/big.ts" | cut -f1))"
fi
