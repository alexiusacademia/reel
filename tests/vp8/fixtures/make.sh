#!/bin/bash
# Makes the VP8 test clips (small, committed: tests/vp8/fixtures/*.ivf with
# ffmpeg's framemd5 of each) and the timing clips (720p/1080p, ~3 Mbit/s:
# build/scratch/vp8theora/clips/, not committed). Uses ffmpeg's libvpx
# encoder; ffmpeg's own VP8 decoder gives the references. Reel itself never
# runs ffmpeg.
#
# Run from ~/Dev/reel: tests/vp8/fixtures/make.sh   (FORCE=1 to remake)
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../../.."
out=tests/vp8/fixtures
clips=build/scratch/vp8theora/clips
mkdir -p "$out" "$clips"
q="-hide_banner -loglevel error -y"
src() { # size rate seconds
    echo "-f lavfi -i testsrc2=size=$1:rate=$2:duration=$3,noise=alls=8:allf=t"
}
enc="-c:v libvpx -deadline good -cpu-used 4"

make() { # name, then ffmpeg arguments (output is IVF)
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" -f ivf "$out/$name"
    ffmpeg $q -i "$out/$name" -f framemd5 "$out/$name.framemd5"
    echo "made $name"
}

make vp8_basic.ivf $(src 320x240 25 0.4) $enc -b:v 400k
make vp8_parts.ivf $(src 352x288 25 0.4) $enc -b:v 600k -slices 8
make vp8_errres.ivf $(src 320x240 25 0.4) $enc -b:v 300k -error-resilient 1
# testsrc2 makes even sizes only: scale to odd ones.
make vp8_odd.ivf $(src 334x178 25 0.4),scale=333:177 $enc -b:v 300k
make vp8_tiny.ivf $(src 18x10 25 0.4),scale=17:9 $enc -b:v 50k
make vp8_profile1.ivf $(src 176x144 25 0.4) $enc -b:v 200k -profile:v 1
make vp8_profile2.ivf $(src 176x144 25 0.4) $enc -b:v 200k -profile:v 2
make vp8_profile3.ivf $(src 176x144 25 0.4) $enc -b:v 200k -profile:v 3
make vp8_sharp.ivf $(src 176x144 25 0.4) $enc -b:v 100k -sharpness 5
make vp8_rt.ivf $(src 320x240 25 0.6) -c:v libvpx -deadline realtime -cpu-used 8 -b:v 150k -static-thresh 100 -noise-sensitivity 1
# Three temporal layers: the top layer's frames refresh no reference.
make vp8_layers.ivf $(src 176x144 25 0.6) -c:v libvpx -deadline realtime -cpu-used 8 -b:v 200k \
    -ts-parameters ts_layering_mode=3:ts_target_bitrate=80,140,200
make vp8_lowq.ivf $(src 176x144 25 0.12) $enc -qmin 0 -qmax 0 -b:v 5M

# Alt-ref frames (hidden frames) need libvpx's two-pass mode.
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
twopass vp8_altref.ivf $(src 320x240 25 1.2) $enc -b:v 300k -auto-alt-ref 1 -lag-in-frames 25 -arnr-maxframes 5

# A size change mid-stream: two encodes joined as one IVF (the second
# starts with a keyframe at its own size).
if [ ! -f "$out/vp8_sizes.ivf" ] || [ -n "$FORCE" ]; then
    tmp=$(mktemp -d)
    ffmpeg $q $(src 320x240 25 0.4) $enc -b:v 300k -f ivf "$tmp/a.ivf"
    ffmpeg $q $(src 192x108 25 0.4) $enc -b:v 200k -f ivf "$tmp/b.ivf"
    python3 -I tests/vp8/fixtures/ivfcat.py "$tmp/a.ivf" "$tmp/b.ivf" "$out/vp8_sizes.ivf"
    ffmpeg $q -i "$out/vp8_sizes.ivf" -noautoscale -f framemd5 "$out/vp8_sizes.ivf.framemd5"
    rm -rf "$tmp"
    echo "made vp8_sizes.ivf"
fi

# The basic clip in Matroska and AVI (VP80), for demux.open.
for c in mkv avi; do
    if [ ! -f "$out/vp8_basic.$c" ] || [ -n "$FORCE" ]; then
        ffmpeg $q -i "$out/vp8_basic.ivf" -c copy "$out/vp8_basic.$c"
    fi
done

# References for the shared fixture t.vp8.ivf.
if [ ! -f "$out/t.vp8.ivf.framemd5" ] || [ -n "$FORCE" ]; then
    ffmpeg $q -i tests/fixtures/t.vp8.ivf -f framemd5 "$out/t.vp8.ivf.framemd5"
fi

# Timing clips.
tsrc() { echo "-f lavfi -i testsrc2=size=$1:rate=30:duration=3,noise=alls=6:allf=t"; }
tenc="-c:v libvpx -b:v 3M -deadline good -cpu-used 4 -auto-alt-ref 1 -lag-in-frames 16"
clip() { # name size
    if [ -f "$clips/$1.ivf" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q $(tsrc $2) $tenc -f ivf "$clips/$1.ivf"
    ffmpeg $q -i "$clips/$1.ivf" -f framemd5 "$clips/$1.framemd5"
    echo "made $1"
}
clip t720 1280x720
clip t1080 1920x1080
if [ ! -f "$clips/m1080.ivf" ] || [ -n "$FORCE" ]; then
    ffmpeg $q -f lavfi -i "mandelbrot=size=1920x1080:rate=30,trim=duration=3" $tenc -f ivf "$clips/m1080.ivf"
    ffmpeg $q -i "$clips/m1080.ivf" -f framemd5 "$clips/m1080.framemd5"
    echo "made m1080"
fi
if [ ! -f "$clips/h1080.ivf" ] || [ -n "$FORCE" ]; then
    # A heavier one: 8 Mbit/s.
    ffmpeg $q -f lavfi -i "mandelbrot=size=1920x1080:rate=30,trim=duration=3" -c:v libvpx -b:v 8M -deadline good -cpu-used 4 -auto-alt-ref 1 -lag-in-frames 16 -f ivf "$clips/h1080.ivf"
    ffmpeg $q -i "$clips/h1080.ivf" -f framemd5 "$clips/h1080.framemd5"
    echo "made h1080"
fi
if [ ! -f "$clips/m720.ivf" ] || [ -n "$FORCE" ]; then
    ffmpeg $q -f lavfi -i "mandelbrot=size=1280x720:rate=30,trim=duration=3" -c:v libvpx -b:v 2M -deadline good -cpu-used 4 -f ivf "$clips/m720.ivf"
    ffmpeg $q -i "$clips/m720.ivf" -f framemd5 "$clips/m720.framemd5"
    echo "made m720"
fi
