#!/bin/bash
# Makes the HLS and DASH fixtures tests/net reads (into tests/net/fixtures)
# with ffmpeg, and ffprobe's packets for each (NAME.packets: one line per
# packet "kind pts_time size md5", read through ffmpeg's own HLS/DASH
# demuxers as a black-box reference). ffmpeg is a test tool only.
#
# Run from anywhere: tests/net/make_fixtures.sh (a few seconds).
#
# Author: Alexius Academia
# Date: 2026-10-26

set -e
cd "$(dirname "$0")"
out=fixtures
rm -rf "$out"
mkdir -p "$out"
q="-hide_banner -loglevel error -y"
# 6 s of small moving picture and a tone; a keyframe every 2 s so
# segments are 2 s long.
src="-f lavfi -i testsrc2=size=160x90:rate=25:duration=6 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=6"
venc="-c:v libx264 -profile:v main -bf 2 -g 50 -keyint_min 50 -sc_threshold 0 -pix_fmt yuv420p -b:v 20k -maxrate 30k -bufsize 60k"
aenc="-c:a aac -b:a 24k -ac 2"

packets() { # input, output name
    ffprobe -v error -allowed_extensions ALL -protocol_whitelist file,crypto,data -show_data_hash md5 -show_packets -of json "$1" \
        | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["packets"]:
    print(p["codec_type"], p.get("pts_time", "nan"), p["size"], p["data_hash"].replace("MD5:", ""))
' > "$2"
}

# 1. Two variants in MPEG-TS, a master playlist.
mkdir -p $out/hls_ts
ffmpeg $q $src $venc $aenc -map 0:v -map 1:a -map 0:v -map 1:a \
    -filter:v:1 scale=96:54 -b:v:1 12k \
    -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$out/hls_ts/v%v_%d.ts" \
    -master_pl_name master.m3u8 -var_stream_map "v:0,a:0 v:1,a:1" "$out/hls_ts/v%v.m3u8"
packets $out/hls_ts/v0.m3u8 $out/hls_ts/v0.packets
packets $out/hls_ts/v1.m3u8 $out/hls_ts/v1.packets

# 2. AES-128 with an IV in the playlist, and with the sequence-number IV.
printf '0123456789abcdef' > $out/key.bin
mkdir -p $out/hls_aes $out/hls_aes_seq
printf 'key.bin\n%s\n000102030405060708090a0b0c0d0e0f\n' "$PWD/$out/key.bin" > $out/keyinfo_iv
cp $out/key.bin $out/hls_aes/key.bin
cp $out/key.bin $out/hls_aes_seq/key.bin
ffmpeg $q $src $venc $aenc -f hls -hls_time 2 -hls_playlist_type vod -hls_key_info_file $out/keyinfo_iv \
    -hls_segment_filename "$out/hls_aes/s%d.ts" "$out/hls_aes/index.m3u8"
rm $out/keyinfo_iv
packets $out/hls_aes/index.m3u8 $out/hls_aes/index.packets

# 2b. AES-128 with no IV attribute: each segment's IV is its media
#     sequence number (RFC 8216 §5.2), made with openssl from hls_ts/v0.
(
    echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-TARGETDURATION:2"
    echo "#EXT-X-MEDIA-SEQUENCE:7"; echo '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"'
    for i in 0 1 2; do
        openssl aes-128-cbc -e -K $(xxd -p $out/key.bin) -iv $(printf '%032x' $((7 + i))) \
            -in $out/hls_ts/v0_$i.ts -out $out/hls_aes_seq/s$((7 + i)).ts
        echo "#EXTINF:2.000000,"; echo "s$((7 + i)).ts"
    done
    echo "#EXT-X-ENDLIST"
) > $out/hls_aes_seq/index.m3u8

# 3. fMP4 segments with EXT-X-MAP.
mkdir -p $out/hls_fmp4
ffmpeg $q $src $venc $aenc -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_type fmp4 \
    -hls_fmp4_init_filename init.mp4 -hls_segment_filename "$out/hls_fmp4/s%d.m4s" "$out/hls_fmp4/index.m3u8"
packets $out/hls_fmp4/index.m3u8 $out/hls_fmp4/index.packets

# 4. One file with byte ranges.
mkdir -p $out/hls_single
ffmpeg $q $src $venc $aenc -f hls -hls_time 2 -hls_playlist_type vod -hls_flags single_file \
    "$out/hls_single/index.m3u8"

packets $out/hls_single/index.m3u8 $out/hls_single/index.packets

# 5. Separate audio rendition (EXT-X-MEDIA).
mkdir -p $out/hls_alt
ffmpeg $q $src $venc $aenc -map 0:v -map 1:a -f hls -hls_time 2 -hls_playlist_type vod \
    -hls_segment_filename "$out/hls_alt/s%v_%d.ts" -master_pl_name master.m3u8 \
    -var_stream_map "v:0,agroup:aud a:0,agroup:aud,language:eng,name:English,default:yes" "$out/hls_alt/p%v.m3u8"

