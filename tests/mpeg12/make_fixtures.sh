#!/bin/bash
# Makes the extra MPEG-1/2 streams tests/mpeg12 reads (small raw
# elementary streams, with ffmpeg's framemd5 for each), and a 1080p
# stream for timing in build/scratch/mpeg12 (not kept in the project).
# ffmpeg is a test tool only.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/mpeg12/fixtures
mkdir -p "$out" build/scratch/mpeg12
q="-hide_banner -loglevel error -y"
src() { echo "-f lavfi -i testsrc2=size=$1:rate=25:duration=$2,noise=alls=8:allf=t"; }
ref() { ffmpeg $q -flags:v +bitexact -i "$1" -f framemd5 "$1.v.framemd5"; }

# Interlaced frame pictures: field DCT and field prediction, alternate
# scan, intra VLC table one, non-linear quantiser, 10-bit DC precision,
# loaded quantiser matrices, BT.709 in a sequence display extension.
ffmpeg $q $(src 240x160 0.8) -vf "tinterlace=interleave_top,fieldorder=tff" -c:v mpeg2video -flags +ildct+ilme -top 1 \
    -alternate_scan 1 -intra_vlc 1 -non_linear_quant 1 -qmax 28 -dc 10 -bf 2 -g 6 -b:v 1500k \
    -intra_matrix "8,16,19,22,26,27,29,34,16,16,22,24,27,29,34,37,19,22,26,27,29,34,34,38,22,22,26,27,29,34,37,40,22,26,27,29,32,35,40,48,26,27,29,32,35,40,48,58,26,27,29,34,38,46,56,69,27,29,35,38,46,56,69,90" \
    -inter_matrix "16,17,18,19,20,21,22,23,17,18,19,20,21,22,23,24,18,19,20,21,22,23,24,25,19,20,21,22,23,24,26,27,20,21,22,23,25,26,27,28,21,22,23,24,26,27,28,30,22,23,24,26,27,28,30,31,23,24,25,27,28,30,31,33" \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -seq_disp_ext 1 -f mpeg2video "$out/interlaced.m2v"
ref "$out/interlaced.m2v"

# 4:2:2 profile, B frames.
ffmpeg $q $(src 176x144 0.4) -c:v mpeg2video -pix_fmt yuv422p -bf 2 -g 5 -b:v 800k -f mpeg2video "$out/yuv422.m2v"
ref "$out/yuv422.m2v"

# MPEG-1 with 16:9-ish pel aspect, odd size (not whole macroblocks).
ffmpeg $q $(src 200x120 0.4) -c:v mpeg1video -bf 1 -g 4 -aspect 16:9 -b:v 600k -f mpeg1video "$out/mpeg1_odd.m1v"
ref "$out/mpeg1_odd.m1v"

# Timing: 1080i-like 1920×1080 at 15 Mbit/s.
ffmpeg $q $(src 1920x1080 1) -c:v mpeg2video -b:v 15M -maxrate 15M -bufsize 9M -bf 2 -g 12 -flags +ildct+ilme -f mpeg2video build/scratch/mpeg12/hd1080.m2v
ls -la "$out" build/scratch/mpeg12/hd1080.m2v
