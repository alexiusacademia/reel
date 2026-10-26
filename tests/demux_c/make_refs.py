# Makes the extra references tests/demux_c needs, beside testkit's
# F.ref.json: each stream's exact time base (ref.json keeps only a whole
# number of ticks per second) and the md5 of every packet's bytes, from
# ffprobe. Writes F.hashes.json into tests/demux_c/fixtures/ for the
# shared fixtures and for the extra files made by make_fixtures.sh here.
#
# Run: python3 -I tests/demux_c/make_refs.py FILE...
#
# Author: Alexius Academia
# Date: 2026-10-25
import json, os, subprocess, sys

out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

def main(path):
    probe = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams",
         "-show_format", "-show_packets", "-show_data_hash", "md5", path],
        check=True, capture_output=True, text=True).stdout)
    streams = probe.get("streams", [])
    tbs = []
    for s in streams:
        a, b = s.get("time_base", "1/1").split("/")
        tbs.append([int(a), int(b)])
    hashes = [[] for _ in streams]
    for p in probe.get("packets", []):
        h = p.get("data_hash", "")
        hashes[p["stream_index"]].append(h.split(":")[-1])
    name = os.path.basename(path)
    with open(os.path.join(out_dir, name + ".hashes.json"), "w") as f:
        json.dump({"timeBases": tbs, "hashes": hashes}, f)
    # Packets and tracks in testkit's form for files made here.
    if not os.path.exists(path + ".ref.json"):
        tmp = os.path.join(out_dir, name + ".probe.json")
        with open(tmp, "w") as f:
            subprocess.run(["ffprobe", "-v", "error", "-print_format", "json",
                            "-show_streams", "-show_format", "-show_chapters",
                            "-show_packets", "-show_data", path], check=True, stdout=f)
        tools = os.path.join(os.path.dirname(out_dir), "..", "..", "tools")
        subprocess.run([sys.executable, "-I", os.path.join(tools, "trim_probe.py"), tmp], check=True)
        subprocess.run([sys.executable, "-I", os.path.join(tools, "make_ref.py"), tmp], check=True)
        os.remove(tmp)

for p in sys.argv[1:]:
    main(p)
