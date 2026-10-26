#!/bin/bash
# Makes the vfx test's clips with ffmpeg: progressive sources at 50
# pictures a second (testsrc2: moving and still parts; a mandelbrot zoom:
# everything moving, fine detail; a still picture: nothing moving), and
# the same clips interlaced by ffmpeg's tinterlace (interleave_top: top
# field from pictures 0, 2, 4…, bottom field from 1, 3, 5…, no vertical
# low-pass), as raw 8-bit 4:2:0 compressed with zlib. Also a clip with
# black bars (letterbox + pillarbox) and a clip with scene cuts.
#
# Run from the Reel folder: tests/vfx/make_fixtures.sh
#
# Author: Alexius Academia
# Date: 2026-10-26

set -e
cd "$(dirname "$0")/../.."
out=tests/vfx/fixtures
tmp=build/scratch/vfx/fixtures
mkdir -p "$out" "$tmp"
q="-hide_banner -loglevel error -y"
z() {
    python3 -I -c "import sys,zlib;open(sys.argv[2],'wb').write(zlib.compress(open(sys.argv[1],'rb').read(),9))" "$1" "$2"
}
size=256x192
# name lavfi-source size [i]: progressive (and interlaced with "i"; the
# test checks its own weave against ffmpeg's on testsrc and weaves the
# others itself, to keep the fixtures small)
clip() {
    ffmpeg $q -f lavfi -i "$2" -frames:v 12 -pix_fmt yuv420p -f rawvideo "$tmp/$1_p.yuv"
    z "$tmp/$1_p.yuv" "$out/$1_p.yuv.z"
    if [ -n "$4" ]; then
        ffmpeg $q -f rawvideo -pix_fmt yuv420p -s $3 -r 50 -i "$tmp/$1_p.yuv" -vf "tinterlace=mode=interleave_top" -pix_fmt yuv420p -f rawvideo "$tmp/$1_i.yuv"
        z "$tmp/$1_i.yuv" "$out/$1_i.yuv.z"
    fi
}
clip testsrc "testsrc2=size=$size:rate=50" $size i
clip mandel "mandelbrot=size=128x96:rate=50:start_scale=0.5:end_scale=0.05:end_pts=1" 128x96
clip still "testsrc2=size=$size:rate=1,trim=end_frame=1,loop=loop=-1:size=1,setpts=N/50/TB" $size
# Letterboxed 2.35:1 inside 256×192 with 16-pixel pillars: picture 224×96
# at (16, 48).
ffmpeg $q -f lavfi -i "testsrc2=size=224x96:rate=25" -frames:v 3 -vf "pad=256:192:16:48:black" -pix_fmt yuv420p -f rawvideo "$tmp/bars.yuv"
z "$tmp/bars.yuv" "$out/bars.yuv.z"
# Scene cuts: 3 shots of 10 pictures (testsrc2, a mandelbrot, smpte bars
# with noise), 96×64.
ffmpeg $q -f lavfi -i "testsrc2=size=96x64:rate=25" -f lavfi -i "mandelbrot=size=96x64:rate=25" -f lavfi -i "smptebars=size=96x64:rate=25,noise=alls=8:allf=t" \
    -filter_complex "[0]trim=end_frame=10[a];[1]trim=end_frame=10,setpts=PTS-STARTPTS[b];[2]trim=end_frame=10,setpts=PTS-STARTPTS[c];[a][b][c]concat=n=3:v=1[v]" \
    -map "[v]" -pix_fmt yuv420p -f rawvideo "$tmp/cuts.yuv"
z "$tmp/cuts.yuv" "$out/cuts.yuv.z"
du -sh "$out"

# ffmpeg's own deinterlacers (yadif, bwdif, w3fdif) at field rate on the
# same interlaced clips, as a black box: mean luma PSNR against the
# progressive pictures, for the test to print beside Reel's numbers.
psnr() {
    python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys, math
a = open(sys.argv[1], "rb").read(); b = open(sys.argv[2], "rb").read()
w, h = map(int, sys.argv[3].split("x")); n = int(sys.argv[4])
size = w * h * 3 // 2
total = 0.0
for k in range(n):
    pa = a[k*size:k*size + w*h]; pb = b[k*size:k*size + w*h]
    se = sum((x - y) ** 2 for x, y in zip(pa, pb))
    total += 99.0 if se == 0 else 10 * math.log10(255 * 255 * w * h / se)
print("%.2f" % (total / n))
PY
}
: > "$out/ffmpeg_deint.txt"
for c in testsrc:$size mandel:128x96 still:$size; do
    name=${c%%:*}; s=${c#*:}
    ffmpeg $q -f rawvideo -pix_fmt yuv420p -s $s -r 50 -i "$tmp/${name}_p.yuv" -vf "tinterlace=mode=interleave_top" -pix_fmt yuv420p -f rawvideo "$tmp/${name}_i.yuv"
    for f in yadif=1:0 bwdif=1:0 w3fdif; do
        ffmpeg $q -f rawvideo -pix_fmt yuv420p -s $s -r 25 -i "$tmp/${name}_i.yuv" -vf "setfield=tff,$f" -pix_fmt yuv420p -f rawvideo "$tmp/${name}_d.yuv"
        echo "$name ${f%%=*} $(psnr "$tmp/${name}_d.yuv" "$tmp/${name}_p.yuv" $s 12)" >> "$out/ffmpeg_deint.txt"
    done
done
cat "$out/ffmpeg_deint.txt"
