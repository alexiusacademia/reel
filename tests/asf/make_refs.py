# Makes ffprobe's answers for ASF files into F.asf.json, the form
# tests/asf reads with fromJson: the container's tags, duration and
# chapters, each stream (attached pictures apart: their md5 goes in
# "coverMd5") and every packet with its timestamps, key flag, size and the
# md5 of its bytes.
#
# Run: python3 -I tests/asf/make_refs.py OUT_DIR FILE...
#
# Author: Alexius Academia
# Date: 2026-10-25
import hashlib, json, os, re, subprocess, sys

NO_TIME = -9223372036854775807

CODECS = {
    "wmav1": "wmav1", "wmav2": "wmav2", "wmapro": "wmapro",
    "wmalossless": "wmalossless", "wmv1": "wmv1", "wmv2": "wmv2",
    "wmv3": "wmv3", "vc1": "vc1", "msmpeg4v3": "msmpeg4v3",
    "msmpeg4v2": "msmpeg4v2", "msmpeg4v1": "msmpeg4v1", "mp3": "mp3",
    "mp2": "mp2", "ac3": "ac3", "aac": "aac", "h264": "h264",
    "mpeg4": "mpeg4", "mjpeg": "mjpeg",
}


def num(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return default


def hexdump_to_hex(text):
    out = []
    for line in (text or "").splitlines():
        m = re.match(r"^[0-9a-f]{8}: ((?:[0-9a-f]{2,4} ?)+)", line)
        if m:
            out.append(m.group(1).replace(" ", ""))
    return "".join(out)


def probe(path, *extra):
    r = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json",
                        "-show_streams", "-show_format", "-show_chapters",
                        *extra, path], capture_output=True, text=True)
    return json.loads(r.stdout or "{}")


def main(out_dir, path):
    info = probe(path, "-show_data")
    pk = probe(path, "-show_packets", "-show_data_hash", "md5")
    streams = info.get("streams", [])
    fmt = info.get("format", {})
    tracks, cover_streams = [], set()
    cover_md5 = ""
    for s in streams:
        if num(s.get("disposition", {}).get("attached_pic")) == 1:
            cover_streams.add(s["index"])
            continue
        name = s.get("codec_name", "")
        codec = CODECS.get(name)
        if codec is None:
            codec = "pcm" if name.startswith("pcm_") else "unknown:" + name
        kind = s.get("codec_type", "other")
        sar = s.get("sample_aspect_ratio", "1:1").split(":")
        tags = s.get("tags", {})
        tracks.append({
            "index": s["index"], "kind": kind if kind in ("video", "audio") else "other",
            "codec": codec, "ffCodec": name, "tag": s.get("codec_tag", ""),
            "extraHex": hexdump_to_hex(s.get("extradata")),
            "width": num(s.get("width")), "height": num(s.get("height")),
            "sarNum": num(sar[0], 1) if len(sar) == 2 and num(sar[0]) > 0 else 1,
            "sarDen": num(sar[1], 1) if len(sar) == 2 and num(sar[1]) > 0 else 1,
            "sampleRate": num(s.get("sample_rate")), "channels": num(s.get("channels")),
            "bitrate": num(s.get("bit_rate")), "duration": num(s.get("duration_ts"), NO_TIME),
            "language": tags.get("language", ""),
        })
    packets = []
    for p in pk.get("packets", []):
        si = p.get("stream_index", 0)
        h = p.get("data_hash", "").split(":")[-1]
        if si in cover_streams:
            cover_md5 = h
            continue
        packets.append({"track": si, "pts": num(p.get("pts"), NO_TIME),
                        "dts": num(p.get("dts"), NO_TIME),
                        "key": "K" in p.get("flags", ""),
                        "size": num(p.get("size")), "md5": h})
    chapters = [{"start": float(c.get("start_time", 0)),
                 "title": c.get("tags", {}).get("title", "")}
                for c in info.get("chapters", [])]
    ref = {
        "format": fmt.get("format_name", ""),
        "duration": float(fmt.get("duration", -1) if fmt.get("duration") not in (None, "N/A") else -1),
        "tags": {k.lower(): v for k, v in fmt.get("tags", {}).items()},
        "tracks": tracks, "packets": packets, "chapters": chapters,
        "coverMd5": cover_md5,
    }
    with open(os.path.join(out_dir, os.path.basename(path) + ".asf.json"), "w") as f:
        json.dump(ref, f)


for p in sys.argv[2:]:
    main(sys.argv[1], p)
