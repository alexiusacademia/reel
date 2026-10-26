#!/bin/bash
# Makes demux_b's extra fixtures (Matroska and Ogg files with codecs and
# features the shared fixtures don't have) into tests/demux_b/fixtures/,
# with ffprobe's answers as F.ref.json (through tools/make_ref.py), plus
# hand-built files from synth.py (lacing, live WebM, header stripping …)
# whose answers synth.py writes itself. ffmpeg and Python are test tools
# only: Reel never runs them.
#
# Run from anywhere: tests/demux_b/make_fixtures.sh   (FORCE=1 remakes)
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/demux_b/fixtures
shared=tests/fixtures
mkdir -p "$out"
q="-hide_banner -loglevel error -y"
v() { echo "-f lavfi -i testsrc2=size=$1:rate=$2:duration=$3"; }
a() { echo "-f lavfi -i sine=frequency=440:sample_rate=$1:duration=$3,aformat=channel_layouts=$( [ "$2" = 1 ] && echo mono || ([ "$2" = 6 ] && echo 5.1 || echo stereo))"; }
make() {
    local name=$1; shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    echo "made $name"
}

make vorbis.mka $(a 44100 2 0.5) -c:a vorbis -strict -2
make flac.mka $(a 44100 2 0.5) -c:a flac
make pcm_s16.mka $(a 22050 2 0.3) -c:a pcm_s16le
make pcm_s24be.mka $(a 22050 1 0.3) -c:a pcm_s24be
make pcm_f32.mka $(a 22050 1 0.3) -c:a pcm_f32le
make pcm_u8.mka $(a 8000 1 0.3) -c:a pcm_u8
make ac3.mka $(a 48000 6 0.3) -c:a ac3
make eac3.mka $(a 48000 2 0.3) -c:a eac3
make mp2.mka $(a 48000 2 0.3) -c:a mp2
make dts.mka $(a 48000 2 0.3) -c:a dca -strict -2
make alac.mka $(a 44100 2 0.3) -c:a alac
make mpeg4.mkv $(v 64x48 25 0.4) -c:v mpeg4 -bf 1
make mpeg2.mkv $(v 64x48 25 0.4) -c:v mpeg2video
make mpeg1.mkv $(v 64x48 25 0.4) -c:v mpeg1video
make mjpeg.mkv $(v 64x48 25 0.2) -c:v mjpeg -pix_fmt yuvj420p
make hevc.mkv $(v 64x48 25 0.4) -c:v libx265 -x265-params log-level=error
make aspect.mkv $(v 64x48 30000/1001 0.4) -c:v libx264 -aspect 16:9 -pix_fmt yuv420p
make webvtt.mkv $(v 64x48 25 4) -i $shared/subs.vtt -map 0 -map 1 -c:v libx264 -pix_fmt yuv420p -c:s webvtt
make webvtt.webm $(v 64x48 25 4) -i $shared/subs.vtt -map 0 -map 1 -c:v libvpx -c:s webvtt
make attach.mkv $(v 64x48 25 0.2) -attach $shared/cover.jpg -metadata:s:t:0 mimetype=image/jpeg -metadata:s:t:0 filename=cover.jpg -c:v libx264 -pix_fmt yuv420p -metadata title="Attached" -metadata artist="Reel" -metadata date=2026
make tags.ogg $(a 48000 2 0.5) -c:a libopus -metadata title="Ogg Tags" -metadata artist="Reel" -metadata album="Reel Album"
make flac.oga $(a 96000 6 1) -c:a flac -sample_fmt s32 -compression_level 0

for f in "$out"/*; do
    case "$f" in *.json|*.py|*.sh) continue ;; esac
    [ -f "$f.ref.json" ] && [ -z "$FORCE" ] && continue
    ffprobe -v error -print_format json -show_streams -show_format -show_chapters -show_packets -show_data "$f" > "$f.probe.json" || true
    python3 -I tools/trim_probe.py "$f.probe.json"
    python3 -I tools/make_ref.py "$f.probe.json"
    rm -f "$f.probe.json"
    echo "probed $(basename "$f")"
done
python3 -I tests/demux_b/synth.py "$out"
du -sh "$out"
