#!/bin/bash
# Makes the ProRes and DNxHD/DNxHR test clips with ffmpeg and ffmpeg's
# own decoded answers (framemd5 of every picture, in the decoder's pixel
# format: 16-bit little-endian samples for 10/12-bit).
#
#   small clips      -> tests/prores/fixtures, tests/dnxhd/fixtures (committed)
#   1080p / 4K clips -> build/scratch/pro/big (timing, not committed)
#   FATE samples     -> build/conformance/pro (downloaded), md5s made here
#
# Run from ~/Dev/reel: tests/prores/make_fixtures.sh
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
P=tests/prores/fixtures
D=tests/dnxhd/fixtures
B=build/scratch/pro/big
C=build/conformance/pro
mkdir -p $P $D $B
FF="ffmpeg -hide_banner -loglevel error -y"

# A busy test picture: moving colour bars, gradients and noise.
src() { # size frames
    echo "-f lavfi -i testsrc2=size=$1:rate=25,noise=alls=12:allf=t+u -frames:v $2"
}
ref() { # file [decoder options]
    local f=$1; shift
    # Whole coded pictures: no cropping by the container's clean aperture.
    $FF -apply_cropping none "$@" -i "$f" -map 0:v:0 -f framemd5 "$f.framemd5"
}

# ---- ProRes (prores_ks profiles 0..5, prores_aw, interlaced, alpha) ----
for p in 0 1 2 3; do
    $FF $(src 208x112 2) -pix_fmt yuv422p10le -c:v prores_ks -profile:v $p $P/ks$p.mov
    ref $P/ks$p.mov
done
for p in 4 5; do
    $FF $(src 208x112 2) -pix_fmt yuv444p10le -c:v prores_ks -profile:v $p $P/ks$p.mov
    ref $P/ks$p.mov
done
# Odd size, 4 macroblocks per slice, a fixed quantiser matrix.
$FF $(src 173x101 2) -pix_fmt yuv422p10le -c:v prores_ks -profile:v 2 -mbs_per_slice 4 $P/odd.mov
ref $P/odd.mov
# High bit budget: big coefficients, small quantisers.
$FF $(src 96x64 2) -pix_fmt yuv422p10le -c:v prores_ks -profile:v 3 -bits_per_mb 8000 $P/hiq.mov
ref $P/hiq.mov
# prores_aw (another encoder: other slice sizes and tables).
$FF $(src 160x96 2) -pix_fmt yuv422p10le -c:v prores_aw -profile:v 3 $P/aw3.mov
ref $P/aw3.mov
$FF $(src 160x96 2) -pix_fmt yuv444p10le -c:v prores_aw -profile:v 4 $P/aw4.mov
ref $P/aw4.mov
# Interlaced: top field first and bottom field first, odd height.
$FF $(src 176x128 2) -vf setfield=tff -pix_fmt yuv422p10le -c:v prores_ks -profile:v 2 -flags +ildct $P/tff.mov
ref $P/tff.mov
$FF $(src 176x122 2) -vf setfield=bff -pix_fmt yuv422p10le -c:v prores_ks -profile:v 3 -flags +ildct $P/bff.mov
ref $P/bff.mov
$FF $(src 192x128 2) -vf setfield=tff -pix_fmt yuv444p10le -c:v prores_ks -profile:v 4 -flags +ildct $P/il444.mov
ref $P/il444.mov
# 4444 with an alpha plane (alpha is skipped: the reference drops it too).
$FF -f lavfi -i "testsrc2=size=128x96:rate=25,format=yuva444p10le,geq=lum='lum(X,Y)':cb='cb(X,Y)':cr='cr(X,Y)':a='512+400*sin(X/9)'" -frames:v 2 -c:v prores_ks -profile:v 4 $P/alpha.mov
ref $P/alpha.mov -skip_alpha 1

