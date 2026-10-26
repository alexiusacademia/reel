#!/bin/bash
# Makes the extra clips the lossless test reads (besides tests/fixtures):
# FLAC with every stereo mode, LPC up to order 32, fixed predictors, odd
# block sizes, wasted bits, noise (escape codes), 8 kHz mono; ALAC 24-bit,
# mono and 5.1; PCM forms the shared fixtures don't have (s32, f64, s8,
# 24-bit big endian), A-law and µ-law. For each F: F.a.f32 (ffmpeg's
# decoded samples) and F.ref.json (packets, via tools/make_ref.py).
# ffmpeg is a test tool only. Run from anywhere; FORCE=1 remakes.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/lossless/fixtures
mkdir -p "$out"
q="-hide_banner -loglevel error -y"
# A chirp plus a little noise: more varied than a sine, so predictors and
# Rice parameters change from frame to frame.
sig() { # rate channels seconds
    local layout=$([ "$2" = 1 ] && echo mono || ([ "$2" = 6 ] && echo 5.1 || echo stereo))
    echo "-f lavfi -i aevalsrc=0.4*sin(2*PI*(200+2000*t)*t)+0.05*(random(0)-0.5)|0.3*sin(2*PI*330*t)+0.05*(random(1)-0.5):s=$1:d=$3,aformat=channel_layouts=$layout"
}
make() {
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    ffmpeg $q -i "$out/$name" -map 0:a:0 -c:a pcm_f32le -f f32le "$out/$name.a.f32"
    ffprobe -v error -print_format json -show_streams -show_format -show_packets -show_data "$out/$name" > "$out/$name.probe.json"
    python3 -I tools/trim_probe.py "$out/$name.probe.json"
    python3 -I tools/make_ref.py "$out/$name.probe.json"
    rm -f "$out/$name.probe.json"
    echo "made $name"
}

make flac_ms.flac $(sig 44100 2 0.2) -c:a flac -sample_fmt s16 -ch_mode mid_side
make flac_ls.flac $(sig 44100 2 0.2) -c:a flac -ch_mode left_side
make flac_rs.flac $(sig 44100 2 0.2) -c:a flac -ch_mode right_side
make flac_lpc32.flac $(sig 48000 2 0.2) -c:a flac -compression_level 12 -lpc_type cholesky -max_prediction_order 32 -exact_rice_parameters 1 -max_partition_order 8
make flac_fixed.flac $(sig 44100 2 0.2) -c:a flac -lpc_type fixed
make flac_odd.flac $(sig 32000 1 0.2) -c:a flac -frame_size 1000
make flac_tiny.flac $(sig 8000 1 0.15) -c:a flac -frame_size 100
make flac_noise.flac -f lavfi -i "anoisesrc=color=white:amplitude=0.9:sample_rate=22050:duration=0.15" -c:a flac
make flac_s32.flac $(sig 48000 2 0.2) -c:a flac -sample_fmt s32 -strict experimental
make flac_wasted.flac -f lavfi -i "aevalsrc=floor(16*sin(2*PI*440*t))/32|floor(8*sin(2*PI*220*t))/32:s=44100:d=0.15" -c:a flac
make alac_24.m4a $(sig 48000 2 0.15) -c:a alac -sample_fmt s32p
make alac_mono.m4a $(sig 22050 1 0.15) -c:a alac -sample_fmt s16p
make alac_51.m4a -f lavfi -i "aevalsrc=0.3*sin(2*PI*200*t)|0.3*sin(2*PI*300*t)+0.02*(random(0)-0.5)|0.3*sin(2*PI*400*t)|0.2*sin(2*PI*60*t)|0.3*sin(2*PI*500*t)|0.3*sin(2*PI*700*t):c=5.1:s=48000:d=0.1" -c:a alac
make alac_noise.m4a -f lavfi -i "anoisesrc=color=white:amplitude=1.0:sample_rate=44100:duration=0.1" -c:a alac
make pcm_s32.wav $(sig 44100 2 0.2) -c:a pcm_s32le
make pcm_f64.wav $(sig 44100 2 0.2) -c:a pcm_f64le
make pcm_s24be.aiff $(sig 48000 2 0.2) -c:a pcm_s24be
make pcm_s8.aiff $(sig 8000 1 0.15) -c:a pcm_s8
make pcm_s16be.mov $(sig 44100 2 0.2) -c:a pcm_s16be
make alaw.wav $(sig 8000 1 0.25) -c:a pcm_alaw
make ulaw.wav $(sig 8000 2 0.25) -c:a pcm_mulaw
du -sh "$out"
