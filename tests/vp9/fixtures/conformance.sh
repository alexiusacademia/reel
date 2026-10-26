#!/bin/bash
# Downloads the libvpx VP9 test vectors (vp90/91/92/93-2-*.webm|ivf and
# their .md5, the list in libvpx's test/test_vectors.cc) into
# build/conformance/vp9/, and copies each into an IVF file in
# build/conformance/vp9/ivf/ (ffmpeg -c copy) for tests/vp9 to read.
#
# Run from ~/Dev/reel: tests/vp9/fixtures/conformance.sh
#
# Author: Alexius Academia
# Date: 2026-10-25

cd "$(dirname "$0")/../../.."
dir=build/conformance/vp9
mkdir -p "$dir/ivf"
base=https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx
list="$dir/names.txt"
if [ ! -f "$list" ]; then
    curl -sfL https://raw.githubusercontent.com/webmproject/libvpx/main/test/test_vectors.cc |
        grep -o '"vp9[0-9]-[^"]*"' | tr -d '"' | sort -u > "$list"
fi
while read n; do
    [ -f "$dir/$n" ] || curl -sfL -o "$dir/$n" "$base/$n" || echo "missing $n"
    [ -f "$dir/$n.md5" ] || curl -sfL -o "$dir/$n.md5" "$base/$n.md5" || echo "missing $n.md5"
    b="${n%.*}"
    if [ ! -s "$dir/ivf/$b.ivf" ] || [ $(stat -f %z "$dir/ivf/$b.ivf") -le 32 ]; then
        case "$n" in
            *.ivf) cp "$dir/$n" "$dir/ivf/$b.ivf" ;;
            # -copyinkf: some vectors start with intra-only frames.
            *) ffmpeg -hide_banner -loglevel error -y -i "$dir/$n" -c copy -copyinkf -f ivf "$dir/ivf/$b.ivf" ;;
        esac
    fi
done < "$list"
echo "$(ls "$dir/ivf" | wc -l) vectors in $dir/ivf"
