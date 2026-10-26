#!/bin/bash
# Makes the HEVC decoder's own fixtures in tests/hevc/fixtures with ffmpeg's
# libx265: raw Annex B streams (NAME.hevc) and ffmpeg's per-picture md5s
# (NAME.hevc.framemd5, native pixel format: 16-bit little-endian samples for
# 10-bit). Run from anywhere; needs ffmpeg 8 with libx265.
#
# Author: Alexius Academia
# Date: 2026-10-25

cd "$(dirname "$0")/fixtures" || exit 1
q="-v error -y"
src="testsrc2=size=320x240:rate=25"
grain="testsrc2=s=1920x1080:r=24,noise=alls=10:allf=t"

# make NAME FRAMES SOURCE PIXFMT X265PARAMS [extra ffmpeg options]
make() {
    local name=$1 frames=$2 source=$3 pix=$4 params=$5
    shift 5
    ffmpeg $q -f lavfi -i "$source" -frames:v "$frames" -pix_fmt "$pix" "$@" \
        -c:v libx265 -x265-params "log-level=error:$params" -f hevc "$name.hevc" || return
    ffmpeg $q -flags:v +bitexact -i "$name.hevc" -f framemd5 "$name.hevc.framemd5"
    echo "made $name.hevc ($(wc -c < "$name.hevc") bytes)"
}

# Speed clips: x265 preset medium at a movie-like bitrate, 1080p.
make hevc_1080p8 12 "$grain" yuv420p "" -preset medium -b:v 5M
make hevc_1080p10 12 "$grain" yuv420p10le "" -preset medium -b:v 5M

# Tools x265 can produce, small and short.
make p_only 10 "$src" yuv420p "bframes=0:keyint=30"
make bframes 16 "$src" yuv420p "bframes=4:b-pyramid=1:ref=4:keyint=30"
make main10 12 "$src" yuv420p10le "bframes=3"
make nosao_nodeblock 10 "$src" yuv420p "no-sao=1:no-deblock=1"
make deblock_offsets 10 "$src" yuv420p "deblock=-3,3"
make weighted 12 "$src,fade=in:0:12" yuv420p "weightp=1:weightb=1:bframes=3"
make weighted10 12 "$src,fade=out:0:12" yuv420p10le "weightp=1:weightb=1:bframes=3"
make open_gop 24 "$src" yuv420p "keyint=8:min-keyint=8:open-gop=1:bframes=3"
make closed_gop 20 "$src" yuv420p "keyint=8:min-keyint=8:open-gop=0:bframes=3"
make lossless 6 "$src" yuv420p "lossless=1"
make tskip 8 "$src" yuv420p "tskip=1:rdoq-level=0"
make crop 8 "testsrc2=size=330x186:rate=25" yuv420p "bframes=2"
make gray 8 "$src" gray "bframes=2"
make slices 8 "$src" yuv420p "slices=4:bframes=2"
make nowpp 8 "$src" yuv420p "wpp=0:bframes=2"
make amp_rect 8 "$src" yuv420p "amp=1:rect=1:bframes=2:tu-intra-depth=3:tu-inter-depth=3"
make ctu16 8 "$src" yuv420p "ctu=16:min-cu-size=8:bframes=2"
# ffmpeg 8.1 filters chroma of 16x16 CTBs differently from the HM reference
# decoder (and the spec): ctu16.hevc.md5 holds HM's per-picture md5s, which
# the test prefers. Remake it with HM's TAppDecoder if the stream changes.
make ctu32 8 "$src" yuv420p "ctu=32:bframes=2:max-tu-size=16"
make scaling 8 "$src" yuv420p "scaling-list=default:bframes=2"
make cip 8 "$src" yuv420p "constrained-intra=1:bframes=2"
make merge_level 8 "$src" yuv420p "bframes=2:max-merge=5"

# A Matroska file (10-bit, B-frames) with the shared testkit reference.
ffmpeg $q -f lavfi -i "$src" -frames:v 12 -pix_fmt yuv420p10le -c:v libx265 \
    -x265-params log-level=error:bframes=3 hevc10.mkv
ffmpeg $q -flags:v +bitexact -i hevc10.mkv -map 0:v:0 -f framemd5 hevc10.mkv.v.framemd5
ffprobe -v error -print_format json -show_streams -show_format -show_chapters \
    -show_packets -show_data hevc10.mkv > hevc10.mkv.probe.json
python3 -I ../../../tools/trim_probe.py hevc10.mkv.probe.json
python3 -I ../../../tools/make_ref.py hevc10.mkv.probe.json
rm -f hevc10.mkv.probe.json
echo "made hevc10.mkv"
