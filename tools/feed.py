#!/usr/bin/env python3
# Puts one system's newest release into the release feed, keeping the
# other system's entry as it is. The feed is what the website's
# download buttons read.
#
#   tools/feed.py <feed.json> <macos|windows> <version> <url> <installer file> [notes url]
#
# Author: Alexius Academia
# Date: 2026-10-27
import hashlib, json, os, sys

feed_path, system, version, url, installer = sys.argv[1:6]
notes = sys.argv[6] if len(sys.argv) > 6 else ""
empty = {"version": "", "url": "", "sha256": "", "size": 0, "notes": ""}
feed = {"macos": dict(empty), "windows": dict(empty)}
if os.path.exists(feed_path):
    try:
        feed.update(json.load(open(feed_path)))
    except ValueError:
        pass
digest = hashlib.sha256(open(installer, "rb").read()).hexdigest()
feed[system] = {"version": version, "url": url, "sha256": digest,
                "size": os.path.getsize(installer), "notes": notes}
json.dump(feed, open(feed_path, "w"), indent=2)
open(feed_path, "a").write("\n")
print(f"{system}: {version}  {digest}")
