# Outside checks of the files tests/export writes (build/scratch/export/out):
# ffprobe/ffmpeg are used as black-box oracles only.
#   - every file is read by ffprobe and decoded by ffmpeg without errors;
#   - remuxes: each stream's packets have the same payload hashes as the
#     source's (when the bytes aren't rewritten) and the same times;
#   - rewritten streams (Annex B → avcC, ADTS → raw) decode to the same
#     pictures / samples as the source;
#   - clips: durations and start times;
#   - GIFs: ffmpeg decodes flat.gif to exactly the frames the test made.
#
# Author: Alexius Academia
# Date: 2026-10-26
import json, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build/scratch/export/out")
FIX = os.path.join(ROOT, "tests/fixtures")
passed = 0
total = 0

def check(ok, what):
    global passed, total
    total += 1
    if ok:
        passed += 1
    else:
        print("FAIL:", what)

def run(args):
    p = subprocess.run(args, capture_output=True)
    # The null muxer's complaints about decode times are not decoding
    # errors (Matroska stores no dts; invisible frames have no pts).
    err = "\n".join(l for l in p.stderr.decode("utf-8", "replace").splitlines()
                    if "non monotonically increasing dts" not in l)
    return p.returncode, p.stdout, err

def probe(path):
    code, out, err = run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-show_chapters",
                          "-show_packets", "-show_data_hash", "md5", "-of", "json", path])
    return code, (json.loads(out) if code == 0 else {}), err

def packets(info, index):
    return [p for p in info.get("packets", []) if p["stream_index"] == index]

def decoded(path, spec, kind):
    fmt = ["-f", "framemd5"] if kind == "v" else ["-f", "framemd5"]
    code, out, err = run(["ffmpeg", "-v", "error", "-i", path, "-map", "0:" + spec, "-fps_mode", "passthrough"] + fmt + ["-"])
    hashes = [l.split(",")[-1].strip() for l in out.decode().splitlines() if l and not l.startswith("#")]
    return code, hashes, err

REMUX = [("h264_main_bframes.mp4", "bframes"), ("h264_high.mkv", "high"), ("h264.ts", "ts"),
         ("multi.mkv", "multi"), ("vp9.webm", "vp9"), ("hevc.mp4", "hevc"), ("av1.mkv", "av1"),
         ("subs_srt.mkv", "subsrt"), ("subs_tx3g.mp4", "subtx3g"), ("flac.flac", "flac"),
         ("opus.opus", "opus"), ("ac3.ac3", "ac3"), ("eac3.eac3", "eac3"), ("mp3_cbr.mp3", "mp3"),
         ("aac_mono.aac", "adts"), ("alac.m4a", "alac"), ("he_aac.m4a", "heaac")]
MKV_ONLY = [("subs_ass.mkv", "subass"), ("vorbis.ogg", "vorbis"), ("mpeg4.avi", "mpeg4"),
            ("pcm_s16.wav", "pcm"), ("mjpeg.avi", "mjpeg"), ("mpeg2.ts", "mpeg2ts")]
REWRITTEN = {"ts", "adts", "mpeg2ts"}

def compare(src, out, label):
    code, s, err = probe(src)
    code2, o, err2 = probe(out)
    check(code2 == 0 and not err2.strip(), "%s: ffprobe errors: %s" % (label, err2.strip()[:300]))
    if code2 != 0:
        return
    code3, _, err3 = run(["ffmpeg", "-v", "error", "-i", out, "-map", "0:v?", "-map", "0:a?", "-f", "null", "-"])
    check(code3 == 0 and not err3.strip(), "%s: ffmpeg decode errors: %s" % (label, err3.strip()[:300]))
    ss = [st for st in s["streams"] if st["codec_type"] in ("video", "audio", "subtitle")]
    os_ = o["streams"]
    check(len(ss) == len(os_), "%s: %d streams, source %d" % (label, len(os_), len(ss)))
    for a, b in zip(ss, os_):
        kind = a["codec_type"]
        same_codec = a["codec_name"] == b["codec_name"] or (kind == "subtitle")
        check(same_codec, "%s stream %d: %s vs %s" % (label, b["index"], b["codec_name"], a["codec_name"]))
        pa = packets(s, a["index"])
        pb = packets(o, b["index"])
        if kind == "subtitle" and a["codec_name"] == "mov_text" and not out.endswith("mp4"):
            # Empty timed-text samples (gaps) aren't written to Matroska.
            pa = [x for x in pa if int(x["size"]) > 2]
        check(len(pa) == len(pb), "%s stream %d (%s): %d packets, source %d" % (label, b["index"], kind, len(pb), len(pa)))
        rewritten = (label.split(".")[0] in REWRITTEN and a["codec_name"] in ("h264", "aac")) or kind == "subtitle"
        if not rewritten and len(pa) == len(pb):
            same = sum(1 for x, y in zip(pa, pb) if x.get("data_hash") == y.get("data_hash"))
            check(same == len(pa), "%s stream %d: %d of %d packet payloads equal" % (label, b["index"], same, len(pa)))
        # Times: compared after a constant shift (Matroska keeps times >= 0).
        ta = [float(x["pts_time"]) for x in pa if x.get("pts_time") not in (None, "N/A")]
        tb = [float(x["pts_time"]) for x in pb if x.get("pts_time") not in (None, "N/A")]
        if ta and tb and len(ta) == len(tb):
            shift = tb[0] - ta[0] if out.endswith(("mkv", "webm")) else 0.0
            worst = max(abs(x + shift - y) for x, y in zip(ta, tb))
            check(worst <= 0.0016, "%s stream %d: times off by %.4f s" % (label, b["index"], worst))
        if kind == "video" and rewritten:
            c1, h1, _ = decoded(src, "v:0", "v")
            c2, h2, _ = decoded(out, "v:0", "v")
            check(h1 and h1 == h2, "%s: decoded pictures differ (%d vs %d)" % (label, len(h2), len(h1)))
        if kind == "audio" and a["codec_name"] == "aac" and rewritten:
            c1, h1, _ = decoded(src, "a:0", "a")
            c2, h2, _ = decoded(out, "a:0", "a")
            # Frame by frame, ignoring the first (priming handled differently).
            common = min(len(h1), len(h2))
            same = sum(1 for x, y in zip(h1[2:common], h2[2:common]) if x == y)
            check(common > 4 and same == common - 2, "%s: decoded audio frames differ (%d of %d)" % (label, same, common - 2))

