#!/bin/bash
# Makes the wma test's own small clips (tests/wma/fixtures/: WMA 1 and 2
# from ffmpeg's encoders at several rates and bitrates) and ffmpeg's
# decoded samples for them (F.a.f32: 32-bit float, interleaved), and the
# same references for the downloaded samples in build/conformance/wma/
# (into build/scratch/wma/refs/; for WMA Lossless also F.a.s32, 32-bit
# integers, for the bit-exact check). ffmpeg is a test tool only.
#
# Run from anywhere: tests/wma/make_fixtures.sh (FORCE=1 remakes).
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/wma/fixtures
conf=build/conformance/wma
refs=build/scratch/wma/refs
mkdir -p "$out" "$refs"
q="-hide_banner -loglevel error -y"

# "Music": a chord with vibrato, clicks every 0.4 s (short blocks), hiss,
# stereo with a correlated and a panned part (M/S).
music() { # rate
    echo "aevalsrc=exprs='0.25*sin(2*PI*(330+3*sin(2*PI*5*t))*t)+0.15*sin(2*PI*495*t)+0.1*sin(2*PI*3960*t)+if(lt(mod(t\,0.4)\,0.004)\,0.8*sin(2*PI*1800*t)*exp(-300*mod(t\,0.4))\,0)+0.04*(random(0)*2-1)|0.25*sin(2*PI*(330+3*sin(2*PI*5*t))*t)+0.12*sin(2*PI*660*t)+0.06*sin(2*PI*3960*t)+if(lt(mod(t\,0.4)\,0.004)\,0.8*sin(2*PI*1800*t)*exp(-300*mod(t\,0.4))\,0)+0.04*(random(1)*2-1)':s=$1:d=0.45"
}

make() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    ffmpeg $q -i "$out/$name" -map 0:a:0 -c:a pcm_f32le -f f32le "$out/$name.a.f32"
    echo "made $name"
}

make v2_music_128k.wma -f lavfi -i "$(music 44100)" -c:a wmav2 -b:a 128k
make v2_music_48k.wma -f lavfi -i "$(music 44100)" -c:a wmav2 -b:a 48k
make v2_mono_22k.wma -f lavfi -i "$(music 22050)" -ac 1 -c:a wmav2 -b:a 32k
make v2_8k.wma -f lavfi -i "$(music 8000)" -ac 1 -c:a wmav2 -b:a 24k
make v1_music_64k.wma -f lavfi -i "$(music 44100)" -c:a wmav1 -b:a 64k
make v1_mono_16k.wma -f lavfi -i "$(music 16000)" -ac 1 -c:a wmav1 -b:a 24k
make v2_32k_stereo.wma -f lavfi -i "$(music 32000)" -c:a wmav2 -b:a 40k

for f in "$conf"/*.wma "$conf"/*.wmv "$conf"/*.asf; do
    [ -f "$f" ] || continue
    b="$refs/$(basename "$f")"
    [ -f "$b.a.f32" ] && [ -z "$FORCE" ] && continue
    ffmpeg $q -i "$f" -map 0:a:0 -c:a pcm_f32le -f f32le "$b.a.f32" 2>/dev/null || rm -f "$b.a.f32"
    codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" | head -1)
    if [ "$codec" = wmalossless ]; then
        ffmpeg $q -i "$f" -map 0:a:0 -c:a pcm_s32le -f s32le "$b.a.s32"
    fi
done
du -sh "$out"
