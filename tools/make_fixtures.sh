#!/bin/bash
# Makes the media files Reel's tests read, and what ffmpeg says about
# them (the reference answers), into tests/fixtures/. ffmpeg is a test
# tool only: Reel itself never runs it.
#
# For every file F:
#   F.probe.json   ffprobe's streams, format, chapters and packets
#   F.v.framemd5   (video) the md5 of each decoded picture, ffmpeg's
#                  framemd5 (8-bit planes Y, U, V, as core.pictureBytes)
#   F.v.yuv        (video, lossy codecs whose decoders may differ from
#                  ffmpeg's in the last bit) the first 10 decoded
#                  pictures, raw planar YUV, for a PSNR comparison
#   F.a.f32        (audio) ffmpeg's decoded samples: 32-bit float
#                  little-endian, interleaved, at the stream's own rate and
#                  channel count
#
# Run from anywhere: tools/make_fixtures.sh (takes about a minute).
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/.."
out=tests/fixtures
mkdir -p "$out"
q="-hide_banner -loglevel error -y"

# Sources: moving test picture with grain, and a two-tone sound.
vsrc() { # size rate seconds
    echo "-f lavfi -i testsrc2=size=$1:rate=$2:duration=$3,noise=alls=10:allf=t"
}
asrc() { # rate channels seconds
    echo "-f lavfi -i sine=frequency=440:sample_rate=$1:duration=$3,aformat=channel_layouts=$( [ "$2" = 1 ] && echo mono || ([ "$2" = 6 ] && echo 5.1 || echo stereo))"
}

make() { # name, then ffmpeg arguments
    local name=$1
    shift
    if [ -f "$out/$name" ] && [ -z "$FORCE" ]; then return; fi
    ffmpeg $q "$@" "$out/$name"
    echo "made $name"
}

# --- H.264 ---
make h264_baseline.mp4 $(vsrc 320x240 25 2) -c:v libx264 -profile:v baseline -g 25 -pix_fmt yuv420p
make h264_main_bframes.mp4 $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v libx264 -profile:v main -bf 3 -g 50 -pix_fmt yuv420p -c:a aac -b:a 96k
make h264_high.mkv $(vsrc 640x360 30 2) $(asrc 44100 2 2) -c:v libx264 -profile:v high -bf 2 -pix_fmt yuv420p -c:a libmp3lame
make h264_cavlc_slices.mp4 $(vsrc 320x240 25 1) -c:v libx264 -profile:v main -x264-params cabac=0:slices=4 -pix_fmt yuv420p
make h264_crop.mp4 $(vsrc 318x238 25 1) -c:v libx264 -profile:v high -pix_fmt yuv420p
make h264_weighted.mp4 -f lavfi -i "testsrc2=size=320x240:rate=25:duration=2,fade=in:0:25" -c:v libx264 -profile:v high -x264-params weightp=2:weightb=1 -bf 2 -pix_fmt yuv420p
make h264_intra.mp4 $(vsrc 320x240 25 1) -c:v libx264 -profile:v high -x264-params keyint=1 -pix_fmt yuv420p
make h264_720p.mp4 $(vsrc 1280x720 30 5) $(asrc 48000 2 5) -c:v libx264 -preset medium -profile:v high -pix_fmt yuv420p -c:a aac
make h264_1080p.mp4 $(vsrc 1920x1080 30 3) -c:v libx264 -preset medium -profile:v high -pix_fmt yuv420p
make h264.ts $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v libx264 -profile:v main -bf 2 -pix_fmt yuv420p -c:a aac
make h264_fragmented.mp4 $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +frag_keyframe+empty_moov+default_base_moof
make h264_interlaced.ts $(vsrc 720x576 25 1) -c:v libx264 -flags +ildct+ilme -x264-params tff=1 -pix_fmt yuv420p