for src, label in REMUX:
    for ext in (["webm"] if label in ("vp9", "opus") else ["mkv"]) + ["mp4"]:
        compare(os.path.join(FIX, src), os.path.join(OUT, label + "." + ext), label + "." + ext)
for src, label in MKV_ONLY:
    compare(os.path.join(FIX, src), os.path.join(OUT, label + ".mkv"), label + ".mkv")

# Clips of h264_main_bframes.mp4, 1.5–1.9 s.
for name, want_start, lo, hi in [("clip_key.mp4", 0.0, 0.57, 0.65), ("clip_key.mkv", 0.0, 0.57, 0.65),
                                 ("clip_exact.mp4", 0.0, 0.39, 0.52)]:
    path = os.path.join(OUT, name)
    code, info, err = probe(path)
    check(code == 0 and not err.strip(), "%s: ffprobe: %s" % (name, err.strip()[:200]))
    if code == 0:
        d = float(info["format"].get("duration", "0"))
        check(lo <= d <= hi, "%s: duration %.3f not in %.2f..%.2f" % (name, d, lo, hi))
        v = [st for st in info["streams"] if st["codec_type"] == "video"][0]
        st = float(v.get("start_time", "0"))
        check(abs(st - want_start) < 0.03, "%s: video starts at %.3f, want %.2f" % (name, st, want_start))
    code, _, err = run(["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"])
    check(code == 0 and not err.strip(), "%s decodes: %s" % (name, err.strip()[:200]))
# The exact clip shows 10 pictures from 1.5 s in 0.4 s (ffmpeg honours the edit list).
code, frames, _ = decoded(os.path.join(OUT, "clip_exact.mp4"), "v:0", "v")
code2, src_frames, _ = decoded(os.path.join(FIX, "h264_main_bframes.mp4"), "v:0", "v")
check(len(frames) >= 10 and frames[:10] == src_frames[38:48], "clip_exact.mp4: first shown pictures are the source's 1.50 s on (%d)" % len(frames))
code, frames, _ = decoded(os.path.join(OUT, "clip_key.mp4"), "v:0", "v")
check(len(frames) >= 14 and frames[:14] == src_frames[33:47], "clip_key.mp4: pictures are the source's from 1.32 s (%d)" % len(frames))

# The exact Matroska clip: the 5 pictures before 1.5 s are invisible
# (ffmpeg gives them no pts); the rest show from 0.
code, info, err = probe(os.path.join(OUT, "clip_exact.mkv"))
vp = packets(info, 0)
hidden = [p for p in vp if p.get("pts_time") in (None, "N/A")]
shown = sorted(float(p["pts_time"]) for p in vp if p.get("pts_time") not in (None, "N/A"))
check(len(hidden) == 5 and shown and abs(shown[0] - 0.02) < 0.002, "clip_exact.mkv: %d hidden, first shown at %s" % (len(hidden), shown[:1]))
code, frames, _ = decoded(os.path.join(OUT, "clip_exact.mkv"), "v:0", "v")
# (ffmpeg's command line still outputs the invisible pictures, without
# times, so the shown ones follow them.)
check(len(frames) >= 15 and frames[5:15] == src_frames[38:48], "clip_exact.mkv: shown pictures are the source's from 1.52 s (%d)" % len(frames))

# Chapters survive (multi remux).
for name in ("multi.mkv", "multi.mp4"):
    code, info, _ = probe(os.path.join(OUT, name))
    check(len(info.get("chapters", [])) == 2, "%s: %d chapters" % (name, len(info.get("chapters", []))))

# GIFs.
for name in ("flat.gif", "noise.gif", "smooth.gif", "smooth_dither.gif", "video.gif"):
    code, _, err = run(["ffmpeg", "-v", "error", "-i", os.path.join(OUT, name), "-f", "null", "-"])
    check(code == 0 and not err.strip(), "%s decodes: %s" % (name, err.strip()[:200]))
code, raw, err = run(["ffmpeg", "-v", "error", "-i", os.path.join(OUT, "flat.gif"), "-fps_mode", "passthrough",
                      "-pix_fmt", "rgba", "-f", "rawvideo", "-"])
want = open(os.path.join(OUT, "flat.rgba"), "rb").read()
check(raw == want, "flat.gif: ffmpeg's frames equal the source frames (%d vs %d bytes)" % (len(raw), len(want)))
code, info, _ = probe(os.path.join(OUT, "video.gif"))
check(code == 0 and int(info["streams"][0]["width"]) == 160, "video.gif probes")

print("export check: %d of %d passed" % (passed, total))
sys.exit(0 if passed == total else 1)
