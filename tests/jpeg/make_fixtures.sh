#!/bin/bash
# Makes the JPEG images tests/jpeg reads, with references: ffmpeg's
# framemd5 (and raw planes for samplings Reel spreads), djpeg's RGB for
# colour-converted images. Tools: ffmpeg, libjpeg-turbo's cjpeg/djpeg,
# Python with PIL (for CMYK and EXIF). Test tools only.
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/jpeg/fixtures
tmp=build/scratch/jpeg
mkdir -p "$out" "$tmp"
q="-hide_banner -loglevel error -y"
ffmpeg $q -f lavfi -i "testsrc2=size=160x120,noise=alls=12:allf=t" -frames:v 1 "$tmp/src.ppm"
ffmpeg $q -f lavfi -i "testsrc2=size=157x93" -frames:v 1 "$tmp/odd.ppm"
md5() { ffmpeg $q -flags:v +bitexact -noautorotate -i "$1" -f framemd5 "$1.v.framemd5"; }
raw() { ffmpeg $q -i "$1" -f rawvideo "$1.raw"; }

cjpeg -quality 85 -progressive -sample 2x2 "$tmp/src.ppm" > "$out/prog420.jpg"; md5 "$out/prog420.jpg"
cjpeg -quality 90 -progressive -sample 1x1 -restart 3B "$tmp/src.ppm" > "$out/prog444_restart.jpg"; md5 "$out/prog444_restart.jpg"
cjpeg -quality 80 -progressive -sample 2x2 "$tmp/odd.ppm" > "$out/prog_odd.jpg"; md5 "$out/prog_odd.jpg"
cjpeg -quality 85 -sample 2x2 -restart 2B "$tmp/odd.ppm" > "$out/restart_odd.jpg"; md5 "$out/restart_odd.jpg"
cjpeg -quality 85 -grayscale "$tmp/src.ppm" > "$out/gray.jpg"; md5 "$out/gray.jpg"
cjpeg -quality 85 -sample 2x1 -optimize "$tmp/src.ppm" > "$out/b422_opt.jpg"; md5 "$out/b422_opt.jpg"
cjpeg -quality 85 -sample 4x1 "$tmp/src.ppm" > "$out/b411.jpg"; raw "$out/b411.jpg"
cjpeg -quality 85 -sample 1x2 "$tmp/src.ppm" > "$out/b440.jpg"; raw "$out/b440.jpg"
cjpeg -quality 90 -rgb "$tmp/src.ppm" > "$out/rgb.jpg"; djpeg -ppm "$out/rgb.jpg" > "$out/rgb.jpg.ppm"
python3 -I - "$tmp/src.ppm" "$out" <<'PY'
import site, sys
# PIL lives in the user's site packages, which -I leaves out; the inputs
# are images this script just made.
sys.path.append(site.getusersitepackages())
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
im.convert("CMYK").save(out + "/cmyk.jpg", quality=92)
ex = Image.Exif()
ex[0x0112] = 6
im.save(out + "/exif6.jpg", quality=80, exif=ex.tobytes())
PY
djpeg -ppm "$out/cmyk.jpg" > "$tmp/cmyk.ppm"
python3 -I - "$tmp/cmyk.ppm" "$out/cmyk.jpg.ppm" <<'PY'
import site, sys
# PIL lives in the user's site packages, which -I leaves out; the inputs
# are images this script just made.
sys.path.append(site.getusersitepackages())
from PIL import Image
# djpeg gives CMYK as stored; turn it into the RGB a viewer shows (Adobe
# inverted CMYK: R = C * K / 255).
im = Image.open(sys.argv[1])
im.convert("RGB").save(sys.argv[2])
PY
md5 "$out/exif6.jpg"
# ffmpeg's decoding of the cover art, for an exact comparison.
md5 tests/fixtures/cover.jpg && mv tests/fixtures/cover.jpg.v.framemd5 "$out/cover.jpg.v.framemd5"
# Two fields of an interlaced Motion-JPEG frame (160×60 each).
ffmpeg $q -f lavfi -i "testsrc2=size=160x60" -frames:v 1 "$tmp/f1.ppm"
ffmpeg $q -f lavfi -i "testsrc2=size=160x60,negate" -frames:v 1 "$tmp/f2.ppm"
cjpeg -quality 85 "$tmp/f1.ppm" > "$out/field1.jpg"; md5 "$out/field1.jpg"
cjpeg -quality 85 "$tmp/f2.ppm" > "$out/field2.jpg"; md5 "$out/field2.jpg"
# Timing: 1280×720 Motion-JPEG (JPEG images back to back), not kept.
ffmpeg $q -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=1,noise=alls=8:allf=t" -c:v mjpeg -q:v 4 -pix_fmt yuvj420p -f mjpeg "$tmp/hd720.mjpeg"
ls -la "$out"