packets $out/hls_alt/p0.m3u8 $out/hls_alt/p0.packets
packets $out/hls_alt/pEnglish.m3u8 $out/hls_alt/pEnglish.packets

# 6. A second encode whose timestamps start again (for a discontinuity).
mkdir -p $out/hls_b
ffmpeg $q -f lavfi -i testsrc2=size=160x90:rate=25:duration=4 -f lavfi -i sine=frequency=880:sample_rate=48000:duration=4 \
    $venc $aenc -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$out/hls_b/b%d.ts" "$out/hls_b/index.m3u8"

# A playlist that goes on from hls_ts/v0 into hls_b after a
# discontinuity, and three snapshots of a live sliding window over
# hls_ts/v0 (the last one ends the stream).
cat > $out/disc.m3u8 <<'M3U'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:2.0,
hls_ts/v0_0.ts
#EXTINF:2.0,
hls_ts/v0_1.ts
#EXT-X-DISCONTINUITY
#EXTINF:2.0,
hls_b/b0.ts
#EXTINF:2.0,
hls_b/b1.ts
#EXT-X-ENDLIST
M3U
for k in 1 2 3; do
    {
        echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-TARGETDURATION:2"
        echo "#EXT-X-MEDIA-SEQUENCE:$((k - 1))"
        echo "#EXT-X-PROGRAM-DATE-TIME:2026-10-26T10:00:0$((2 * (k - 1))).000Z"
        for i in $(seq $((k - 1)) $((k == 3 ? 2 : k))); do echo "#EXTINF:2.0,"; echo "hls_ts/v0_$i.ts"; done
        [ $k = 3 ] && echo "#EXT-X-ENDLIST"
    } > $out/live$k.m3u8
done

# 7. DASH: SegmentTemplate with SegmentTimeline, with $Number$ and
#    duration, and one file per representation (SegmentBase + sidx).
mkdir -p $out/dash_tl $out/dash_num $out/dash_single
ffmpeg $q $src $venc $aenc -map 0:v -map 1:a -f dash -seg_duration 2 -use_timeline 1 -use_template 1 \
    -adaptation_sets "id=0,streams=v id=1,streams=a" "$out/dash_tl/manifest.mpd"
ffmpeg $q $src $venc $aenc -map 0:v -map 1:a -f dash -seg_duration 2 -use_timeline 0 -use_template 1 \
    -adaptation_sets "id=0,streams=v id=1,streams=a" "$out/dash_num/manifest.mpd"
ffmpeg $q $src $venc $aenc -map 0:v -map 1:a -f dash -seg_duration 2 -single_file 1 \
    -adaptation_sets "id=0,streams=v id=1,streams=a" "$out/dash_single/manifest.mpd"
# ffprobe here has no DASH demuxer: the reference is each
# representation's init + segments joined.
for r in 0 1; do
    cat $out/dash_tl/init-stream$r.m4s $out/dash_tl/chunk-stream$r-*.m4s > $out/joined.mp4
    packets $out/joined.mp4 $out/dash_tl/stream$r.packets
done
for r in 0 1; do
    cat $out/dash_num/init-stream$r.m4s $out/dash_num/chunk-stream$r-*.m4s > $out/joined.mp4
    packets $out/joined.mp4 $out/dash_num/stream$r.packets
done
rm $out/joined.mp4

# 8. One fragmented MP4 with a global sidx, described by SegmentBase.
mkdir -p $out/dash_base
ffmpeg $q $src $venc -an -f mp4 -movflags frag_keyframe+empty_moov+default_base_moof+global_sidx $out/dash_base/video.mp4
python3 -I - $out/dash_base <<'PY'
import struct, sys
d = sys.argv[1]
b = open(d + "/video.mp4", "rb").read()
p = 0
boxes = []
while p + 8 <= len(b):
    size, = struct.unpack(">I", b[p:p+4])
    boxes.append((b[p+4:p+8].decode(), p, size))
    p += size
sidx = [x for x in boxes if x[0] == "sidx"][0]
moov = [x for x in boxes if x[0] == "moov"][0]
init_end = moov[1] + moov[2] - 1
open(d + "/manifest.mpd", "w").write("""<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT6S" minBufferTime="PT2S" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011">
  <Period>
    <AdaptationSet contentType="video" mimeType="video/mp4">
      <Representation id="v" bandwidth="60000" width="160" height="90" codecs="avc1.4d400b">
        <BaseURL>video.mp4</BaseURL>
        <SegmentBase indexRange="%d-%d">
          <Initialization range="0-%d"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
""" % (sidx[1], sidx[1] + sidx[2] - 1, init_end))
PY
packets $out/dash_base/video.mp4 $out/dash_base/video.packets

du -sh $out
