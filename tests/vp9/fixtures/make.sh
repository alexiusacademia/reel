#!/bin/bash
# Makes the VP9 test clips (small, committed: tests/vp9/fixtures/*.ivf with
# ffmpeg's framemd5 of each) and the timing clips (720p/1080p, 8 and 10
# bit, ~3 Mbit/s: build/scratch/vp9/clips/, not committed). Uses ffmpeg's
# libvpx-vp9 encoder; Reel itself never runs ffmpeg.
#
# Run from ~/Dev/reel: tests/vp9/fixtures/make.sh   (FORCE=1 to remake)
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../../.."
out=tests/vp9/fixtures
clips=build/scratch/vp9/clips
mkdir -p "$out" "$clips"
q="-hide_banner -loglevel error -y"
src() { # size rate seconds
    echo "-f lavfi -i testsrc2=size=$1:rate=$2:duration=$3,noise=alls=8:allf=t"
}
enc="-c:v libvpx-vp9 -deadline good -cpu-used 4"

make() { # name, then ffmpeg arguments (output is IVF)
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" -f ivf "$out/$name"
    ffmpeg $q -i "$out/$name" -f framemd5 "$out/$name.framemd5"
    echo "made $name"
}

make vp9_8bit.ivf $(src 320x240 25 0.4) $enc -b:v 400k -pix_fmt yuv420p
make vp9_10bit.ivf $(src 320x240 25 0.4) $enc -b:v 400k -pix_fmt yuv420p10le -profile:v 2
make vp9_12bit.ivf $(src 176x144 25 0.4) $enc -b:v 300k -pix_fmt yuv420p12le -profile:v 2
make vp9_444.ivf $(src 176x144 25 0.4) $enc -b:v 300k -pix_fmt yuv444p -profile:v 1
make vp9_422_10bit.ivf $(src 176x144 25 0.4) $enc -b:v 300k -pix_fmt yuv422p10le -profile:v 3
make vp9_tiles.ivf $(src 1024x256 25 0.2) $enc -b:v 600k -tile-columns 2 -pix_fmt yuv420p
make vp9_rowmt.ivf $(src 640x192 25 0.4) $enc -b:v 500k -row-mt 1 -tile-columns 1 -pix_fmt yuv420p
make vp9_lossless.ivf $(src 96x64 25 0.4) $enc -lossless 1 -pix_fmt yuv420p
make vp9_odd.ivf $(src 333x177 25 0.4) $enc -b:v 300k -pix_fmt yuv420p
make vp9_errres.ivf $(src 320x240 25 0.4) $enc -b:v 300k -error-resilient 1 -frame-parallel 1 -pix_fmt yuv420p

# Alt-ref frames (hidden frames in superframes, compound prediction) need
# libvpx's two-pass mode.
twopass() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    local tmp=$(mktemp -d)
    ffmpeg $q "$@" -pass 1 -passlogfile "$tmp/log" -f null -
    ffmpeg $q "$@" -pass 2 -passlogfile "$tmp/log" -f ivf "$out/$name"
    ffmpeg $q -i "$out/$name" -f framemd5 "$out/$name.framemd5"
    rm -rf "$tmp"
    echo "made $name"
}
twopass vp9_altref.ivf $(src 320x240 25 1.2) $enc -b:v 300k -auto-alt-ref 1 -lag-in-frames 25 -pix_fmt yuv420p
twopass vp9_compound.ivf $(src 352x288 25 1.2) $enc -b:v 150k -auto-alt-ref 1 -lag-in-frames 16 -arnr-maxframes 7 -pix_fmt yuv420p

# A size change mid-stream: two encodes joined as one IVF (the second
# starts with a keyframe at its own size).
if [ ! -f "$out/vp9_sizes.ivf" ] || [ -n "$FORCE" ]; then
    tmp=$(mktemp -d)
    ffmpeg $q $(src 320x240 25 0.4) $enc -b:v 300k -pix_fmt yuv420p -f ivf "$tmp/a.ivf"
    ffmpeg $q $(src 192x108 25 0.4) $enc -b:v 200k -pix_fmt yuv420p -f ivf "$tmp/b.ivf"
    python3 -I tests/vp9/fixtures/ivfcat.py "$tmp/a.ivf" "$tmp/b.ivf" "$out/vp9_sizes.ivf"
    ffmpeg $q -i "$out/vp9_sizes.ivf" -noautoscale -f framemd5 "$out/vp9_sizes.ivf.framemd5"
    rm -rf "$tmp"
    echo "made vp9_sizes.ivf"
fi

# Timing clips.
tsrc() { echo "-f lavfi -i testsrc2=size=$1:rate=30:duration=3,noise=alls=6:allf=t"; }
tenc="-c:v libvpx-vp9 -b:v 3M -deadline good -cpu-used 4 -row-mt 1 -auto-alt-ref 1 -lag-in-frames 16"
clip() { # name size pixfmt [profile]
    if [ -f "$clips/$1.ivf" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q $(tsrc $2) $tenc -pix_fmt $3 ${4:+-profile:v $4} -f ivf "$clips/$1.ivf"
    ffmpeg $q -i "$clips/$1.ivf" -f framemd5 "$clips/$1.framemd5"
    echo "made $1"
}
clip t720 1280x720 yuv420p
clip t1080 1920x1080 yuv420p
clip t720_10 1280x720 yuv420p10le 2
clip t1080_10 1920x1080 yuv420p10le 2
if [ ! -f "$clips/m1080.ivf" ] || [ -n "$FORCE" ]; then
    ffmpeg $q -f lavfi -i "mandelbrot=size=1920x1080:rate=30,trim=duration=3" $tenc -pix_fmt yuv420p -f ivf "$clips/m1080.ivf"
    ffmpeg $q -i "$clips/m1080.ivf" -f framemd5 "$clips/m1080.framemd5"
    echo "made m1080"
fi
