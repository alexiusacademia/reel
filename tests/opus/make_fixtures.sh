#!/bin/bash
# Makes the opus test's own clips with ffmpeg's libopus encoder, covering
# what tools/make_fixtures.sh doesn't: SILK-only narrowband/mediumband/
# wideband speech at low bitrates, 40 and 60 ms SILK frames, hybrid
# (super-wideband and fullband), CELT-only 2.5, 5 and 10 ms frames, and
# 5.1 surround with channel mapping family 1. Each clip X.opus gets X.s16:
# libopus's own decode (ffmpeg -c:a libopus, which drops the pre-skip),
# 16-bit little-endian at 48 kHz. Run from anywhere; takes a few seconds.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/fixtures"
q="-hide_banner -loglevel error -y"
# A voice-like source (a 180 Hz voice with vibrato and two harmonics) and
# a music-like one (a chord with a little noise).
voice() { echo "aevalsrc=0.3*sin(2*PI*(180+20*sin(2*PI*3*t))*t)+0.2*sin(2*PI*2*(180+20*sin(2*PI*3*t))*t)+0.1*sin(2*PI*3*(180+20*sin(2*PI*3*t))*t)+0.02*random(0)-0.01:s=48000:d=$1"; }
music() { echo "aevalsrc=0.2*sin(2*PI*262*t)+0.15*sin(2*PI*330*t)+0.12*sin(2*PI*392*t)+0.1*sin(2*PI*1568*t)*sin(2*PI*2*t)+0.03*random(0)-0.015:s=48000:d=$1"; }
st() { echo "[0][1]amerge=inputs=2"; }

ffmpeg $q -f lavfi -i "$(voice 1)" -c:a libopus -b:a 8k -application voip -cutoff 4000 silk_nb.opus
ffmpeg $q -f lavfi -i "$(voice 0.6)" -c:a libopus -b:a 12k -application voip -cutoff 6000 -frame_duration 40 silk_mb40.opus
ffmpeg $q -f lavfi -i "$(voice 0.6)" -f lavfi -i "$(music 0.6)" -filter_complex "$(st)" -c:a libopus -b:a 16k -application voip -cutoff 8000 -frame_duration 60 silk_wb60_stereo.opus
ffmpeg $q -f lavfi -i "$(voice 0.6)" -c:a libopus -b:a 24k -application voip -cutoff 12000 hybrid_swb.opus
ffmpeg $q -f lavfi -i "$(music 0.5)" -f lavfi -i "$(voice 0.5)" -filter_complex "$(st)" -c:a libopus -b:a 40k -application voip hybrid_fb_stereo.opus
for d in 2.5 5 10; do
    ffmpeg $q -f lavfi -i "$(music 0.3)" -f lavfi -i "$(voice 0.3)" -filter_complex "$(st)" -c:a libopus -b:a 96k -application lowdelay -frame_duration $d celt_${d/./_}ms.opus
done
ffmpeg $q -f lavfi -i "$(music 0.3)" -f lavfi -i "sine=frequency=550:sample_rate=48000:duration=0.3" -f lavfi -i "$(voice 0.3)" -f lavfi -i "sine=frequency=60:sample_rate=48000:duration=0.3" -f lavfi -i "sine=frequency=1200:sample_rate=48000:duration=0.3" -f lavfi -i "anoisesrc=d=0.3:c=pink:r=48000:a=0.1" -filter_complex "[0][1][2][3][4][5]amerge=inputs=6,aformat=channel_layouts=5.1" -c:a libopus -b:a 192k -mapping_family 1 surround51.opus
for f in *.opus; do
    ffmpeg $q -c:a libopus -i "$f" -f f32le "$f.tmp.f32"
    python3 -I - "$f.tmp.f32" "${f%.opus}.s16" <<'PY'
import sys, array
a = array.array('f'); a.frombytes(open(sys.argv[1], 'rb').read())
o = array.array('h', [max(-32768, min(32767, int(round(x * 32768)))) for x in a])
open(sys.argv[2], 'wb').write(o.tobytes())
PY
    rm "$f.tmp.f32"
done
# libopus's decode of the first second of two shared fixtures (the
# shared .a.f32 files are ffmpeg's own decoder's, and multi.mkv's has only
# its first audio track).
for pair in "multi.mkv 0:a:1 multi_opus_1s" "opus_mono.ogg 0:a:0 opus_mono_1s"; do
    set -- $pair
    ffmpeg $q -c:a libopus -i "../../fixtures/$1" -map "$2" -t 1 -f f32le "$3.tmp.f32"
    python3 -I - "$3.tmp.f32" "$3.s16" <<'PY'
import sys, array
a = array.array('f'); a.frombytes(open(sys.argv[1], 'rb').read())
o = array.array('h', [max(-32768, min(32767, int(round(x * 32768)))) for x in a])
open(sys.argv[2], 'wb').write(o.tobytes())
PY
    rm "$3.tmp.f32"
done
ls -la
