#!/bin/bash
# Makes the render test's colour and scaling references with ffmpeg:
# RGB pictures (zlib-compressed, 3 bytes a pixel) converted by swscale
# from crops of the fixtures' raw YUV, with exact rounding, full chroma
# interpolation and MPEG-2's "left" chroma siting, which is what
# render.toRgba does. Inputs that aren't in tests/fixtures (10-bit, 4:4:4)
# are made the same way the test makes them.
#
# Run from the Reel folder: tests/render/make_refs.sh
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/render/fixtures
tmp=build/scratch/render/refs
mkdir -p "$out" "$tmp"
q="-hide_banner -loglevel error -y"
crop="crop=160:120:80:60"

# conv input-file pix_fmt size matrix range flags out-size name
conv() {
    ffmpeg $q -f rawvideo -pix_fmt "$2" -s "$3" -i "$1" -frames:v 1 \
        -vf "$crop,scale=$7:flags=$6+accurate_rnd+full_chroma_int+bitexact:in_color_matrix=$4:in_range=$5:in_chroma_loc=left,format=rgb24" \
        -f rawvideo "$tmp/$8.rgb"
    python3 -I -c "import sys,zlib;open(sys.argv[2],'wb').write(zlib.compress(open(sys.argv[1],'rb').read(),9))" "$tmp/$8.rgb" "$out/$8.rgb.z"
}

m2=tests/fixtures/mpeg2.mpg.v.yuv
mj=tests/fixtures/mjpeg422.avi.v.yuv
# First pictures only.
head -c 115200 "$m2" > "$tmp/m2.yuv"
head -c 153600 "$mj" > "$tmp/mj.yuv"

conv "$tmp/m2.yuv" yuv420p 320x240 bt601 tv bilinear 160:120 m2_601_tv
conv "$tmp/m2.yuv" yuv420p 320x240 bt709 tv bilinear 160:120 m2_709_tv
conv "$tmp/m2.yuv" yuv420p 320x240 bt709 pc bilinear 160:120 m2_709_pc
conv "$tmp/m2.yuv" yuv420p 320x240 bt2020 tv bilinear 160:120 m2_2020_tv
conv "$tmp/mj.yuv" yuv422p 320x240 bt601 pc bilinear 160:120 mj422_601_pc

# 10-bit 4:2:0 (sample·4 + (x + y) % 4) and 4:4:4 (chroma repeated 2×2),
# written as the test makes them.
python3 -I - "$tmp" <<'PY'
import sys, struct
tmp = sys.argv[1]
d = open(tmp + "/m2.yuv", "rb").read()
W, H = 320, 240
Y = d[:W*H]; U = d[W*H:W*H + W*H//4]; V = d[W*H + W*H//4:W*H*3//2]
def ten(plane, w, h):
    return b"".join(struct.pack("<H", plane[y*w + x] * 4 + (x + y) % 4) for y in range(h) for x in range(w))
open(tmp + "/m2_10.yuv", "wb").write(ten(Y, W, H) + ten(U, W//2, H//2) + ten(V, W//2, H//2))
def full(plane):
    return bytes(plane[(y//2)*(W//2) + x//2] for y in range(H) for x in range(W))
open(tmp + "/m2_444.yuv", "wb").write(Y + full(U) + full(V))
PY
conv "$tmp/m2_10.yuv" yuv420p10le 320x240 bt709 tv bilinear 160:120 m2_709_tv_10bit
conv "$tmp/m2_444.yuv" yuv444p 320x240 bt601 tv bilinear 160:120 m2_444_601_tv

# Scaled (bilinear down 1.5×, up 1.6×; area down 4×).
conv "$tmp/m2.yuv" yuv420p 320x240 bt601 tv bilinear 107:80 m2_601_tv_107x80
conv "$tmp/m2.yuv" yuv420p 320x240 bt601 tv bilinear 256:192 m2_601_tv_256x192
conv "$tmp/m2.yuv" yuv420p 320x240 bt601 tv area 40:30 m2_601_tv_40x30_area
du -sh "$out"
