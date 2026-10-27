#!/bin/bash
# Publishes Reel for macOS, Windows or both: builds the installers, uploads
# them, writes the release feed, and puts the new download links on the website.
#
#   tools/publish.sh                  macOS and Windows
#   tools/publish.sh macos            one system (or: windows)
#   tools/publish.sh --skip-build     upload the installers already in build/dist
#   tools/publish.sh --no-website     don't commit and push website/downloads.json
#   tools/publish.sh --dry-run        show what would be uploaded, without doing it
#
# The version is the one in tessel.toml: change it there first. Needs `gcloud`
# signed in and the bucket made once with tools/gcs-setup.sh. The website
# deploys itself: Netlify builds website/ on every push to main, so this script
# commits website/downloads.json (and nothing else) and pushes it.
#
# What ends up where (see packaging/publish.env):
#   gs://<bucket>/updates/<version>/Reel-<version>.dmg
#   gs://<bucket>/updates/<version>/Reel-<version>-setup.exe
#   gs://<bucket>/updates/latest.json      the feed: newest version, link and checksum per system
#   website/downloads.json                 the same feed, for the download buttons
#
# Author: Alexius Academia
# Date: 2026-10-27
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source packaging/publish.env; set +a

build=1
website=1
dry=0
systems=()
for arg in "$@"; do
    case "$arg" in
        macos|windows) systems+=("$arg") ;;
        --skip-build) build=0 ;;
        --no-website) website=0 ;;
        --dry-run) dry=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
[ ${#systems[@]} -gt 0 ] || systems=(macos windows)
run() { if [ "$dry" = 1 ]; then echo "   (dry run) $*"; else "$@"; fi; }

version="$(sed -n 's/^version = "\(.*\)"/\1/p' tessel.toml | head -1)"
remote="gs://$REEL_GCS_BUCKET/updates"
feed="build/dist/latest.json"
mkdir -p build/dist
# The feed as it is now (a system not published this time keeps its entry).
rm -f "$feed"
curl -fsS "$REEL_PUBLIC_BASE/updates/latest.json" -o "$feed" 2>/dev/null \
    || { [ -f website/downloads.json ] && cp website/downloads.json "$feed"; } \
    || rm -f "$feed"   # the first release: tools/feed.py starts an empty feed

for sys in "${systems[@]}"; do
    if [ "$sys" = macos ]; then
        file="build/dist/Reel-$version.dmg"
        [ "$build" = 0 ] || tools/package.sh
        [ -f "$file" ] || { echo "error: $file isn't there (run without --skip-build)" >&2; exit 1; }
        xcrun stapler validate "$file" > /dev/null || { echo "error: $file isn't notarized" >&2; exit 1; }
    else
        file="build/dist/Reel-$version-setup.exe"
        [ "$build" = 0 ] || tools/package-windows.sh
        [ -f "$file" ] || { echo "error: $file isn't there (run without --skip-build)" >&2; exit 1; }
    fi
    name="$(basename "$file")"
    url="$REEL_PUBLIC_BASE/updates/$version/$name"
    echo "==> uploading $name"
    run gcloud storage cp "$file" "$remote/$version/$name" --cache-control="public, max-age=31536000, immutable"
    python3 tools/feed.py "$feed" "$sys" "$version" "$url" "$file"
    if [ "$dry" = 0 ]; then
        got="$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)"
        want="$(shasum -a 256 "$file" | cut -d' ' -f1)"
        [ "$got" = "$want" ] || { echo "error: what's online isn't what was built ($url)" >&2; exit 1; }
        echo "→ online and checked: $url"
    fi
done

echo "==> updating the feed"
run gcloud storage cp "$feed" "$remote/latest.json" --cache-control="no-cache, max-age=0" --content-type="application/json"
if [ "$dry" = 1 ]; then
    cat "$feed"
    exit 0
fi
for sys in "${systems[@]}"; do
    online="$(curl -fsS "$REEL_PUBLIC_BASE/updates/latest.json?t=$RANDOM" | python3 -c "import json,sys; print(json.load(sys.stdin)['$sys']['version'])")"
    [ "$online" = "$version" ] || { echo "error: the feed online says $sys $online, not $version" >&2; exit 1; }
done
cp "$feed" website/downloads.json

if [ "$website" = 1 ]; then
    echo "==> putting the links on the website"
    if git diff --quiet -- website/downloads.json && git ls-files --error-unmatch website/downloads.json > /dev/null 2>&1; then
        echo "→ website/downloads.json hasn't changed"
    else
        git add website/downloads.json
        git commit -q -m "Downloads: Reel $version for ${systems[*]}" -- website/downloads.json
        git push -q
        echo "→ pushed; Netlify deploys $REEL_SITE_URL in about a minute"
    fi
fi
echo "→ done"
