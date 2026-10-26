#!/bin/bash
# Makes the small ASF files tests/asf reads (tests/asf/fixtures/) with
# ffmpeg's ASF muxer and tests/asf/variants.py, and ffprobe's answers for
# them and for the downloaded samples in build/conformance/wma/
# (F.asf.json, by make_refs.py; the samples' references go to
# build/scratch/wma/refs/). ffmpeg is a test tool only.
#
# Run from anywhere: tests/asf/make_fixtures.sh (FORCE=1 remakes).
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/asf/fixtures
conf=build/conformance/wma
refs=build/scratch/wma/refs
mkdir -p "$out" "$refs"
q="-hide_banner -loglevel error -y"
v="-f lavfi -i testsrc2=size=160x120:rate=25:duration=1"
tones="-f lavfi -i sine=frequency=440:sample_rate=44100:duration=1 -f lavfi -i sine=frequency=660:sample_rate=44100:duration=1 -filter_complex amerge"
tags=(-metadata title="Reel Title" -metadata artist="Reel Artist" -metadata album="Reel Album" -metadata date=2026 -metadata genre=Test -metadata track=3 -metadata comment="A comment" -metadata copyright="(c) Reel")
made=()

make() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    made+=("$out/$name")
}
variant() { # op source name [arg]
    if [ -f "$out/$3" ] && [ -z "$FORCE" ]; then return; fi
    python3 -I tests/asf/variants.py "$1" "$out/$2" "$out/$3" $4
    made+=("$out/$3")
}

make wmav2_tags.wma $tones -c:a wmav2 -b:a 128k "${tags[@]}"
make wmav1_mono.wma -f lavfi -i sine=frequency=500:sample_rate=22050:duration=1 -c:a wmav1 -b:a 32k
make wmv2_wmav2.wmv $v -f lavfi -i sine=frequency=440:sample_rate=22050:duration=1 -c:v wmv2 -g 10 -b:v 300k -c:a wmav2 -b:a 64k -metadata:s:a:0 language=fre
make wmv1.wmv $v -c:v wmv1 -g 12 -b:v 200k -packet_size 1000
make mp3.asf -f lavfi -i sine=frequency=440:sample_rate=44100:duration=1 -c:a libmp3lame -b:a 64k -f asf
variant cover wmav2_tags.wma cover.wma tests/fixtures/cover.jpg
variant drm wmav1_mono.wma drm.wma
variant noindex wmv2_wmav2.wmv noindex.wmv
variant cut wmv2_wmav2.wmv cut.wmv 60000

[ ${#made[@]} -gt 0 ] && python3 -I tests/asf/make_refs.py "$out" "${made[@]}"
for f in "$conf"/*.wm[av] "$conf"/*.asf; do
    [ -f "$f" ] || continue
    [ -f "$refs/$(basename "$f").asf.json" ] && [ -z "$FORCE" ] && continue
    python3 -I tests/asf/make_refs.py "$refs" "$f"
done
du -sh "$out"
