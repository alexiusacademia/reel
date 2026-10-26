#!/bin/bash
# Downloads the libvpx VP8 test vectors (vp80-00-comprehensive-001…018,
# vp80-01…06 sets, each .ivf with its .md5 of every shown frame) into
# build/conformance/vp8theora/vp8/ and lists them in names.txt, which
# tests/vp8 reads.
#
# Run from ~/Dev/reel: tests/vp8/fixtures/conformance.sh
#
# Author: Alexius Academia
# Date: 2026-10-25

set -e
cd "$(dirname "$0")/../../.."
dir=build/conformance/vp8theora/vp8
mkdir -p "$dir"
bucket="https://storage.googleapis.com/storage/v1/b/downloads.webmproject.org/o?prefix=test_data/libvpx/vp80-&maxResults=500"
curl -s "$bucket" | python3 -I -c "import json,sys; [print(i['name']) for i in json.load(sys.stdin).get('items',[])]" > "$dir/list.txt"
while read -r n; do
    f="$dir/$(basename "$n")"
    [ -f "$f" ] || curl -s -o "$f" "https://storage.googleapis.com/downloads.webmproject.org/$n"
done < "$dir/list.txt"
ls "$dir"/*.ivf | xargs -n1 basename | sed 's/\.ivf$//' > "$dir/names.txt"
echo "$(wc -l < "$dir/names.txt") vectors in $dir"
