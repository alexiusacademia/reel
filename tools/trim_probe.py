# Drops the per-packet "data" hex dumps that ffprobe -show_data adds
# (keeping the streams' "extradata"), so probe files stay small.
#
# Author: Alexius Academia
# Date: 2026-10-25
import json, sys
path = sys.argv[1]
with open(path) as f:
    probe = json.load(f)
for p in probe.get("packets", []):
    p.pop("data", None)
    p.pop("data_hash", None)
with open(path, "w") as f:
    json.dump(probe, f, indent=1)