# --- Other video ---
make mpeg2.mpg $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v mpeg2video -b:v 1M -bf 2 -c:a mp2
make mpeg2.ts $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v mpeg2video -b:v 1M -c:a ac3
make mpeg1.mpg $(vsrc 320x240 25 2) -c:v mpeg1video -b:v 1M -bf 2
make mjpeg.avi $(vsrc 320x240 25 1) $(asrc 22050 1 1) -c:v mjpeg -q:v 4 -pix_fmt yuvj420p -c:a pcm_s16le
make mjpeg422.avi $(vsrc 320x240 25 1) -c:v mjpeg -q:v 4 -pix_fmt yuvj422p
make mpeg4.avi $(vsrc 320x240 25 2) $(asrc 44100 2 2) -c:v mpeg4 -vtag xvid -q:v 4 -bf 2 -c:a libmp3lame
make vp9.webm $(vsrc 320x240 25 2) $(asrc 48000 2 2) -c:v libvpx-vp9 -b:v 300k -c:a libopus
make vp8.webm $(vsrc 320x240 25 1) -c:v libvpx -b:v 300k
# IVF (tests/demux): 50 frames, a keyframe every 10.
make t.vp9.ivf -f lavfi -i testsrc2=size=320x240:rate=25 -t 2 -c:v libvpx-vp9 -g 10
make t.vp8.ivf -f lavfi -i testsrc2=size=320x240:rate=25 -t 2 -c:v libvpx -g 10
make t.av1.ivf -f lavfi -i testsrc2=size=320x240:rate=25 -t 2 -c:v libsvtav1 -g 10
make av1.mkv $(vsrc 320x240 25 1) -c:v libsvtav1
make hevc.mp4 $(vsrc 320x240 25 1) -c:v libx265 -tag:v hvc1 -x265-params log-level=error

# --- Audio ---
make pcm_s16.wav $(asrc 44100 2 2) -c:a pcm_s16le
make pcm_s24.wav $(asrc 48000 2 1) -c:a pcm_s24le
make pcm_f32.wav $(asrc 48000 1 1) -c:a pcm_f32le
make pcm_u8.wav $(asrc 8000 1 1) -c:a pcm_u8
make pcm_51.wav $(asrc 48000 6 1) -c:a pcm_s16le
make pcm.aiff $(asrc 44100 2 1) -c:a pcm_s16be
make mp3_cbr.mp3 $(asrc 44100 2 3) -c:a libmp3lame -b:a 128k -id3v2_version 3 -metadata title="Test Tone" -metadata artist="Reel"
make mp3_vbr_mono.mp3 $(asrc 22050 1 2) -c:a libmp3lame -q:a 4
make mp2.mp2 $(asrc 48000 2 2) -c:a mp2
make aac_lc.m4a $(asrc 44100 2 3) -c:a aac -b:a 128k -metadata title="AAC Tone"
make aac_mono.aac $(asrc 22050 1 2) -c:a aac
make aac_51.m4a $(asrc 48000 6 2) -c:a aac
make he_aac.m4a $(asrc 44100 2 2) -c:a aac_at -profile:a 4
make flac.flac $(asrc 44100 2 2) -c:a flac -metadata title="FLAC Tone"
make flac_24.flac $(asrc 96000 2 1) -c:a flac -sample_fmt s32
make flac_51.flac $(asrc 48000 6 1) -c:a flac
make vorbis.ogg $(asrc 44100 2 2) -c:a vorbis -strict -2
make opus.opus $(asrc 48000 2 2) -c:a libopus -b:a 96k
make opus_mono.ogg $(asrc 48000 1 2) -c:a libopus -b:a 24k
make alac.m4a $(asrc 44100 2 1) -c:a alac
make ac3.ac3 $(asrc 48000 6 1) -c:a ac3
make eac3.eac3 $(asrc 48000 2 1) -c:a eac3

# --- Subtitles ---
if [ ! -f "$out/subs.srt" ]; then
cat > "$out/subs.srt" <<'SRT'
1
00:00:00,500 --> 00:00:01,500
Hello, <i>world</i>!

2
00:00:01,600 --> 00:00:03,000
Two lines
of <b>text</b>

3
00:00:03,100 --> 00:00:04,000
<font color="#ff0000">Red</font> &amp; plain
SRT
echo "made subs.srt"
fi
make subs.ass -i "$out/subs.srt"
make subs.vtt -i "$out/subs.srt"
make subs_ass.mkv $(vsrc 320x240 25 4) -i "$out/subs.ass" -map 0 -map 1 -c:v libx264 -pix_fmt yuv420p -c:s ass -metadata:s:s:0 language=eng
make subs_srt.mkv $(vsrc 320x240 25 4) -i "$out/subs.srt" -map 0 -map 1 -c:v libx264 -pix_fmt yuv420p -c:s srt -metadata:s:s:0 language=fre
make subs_tx3g.mp4 $(vsrc 320x240 25 4) -i "$out/subs.srt" -map 0 -map 1 -c:v libx264 -pix_fmt yuv420p -c:s mov_text

