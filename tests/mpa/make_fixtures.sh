#!/bin/bash
# Makes the extra MPEG audio clips the mpa test reads (besides
# tests/fixtures), each with F.a.f32, ffmpeg's decoded samples:
#   lame: short blocks (clicks), MPEG-2 LSF and MPEG-2.5 rates, CRC, forced
#         mid/side, dual channel, simple stereo, 320 kbps, no reservoir;
#   ffmpeg's mp2 encoder: mono 32 kHz, LSF 22.05 and 16 kHz;
#   gen_layer12.py: layer I (every mode, joint bounds, CRC) and layer II
#         joint stereo / dual / LSF, which no encoder here makes.
# ffmpeg and lame are test tools only. FORCE=1 remakes.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")"
out=fixtures
tmp=$(mktemp -d)
q="-hide_banner -loglevel error -y"
# Two tones plus clicks every 0.1 s: the clicks make lame switch to short
# blocks.
src() { # rate channels seconds
    local layout=$([ "$2" = 1 ] && echo mono || echo stereo)
    ffmpeg $q -f lavfi -i "aevalsrc=0.3*sin(2*PI*440*t)+0.6*lt(mod(t\,0.1)\,0.002)*(random(0)-0.5)|0.25*sin(2*PI*660*t)+0.5*lt(mod(t+0.05\,0.1)\,0.002)*(random(1)-0.5):s=$1:d=$3" -af aformat=channel_layouts=$layout -c:a pcm_s16le "$tmp/src.wav"
}
ref() {
    ffmpeg $q -i "$out/$1" -map 0:a:0 -c:a pcm_f32le -f f32le "$out/$1.a.f32"
    echo "made $1"
}
lamemake() { # name rate channels seconds lame-args...
    local name=$1 rate=$2 ch=$3 secs=$4
    shift 4
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    src "$rate" "$ch" "$secs"
    lame --quiet "$@" "$tmp/src.wav" "$out/$name"
    ref "$name"
}
ffmake() { # name rate channels seconds ffmpeg-args...
    local name=$1 rate=$2 ch=$3 secs=$4
    shift 4
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    src "$rate" "$ch" "$secs"
    ffmpeg $q -i "$tmp/src.wav" "$@" "$out/$name"
    ref "$name"
}
genmake() { # name layer rate mode modeext kbps frames crc seed
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    python3 -I gen_layer12.py "$@" "$out/$name"
    ffmpeg $q -f mp3 -i "$out/$name" -c:a pcm_f32le -f f32le "$out/$name.a.f32" 2>/dev/null ||
        ffmpeg $q -i "$out/$name" -c:a pcm_f32le -f f32le "$out/$name.a.f32"
    echo "made $name"
}

lamemake mp3_short.mp3 44100 2 0.5 -b 128 -m j
lamemake mp3_lsf24.mp3 24000 2 0.5 -b 64
lamemake mp3_lsf16.mp3 16000 1 0.5 -b 32
lamemake mp3_m25_8k.mp3 8000 1 0.6 -b 16
lamemake mp3_m25_11k.mp3 11025 2 0.5 -b 32
lamemake mp3_m25_12k.mp3 12000 2 0.5 -b 24 -m f
lamemake mp3_crc.mp3 44100 2 0.4 -b 96 -p
lamemake mp3_ms.mp3 48000 2 0.4 -b 112 -m f
lamemake mp3_dual.mp3 44100 2 0.4 -b 128 -m d
lamemake mp3_simple.mp3 32000 2 0.4 -b 96 -m s
lamemake mp3_320.mp3 44100 2 0.4 -b 320
lamemake mp3_nores.mp3 44100 2 0.4 -b 128 --nores
ffmake mp2_mono32.mp2 32000 1 0.5 -c:a mp2 -b:a 64k
ffmake mp2_lsf22.mp2 22050 2 0.5 -c:a mp2 -b:a 64k
ffmake mp2_lsf16.mp2 16000 1 0.5 -c:a mp2 -b:a 32k
genmake mp1_stereo.mp1 1 44100 0 0 192 12 0 1
genmake mp1_joint4.mp1 1 48000 1 0 256 12 0 2
genmake mp1_joint16.mp1 1 32000 1 3 192 12 1 3
genmake mp1_mono.mp1 1 44100 3 0 96 12 0 4
genmake mp1_dual.mp1 1 48000 2 0 320 12 0 5
genmake mp1_lsf.mp1 1 22050 1 1 128 12 0 6
genmake mp2_joint8.mp2 2 44100 1 1 192 8 0 7
genmake mp2_joint16.mp2 2 48000 1 3 256 8 1 8
genmake mp2_dual.mp2 2 32000 2 0 192 8 0 9
genmake mp2_lsfjoint.mp2 2 24000 1 2 96 8 0 10
genmake mp2_lowrate.mp2 2 44100 0 0 64 8 0 11
rm -rf "$tmp"
du -sh "$out"
