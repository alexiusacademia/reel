#!/bin/bash
# Makes the Vorbis test's own fixtures in tests/vorbis/fixtures from files
# in build/scratch/vorbis (FFmpeg FATE samples, made by libvorbis, and
# build/scratch/vorbis/make_native.sh output): short cuts of the streams
# (remuxed, not re-encoded) and ffmpeg's decoded samples of each (32-bit
# float, first frames only, to keep the folder small).
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
src=build/scratch/vorbis
out=tests/vorbis/fixtures
mkdir -p "$out"
q="-hide_banner -loglevel error -y"
cut() { # source, name, seconds, frames of reference to keep, channels
    ffmpeg $q -i "$1" -t "$3" -c copy "$out/$2.ogg"
    ffmpeg $q -i "$out/$2.ogg" -f f32le -c:a pcm_f32le "$out/$2.full.f32"
    head -c $(( $4 * $5 * 4 )) "$out/$2.full.f32" > "$out/$2.f32"
    rm "$out/$2.full.f32"
}
cut $src/fate/6.ogg surround6 0.4 4096 6           # 6 channels, 2 submaps, residues 1+2
cut $src/fate/lsp-test3_small.ogg floor0 0.6 8192 2  # floor 0, residue 0, 24-bit codewords
cut $src/fate/mono_small.ogg mono 0.6 16384 1        # mono, residue 1
cut $src/native/noise_q9.ogg noise 0.5 8192 2       # ffmpeg encoder at high quality
ls -la "$out"
