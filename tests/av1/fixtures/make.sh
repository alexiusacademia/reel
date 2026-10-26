#!/bin/bash
# Makes the AV1 test clips: small ones committed in tests/av1/fixtures/
# (*.ivf with ffmpeg's libdav1d framemd5 of each) and the timing clips
# (720p/1080p, 8 and 10 bit: build/scratch/av1/clips/, not committed).
# Encoders: ffmpeg's libsvtav1 and aomenc (fed y4m from ffmpeg) for the
# tools SVT-AV1 doesn't use (palette/intra block copy, superres, 4:4:4,
# 4:2:2, 12-bit, lossless, error resilience, scaled references,
# monochrome). Reel itself never runs ffmpeg.
#
# Run from ~/Dev/reel: tests/av1/fixtures/make.sh   (FORCE=1 to remake)
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../../.."
out=tests/av1/fixtures
clips=build/scratch/av1/clips
mkdir -p "$out" "$clips"
q="-hide_banner -loglevel error -y"
src() { # size rate seconds
    echo "-f lavfi -i testsrc2=size=$1:rate=$2:duration=$3,noise=alls=8:allf=t"
}
ref() { # ivf -> framemd5 with libdav1d (film grain applied, as dav1d does)
    ffmpeg $q -c:v libdav1d -i "$1" -noautoscale -f framemd5 "$1.framemd5"
}
svt() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" -f ivf "$out/$name"
    ref "$out/$name"
    echo "made $name"
}
aom() { # name pixfmt size seconds, then aomenc arguments
    local name=$1 pix=$2 size=$3 secs=$4
    shift 4
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    local tmp=$(mktemp -d)
    ffmpeg $q $(src $size 25 $secs) -pix_fmt $pix -f yuv4mpegpipe -strict -1 "$tmp/in.y4m"
    aomenc --quiet --ivf --cpu-used=6 --lag-in-frames=12 "$@" -o "$out/$name" "$tmp/in.y4m" 2>/dev/null
    rm -rf "$tmp"
    ref "$out/$name"
    echo "made $name"
}
s="-c:v libsvtav1 -preset 8"
svt av1_8bit.ivf $(src 320x240 25 0.8) $s -crf 40 -pix_fmt yuv420p
svt av1_10bit.ivf $(src 320x240 25 0.8) $s -crf 40 -pix_fmt yuv420p10le
svt av1_grain.ivf $(src 320x240 25 0.4) $s -crf 40 -pix_fmt yuv420p -svtav1-params film-grain=8
svt av1_grain10.ivf $(src 320x240 25 0.4) $s -crf 40 -pix_fmt yuv420p10le -svtav1-params film-grain=8
svt av1_tiles.ivf $(src 1024x288 25 0.4) $s -crf 45 -pix_fmt yuv420p -svtav1-params tile-columns=2:tile-rows=1
svt av1_odd.ivf $(src 333x177 25 0.6) $s -crf 40 -pix_fmt yuv420p
a="--end-usage=q --cq-level=40"
aom aom_screen.ivf yuv420p 256x144 0.4 $a --tune-content=screen
aom aom_superres.ivf yuv420p 320x240 0.4 $a --superres-mode=1 --superres-denominator=12
aom aom_444.ivf yuv444p 176x144 0.4 $a --profile=1
aom aom_422_10.ivf yuv422p10le 176x144 0.4 $a --profile=2 --bit-depth=10 --input-bit-depth=10
aom aom_12bit.ivf yuv420p12le 176x144 0.4 $a --profile=2 --bit-depth=12 --input-bit-depth=12
aom aom_lossless.ivf yuv420p 96x64 0.3 --lossless=1
aom aom_errres.ivf yuv420p 256x144 0.4 $a --error-resilient=1
aom aom_resize.ivf yuv420p 320x240 0.8 $a --resize-mode=2
aom aom_mono.ivf yuv420p 176x144 0.4 $a --monochrome
aom aom_sframe.ivf yuv420p 256x144 0.8 $a --sframe-dist=6 --sframe-mode=2
aom aom_fwdkf.ivf yuv420p 256x144 1.2 $a --enable-fwd-kf=1 --kf-min-dist=10 --kf-max-dist=10
aom aom_tools.ivf yuv420p 320x240 0.8 $a --cpu-used=1 --enable-global-motion=1 --enable-warped-motion=1 --enable-obmc=1 --enable-interintra-comp=1 --enable-masked-comp=1 --enable-dual-filter=1 --enable-ref-frame-mvs=1
aom aom_sb128.ivf yuv420p 640x360 0.4 $a --sb-size=128 --tile-columns=1 --tile-rows=1
aom aom_tilesizes.ivf yuv420p 704x320 0.4 $a --sb-size=64 --tile-width=3,5,2 --tile-height=2,3
aom aom_seg.ivf yuv420p 320x240 0.8 $a --aq-mode=1 --deltaq-mode=1 --delta-lf-mode=1
aom aom_qm.ivf yuv420p 320x240 0.4 $a --enable-qm=1 --qm-min=4 --qm-max=10
aom aom_tiny.ivf yuv420p 17x9 0.4 $a
aom aom_cdfoff.ivf yuv420p 176x144 0.4 $a --cdf-update-mode=2
aom aom_422_8.ivf yuv422p 101x63 0.4 $a --profile=2
aom aom_444_odd.ivf yuv444p 97x45 0.4 $a --profile=1 --tune-content=screen
aom aom_superres10.ivf yuv420p10le 240x136 0.4 $a --bit-depth=10 --input-bit-depth=10 --superres-mode=1 --superres-denominator=14
aom aom_grain444.ivf yuv444p 128x96 0.4 $a --profile=1 --film-grain-test=3
aom aom_mono10.ivf yuv420p10le 128x96 0.4 $a --bit-depth=10 --input-bit-depth=10 --monochrome --film-grain-test=1

# Annex B (length-delimited) units, as aomenc writes raw .obu files.
if [ ! -f "$out/aom_annexb.obu" ] || [ -n "$FORCE" ]; then
    tmp=$(mktemp -d)
    ffmpeg $q $(src 176x144 25 0.4) -pix_fmt yuv420p -f yuv4mpegpipe "$tmp/in.y4m"
    aomenc --quiet --annexb=1 --obu --cpu-used=6 --end-usage=q --cq-level=40 -o "$out/aom_annexb.obu" "$tmp/in.y4m" 2>/dev/null
    rm -rf "$tmp"
    ffmpeg $q -c:v libdav1d -f av1 -i "$out/aom_annexb.obu" -f framemd5 "$out/aom_annexb.obu.framemd5"
    echo "made aom_annexb.obu"
fi

# Timing clips: ~3.5 Mbit/s 1080p (2 Mbit/s 720p), 30 fps, 3 s.
tsrc() { echo "-f lavfi -i mandelbrot=size=$1:rate=30,trim=duration=3,noise=alls=4:allf=t"; }
clip() { # name size pixfmt bitrate
    if [ -f "$clips/$1.ivf" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q $(tsrc $2) -c:v libsvtav1 -preset 8 -b:v $4 -pix_fmt $3 -f ivf "$clips/$1.ivf"
    ffmpeg $q -c:v libdav1d -i "$clips/$1.ivf" -f framemd5 "$clips/$1.framemd5"
    echo "made $1"
}
clip t720 1280x720 yuv420p 2M
clip t1080 1920x1080 yuv420p 3500k
clip t720_10 1280x720 yuv420p10le 2M
clip t1080_10 1920x1080 yuv420p10le 3500k