# ---- DNxHR (any size) and DNxHD (fixed sizes and bitrates) ----
for p in dnxhr_lb dnxhr_sq dnxhr_hq; do
    $FF $(src 256x144 2) -pix_fmt yuv422p -c:v dnxhd -profile:v $p $D/$p.mov
    ref $D/$p.mov
done
$FF $(src 256x144 2) -pix_fmt yuv422p10le -c:v dnxhd -profile:v dnxhr_hqx $D/dnxhr_hqx.mov
ref $D/dnxhr_hqx.mov
$FF $(src 256x144 2) -pix_fmt yuv444p10le -c:v dnxhd -profile:v dnxhr_444 $D/dnxhr_444.mov
ref $D/dnxhr_444.mov
$FF $(src 256x144 2) -pix_fmt gbrp10le -c:v dnxhd -profile:v dnxhr_444 $D/dnxhr_444rgb.mov
ref $D/dnxhr_444rgb.mov
$FF $(src 264x130 2) -pix_fmt yuv422p -c:v dnxhd -profile:v dnxhr_sq $D/dnxhr_odd.mov
ref $D/dnxhr_odd.mov
# DNxHD 1080p 36 Mb/s (CID 1253), one frame, committed.
$FF $(src 1920x1080 1) -pix_fmt yuv422p -c:v dnxhd -b:v 36M $D/dnxhd36.mov
ref $D/dnxhd36.mov

# DNxHD bitrates (each CID ffmpeg can make), 2 frames, in scratch.
dnx() { # name size pixfmt bitrate [flags]
    $FF $(src $2 2) -pix_fmt $3 -c:v dnxhd -b:v $4 $5 $B/$1.mov
    ref $B/$1.mov
}
dnx cid1235 1920x1080 yuv422p10le 175M
dnx cid1237 1920x1080 yuv422p 115M
dnx cid1238 1920x1080 yuv422p 175M
dnx cid1241 1920x1080 yuv422p10le 185M "-flags +ildct"
dnx cid1242 1920x1080 yuv422p 120M "-flags +ildct"
dnx cid1243 1920x1080 yuv422p 185M "-flags +ildct"
dnx cid1250 1280x720 yuv422p10le 90M
dnx cid1251 1280x720 yuv422p 90M
dnx cid1252 1280x720 yuv422p 60M
dnx cid1258 960x720 yuv422p 42M
dnx cid1259 1440x1080 yuv422p 63M
dnx cid1244 1440x1080 yuv422p 120M "-flags +ildct"

# ---- Timing clips: 1080p and 4K, 3 frames ----
big() { # name size options
    local n=$1 s=$2; shift 2
    $FF $(src $s 3) "$@" $B/$n.mov
    ref $B/$n.mov
}
big prores_hq_1080 1920x1080 -pix_fmt yuv422p10le -c:v prores_ks -profile:v 3
big prores_422_1080 1920x1080 -pix_fmt yuv422p10le -c:v prores_ks -profile:v 2
big prores_4444_1080 1920x1080 -pix_fmt yuv444p10le -c:v prores_ks -profile:v 4
big prores_hq_2160 3840x2160 -pix_fmt yuv422p10le -c:v prores_ks -profile:v 3
big dnxhr_hq_1080 1920x1080 -pix_fmt yuv422p -c:v dnxhd -profile:v dnxhr_hq
big dnxhr_hqx_1080 1920x1080 -pix_fmt yuv422p10le -c:v dnxhd -profile:v dnxhr_hqx
big dnxhr_hq_2160 3840x2160 -pix_fmt yuv422p -c:v dnxhd -profile:v dnxhr_hq
big dnxhr_444_2160 3840x2160 -pix_fmt yuv444p10le -c:v dnxhd -profile:v dnxhr_444

# ---- FATE samples ----
for f in $C/*.mov; do
    case "$f" in
        *with_Alpha*|*transparency*) ref "$f" -skip_alpha 1 ;;
        *) ref "$f" ;;
    esac
done
echo done
