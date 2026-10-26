#!/bin/bash
# Makes the aac test's own fixtures into tests/aac/fixtures/: clips that
# use the coding tools the plain sine fixtures don't (short windows, TNS,
# M/S, intensity, PNS, pulses), more channel layouts (3.0, 4.0, 7.1, PCE
# 2.1 and 6.1), HE-AAC in ADTS (implicit SBR) and HE-AAC v2 (PS), and
# ffmpeg's decoded samples for each (F.a.f32) plus F.ref.json for the
# MP4 ones. ffmpeg is a test tool only.
#
# Run from the Reel folder: tests/aac/make_fixtures.sh
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../.."
out=tests/aac/fixtures
mkdir -p "$out"
q="-hide_banner -loglevel error -y"

# "Music": a chord with vibrato, clicks every 0.4 s (transients for short
# windows and TNS), hiss (noise for PNS), stereo with a correlated and a
# panned part (M/S and intensity).
music="aevalsrc=exprs='0.25*sin(2*PI*(330+3*sin(2*PI*5*t))*t)+0.15*sin(2*PI*495*t)+0.1*sin(2*PI*3960*t)+if(lt(mod(t\,0.4)\,0.004)\,0.8*sin(2*PI*1800*t)*exp(-300*mod(t\,0.4))\,0)+0.04*(random(0)*2-1)|0.25*sin(2*PI*(330+3*sin(2*PI*5*t))*t)+0.12*sin(2*PI*660*t)+0.06*sin(2*PI*3960*t)+if(lt(mod(t\,0.4)\,0.004)\,0.8*sin(2*PI*1800*t)*exp(-300*mod(t\,0.4))\,0)+0.04*(random(1)*2-1)':s=44100:d=1.2"

# Per-channel tones (100 Hz apart) to check the channel order.
tones() { # layout channels seconds
    local e="0.3*sin(2*PI*200*t)"
    for i in $(seq 2 $2); do e="$e|0.3*sin(2*PI*$((100 + 100 * i))*t)"; done
    echo "aevalsrc=exprs='$e':s=48000:d=$3:c=$1"
}

make() { # name, then ffmpeg arguments
    local name=$1
    shift
    ffmpeg $q "$@" "$out/$name"
    echo "made $name"
}

make lc_music.m4a -f lavfi -i "$music" -c:a aac -b:a 96k -aac_coder twoloop
make lc_music_lowrate.m4a -f lavfi -i "$music" -c:a aac -b:a 40k -aac_pns 1 -aac_is 1 -aac_ms 1 -aac_tns 1
make lc_music_apple.m4a -f lavfi -i "$music" -c:a aac_at -b:a 128k
make lc_30.m4a -f lavfi -i "$(tones 3.0 3 0.3)" -c:a aac -b:a 128k
make lc_40.m4a -f lavfi -i "$(tones 4.0 4 0.3)" -c:a aac -b:a 128k
make lc_71.m4a -f lavfi -i "$(tones 7.1 8 0.3)" -c:a aac -b:a 256k
make lc_21_pce.m4a -f lavfi -i "$(tones 2.1 3 0.3)" -c:a aac -b:a 128k
make lc_61_pce.m4a -f lavfi -i "$(tones 6.1 7 0.3)" -c:a aac -b:a 192k
make he_music.aac -f lavfi -i "$music" -c:a aac_at -profile:a 4 -b:a 48k -f adts
make he_music.m4a -f lavfi -i "$music" -c:a aac_at -profile:a 4 -b:a 48k
make hev2_music.m4a -f lavfi -i "$music" -c:a aac_at -profile:a 28 -b:a 32k
make hev2_music.aac -f lavfi -i "$music" -c:a aac_at -profile:a 28 -b:a 32k -f adts
make he_mono.m4a -f lavfi -i "$music" -ac 1 -c:a aac_at -profile:a 4 -b:a 32k

for f in "$out"/*.m4a "$out"/*.aac; do
    ffmpeg $q -i "$f" -map 0:a:0 -c:a pcm_f32le -f f32le "$f.a.f32"
    case "$f" in *.m4a)
        ffprobe -v error -print_format json -show_streams -show_format -show_chapters -show_packets -show_data "$f" > "$f.probe.json"
        python3 -I tools/trim_probe.py "$f.probe.json"
        python3 -I tools/make_ref.py "$f.probe.json"
        rm -f "$f.probe.json" ;;
    esac
done
du -sh "$out"

# Excerpts of ISO/IEC 14496-26 conformance streams (download them into
# build/conformance/aac from standards.iso.org, see the aac report) for
# tools no encoder here produces: pulse data (al04), coupling channel
# elements (al07), PS with IPD/OPD (ps_04) and 34 bands (ps_06), and
# downsampled SBR (sr_24_2_fsaac24).
conf=build/conformance/aac
# (source, excerpt, start, seconds: PS only starts after a while there.)
for spec in "al04_44.mp4 conf_pulse.m4a 0 0.6" "al07_44.mp4 conf_cce.m4a 0 0.3" "al_sbr_ps_04_new.mp4 conf_ps_ipd.m4a 3.2 1.0" "al_sbr_ps_06_new.mp4 conf_ps_34.m4a 6.8 1.0" "al_sbr_sr_24_2_fsaac24.mp4 conf_sbr_down.m4a 0 0.6"; do
    set -- $spec
    [ -f "$conf/$1" ] || continue
    ffmpeg $q -ss "$3" -i "$conf/$1" -map 0:a:0 -c copy -t "$4" "$out/$2"
    f="$out/$2"
    ffmpeg $q -i "$f" -map 0:a:0 -c:a pcm_f32le -f f32le "$f.a.f32"
    ffprobe -v error -print_format json -show_streams -show_format -show_chapters -show_packets -show_data "$f" > "$f.probe.json"
    python3 -I tools/trim_probe.py "$f.probe.json"
    python3 -I tools/make_ref.py "$f.probe.json"
    rm -f "$f.probe.json"
    echo "made $2"
done
du -sh "$out"
