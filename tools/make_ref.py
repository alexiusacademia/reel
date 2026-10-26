# Turns ffprobe's JSON for a fixture (F.probe.json) into F.ref.json, a
# simpler form that Tessel's fromJson reads straight into the testkit
# module's structs: Reel's own codec names, numbers as numbers, the codec
# setup bytes (extradata) as hex. Tests compare Reel's demuxers with it,
# and decoder tests use it to cut packets out of files.
#
# Author: Alexius Academia
# Date: 2026-10-25
import json, re, sys

NO_TIME = -9223372036854775807

CODECS = {
    "h264": "h264", "hevc": "hevc", "mpeg1video": "mpeg1", "mpeg2video": "mpeg2",
    "mpeg4": "mpeg4", "mjpeg": "mjpeg", "vp8": "vp8", "vp9": "vp9", "av1": "av1",
    "theora": "theora", "prores": "prores", "rawvideo": "rawvideo", "png": "png",
    "aac": "aac", "mp3": "mp3", "mp2": "mp2", "mp1": "mp1", "flac": "flac",
    "vorbis": "vorbis", "opus": "opus", "alac": "alac", "ac3": "ac3", "eac3": "eac3",
    "dts": "dts", "pcm_alaw": "alaw", "pcm_mulaw": "ulaw",
    "subrip": "srt", "ass": "ass", "ssa": "ass", "webvtt": "webvtt", "mov_text": "tx3g",
    "text": "text", "hdmv_pgs_subtitle": "pgs", "dvd_subtitle": "dvdsub",
    "dvb_subtitle": "dvbsub",
}


def num(v, default=0):
    if v is None:
        return default
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return default


def fnum(v, default=-1.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def hexdump_to_hex(text):
    # ffprobe's dump lines: "00000000: 0142 c00d ffe1 ...  .B......"
    out = []
    for line in (text or "").splitlines():
        m = re.match(r"^[0-9a-f]{8}: ((?:[0-9a-f]{2,4} ?)+)", line)
        if m:
            out.append(m.group(1).replace(" ", ""))
    return "".join(out)


def pcm_format(name):
    m = re.match(r"pcm_([suf])(\d+)(le|be)?(planar)?$", name or "")
    if not m:
        return {"bits": 16, "float": False, "bigEndian": False, "signed": True}
    kind, bits, endian, _ = m.groups()
    return {"bits": int(bits), "float": kind == "f", "bigEndian": endian == "be",
            "signed": kind != "u"}


def rate(text):
    try:
        a, b = text.split("/")
        return int(a), int(b)
    except Exception:
        return 0, 1


def main(path):
    with open(path) as f:
        probe = json.load(f)
    fmt = probe.get("format", {})
    tracks = []
    for s in probe.get("streams", []):
        name = s.get("codec_name", "")
        codec = CODECS.get(name)
        if codec is None:
            codec = "pcm" if name.startswith("pcm_") else "unknown:" + name
        kind = s.get("codec_type", "other")
        if kind == "data" or kind == "attachment":
            kind = "other"
        tb = s.get("time_base", "1/1000").split("/")
        timescale = int(tb[1]) // max(1, int(tb[0])) if len(tb) == 2 else 1000
        fps_num, fps_den = rate(s.get("avg_frame_rate", "0/1"))
        if fps_num == 0:
            fps_num, fps_den = rate(s.get("r_frame_rate", "0/1"))
        sar = s.get("sample_aspect_ratio", "1:1").split(":")
        tags = s.get("tags", {})
        disp = s.get("disposition", {})
        side = s.get("side_data_list", [])
        rotation = 0
        for sd in side:
            if "rotation" in sd:
                rotation = (-num(sd["rotation"])) % 360
        tracks.append({
            "index": s.get("index", len(tracks)),
            "kind": kind if kind in ("video", "audio", "subtitle") else "other",
            "codec": codec,
            "ffCodec": name,
            "profile": s.get("profile", ""),
            "timescale": timescale,
            "duration": num(s.get("duration_ts"), NO_TIME),
            "extraHex": hexdump_to_hex(s.get("extradata")),
            "width": num(s.get("width")),
            "height": num(s.get("height")),
            "sarNum": num(sar[0], 1) if len(sar) == 2 and num(sar[0]) > 0 else 1,
            "sarDen": num(sar[1], 1) if len(sar) == 2 and num(sar[1]) > 0 else 1,
            "fpsNum": fps_num,
            "fpsDen": fps_den,
            "rotation": rotation,
            "pixFmt": s.get("pix_fmt", ""),
            "sampleRate": num(s.get("sample_rate")),
            "channels": num(s.get("channels")),
            "channelLayout": s.get("channel_layout", ""),
            "bitsPerSample": num(s.get("bits_per_raw_sample")) or num(s.get("bits_per_sample")),
            "pcm": pcm_format(name),
            "language": "" if tags.get("language", "und") == "und" else tags.get("language", ""),
            "title": tags.get("title", ""),
            "isDefault": num(disp.get("default")) == 1,
            "isCover": num(disp.get("attached_pic")) == 1,
            "frames": num(s.get("nb_frames"), -1),
        })
    packets = []
    for p in probe.get("packets", []):
        packets.append({
            "track": p.get("stream_index", 0),
            "pts": num(p.get("pts"), NO_TIME),
            "dts": num(p.get("dts"), NO_TIME),
            "duration": num(p.get("duration")),
            "key": "K" in p.get("flags", ""),
            "pos": num(p.get("pos"), -1),
            "size": num(p.get("size")),
        })
    chapters = []
    for c in probe.get("chapters", []):
        chapters.append({"start": fnum(c.get("start_time"), 0.0),
                         "end": fnum(c.get("end_time")),
                         "title": c.get("tags", {}).get("title", "")})
    tags = {k.lower(): v for k, v in fmt.get("tags", {}).items()}
    ref = {
        "format": fmt.get("format_name", ""),
        "duration": fnum(fmt.get("duration")),
        "tags": tags,
        "tracks": tracks,
        "packets": packets,
        "chapters": chapters,
    }
    out = path.replace(".probe.json", ".ref.json")
    with open(out, "w") as f:
        json.dump(ref, f, indent=1)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
