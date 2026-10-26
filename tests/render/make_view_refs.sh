#!/bin/bash
# Makes the render test's references for render.View: ffmpeg's eq, hue,
# crop, hflip, vflip and transpose filters (run as a black box) on the
# same 160×120 crop of mpeg2.mpg's first picture that make_refs.sh uses,
# then converted to RGB by swscale the same way (exact rounding, full
# chroma interpolation, "left" chroma siting). zlib-compressed RGB24.
#
# Run from the Reel folder: tests/render/make_view_refs.sh
#
# Author: Alexius Academia
# Date: 2026-10-26

set -e
cd "$(dirname "$0")/../.."
out=tests/render/fixtures
tmp=build/scratch/vfx/refs
mkdir -p "$out" "$tmp"
q="-hide_banner -loglevel error -y"
head -c 115200 tests/fixtures/mpeg2.mpg.v.yuv > "$tmp/m2.yuv"

# view yuv-filters out-size name [rgb-filters]
# Geometry filters (flips, transpose) run on the RGB result: on 4:2:0
# planes they would move chroma off its siting, while the renderer mirrors
# and turns the finished picture.
view() {
    post=""
    [ -n "$4" ] && post=",$4"
    ffmpeg $q -f rawvideo -pix_fmt yuv420p -s 320x240 -i "$tmp/m2.yuv" -frames:v 1 \
        -vf "crop=160:120:80:60,$1,scale=$2:flags=bilinear+accurate_rnd+full_chroma_int+bitexact:in_color_matrix=bt601:in_range=tv:in_chroma_loc=left,format=rgb24$post" \
        -f rawvideo "$tmp/$3.rgb"
    python3 -I -c "import sys,zlib;open(sys.argv[2],'wb').write(zlib.compress(open(sys.argv[1],'rb').read(),9))" "$tmp/$3.rgb" "$out/$3.rgb.z"
}

view "eq=brightness=0.08:contrast=1.3:saturation=1.4:gamma=1.2" 160:120 v_eq
view "eq=contrast=0.7:gamma=0.8:brightness=-0.05" 107:80 v_eq_scaled
view "hue=h=40:s=0.8" 160:120 v_hue
view "hue=h=-120:s=1.6" 160:120 v_hue2
view "crop=100:80:20:10" 100:80 v_crop
view "null" 160:120 v_hflip hflip
view "null" 160:120 v_vflip vflip
view "null" 256:192 v_hvflip_scaled hflip,vflip
view "null" 160:120 v_transpose1 transpose=1
view "null" 160:120 v_transpose2 transpose=2
view "hue=h=25:s=1.5" 160:120 v_hue_hflip_rot hflip,transpose=1
du -sh "$out"