# --- Containers with several tracks, chapters, cover art ---
if [ ! -f "$out/chapters.txt" ]; then
cat > "$out/chapters.txt" <<'CH'
;FFMETADATA1
title=Chapter Test
[CHAPTER]
TIMEBASE=1/1000
START=0
END=1000
title=Opening
[CHAPTER]
TIMEBASE=1/1000
START=1000
END=3000
title=Middle
CH
fi
make multi.mkv $(vsrc 320x240 25 3) $(asrc 48000 2 3) -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=3" -i "$out/chapters.txt" -map 0:v -map 1:a -map 2:a -map_metadata 3 -map_chapters 3 -c:v libx264 -pix_fmt yuv420p -c:a:0 aac -c:a:1 libopus -metadata:s:a:0 language=eng -metadata:s:a:0 title="Main" -metadata:s:a:1 language=jpn -metadata:s:a:1 title="Commentary"
make multi.mp4 $(vsrc 320x240 25 3) $(asrc 48000 2 3) -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=3" -i "$out/chapters.txt" -map 0:v -map 1:a -map 2:a -map_metadata 3 -map_chapters 3 -c:v libx264 -pix_fmt yuv420p -c:a aac -metadata:s:a:0 language=eng -metadata:s:a:1 language=jpn
if [ ! -f "$out/cover.jpg" ]; then
    ffmpeg $q -f lavfi -i "testsrc2=size=200x200" -frames:v 1 "$out/cover.jpg"
fi
make cover.mp3 $(asrc 44100 2 1) -i "$out/cover.jpg" -map 0 -map 1 -c:a libmp3lame -c:v copy -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" -metadata album="Reel Album"
make cover.m4a $(asrc 44100 2 1) -i "$out/cover.jpg" -map 0 -map 1 -c:a aac -c:v copy -disposition:v attached_pic -metadata album="Reel Album"
make cover.flac $(asrc 44100 2 1) -i "$out/cover.jpg" -map 0 -map 1 -c:a flac -c:v copy -disposition:v attached_pic -metadata album="Reel Album"
make mov.mov $(vsrc 320x240 25 1) $(asrc 48000 2 1) -c:v libx264 -pix_fmt yuv420p -c:a pcm_s16le
make rotated.mp4 -display_rotation 90 -i "$out/h264_baseline.mp4" -c copy

# --- References ---
for f in "$out"/*; do
    case "$f" in *.json|*.framemd5|*.yuv|*.f32|*.txt|*.jpg) continue ;; esac
    base="$f"
    [ -f "$base.probe.json" ] && [ -z "$FORCE" ] && continue
    ffprobe -v error -print_format json -show_streams -show_format -show_chapters -show_packets -show_data "$f" > "$base.probe.json" || true
    # (-show_data adds each packet's bytes too; keep only the streams' extradata.)
    python3 -I tools/trim_probe.py "$base.probe.json"
    python3 -I tools/make_ref.py "$base.probe.json"
    if true; then
        codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" | head -1)
        disp=$(ffprobe -v error -select_streams v:0 -show_entries stream_disposition=attached_pic -of default=nw=1:nk=1 "$f" | head -1)
        if [ -n "$codec" ] && [ "$disp" != "1" ]; then
            ffmpeg $q -flags:v +bitexact -noautorotate -i "$f" -map 0:v:0 -an -sn -f framemd5 "$base.v.framemd5" || true
            case "$codec" in
                mpeg1video|mpeg2video|mpeg4|mjpeg|vp8|vp9|av1|hevc)
                    ffmpeg $q -noautorotate -i "$f" -map 0:v:0 -an -sn -frames:v 10 -f rawvideo "$base.v.yuv" || true ;;
            esac
        fi
    fi
    if [ -n "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f")" ]; then
        ffmpeg $q -i "$f" -map 0:a:0 -vn -sn -c:a pcm_f32le -f f32le "$base.a.f32" || true
    fi
    echo "probed $(basename "$f")"
done
du -sh "$out"
