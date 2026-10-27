#!/bin/bash
# Makes Reel ready to hand out on macOS: the app bundle, signed with a
# Developer ID and the hardened runtime, in a disk image, notarized by Apple and
# stapled, so it opens on any Mac without a warning.
#
#   tools/package.sh                 sign with the Developer ID found in the keychain
#   tools/package.sh --no-notarize   sign and make the .dmg, but don't send it to Apple
#   tools/package.sh --adhoc         no Developer ID: an ad-hoc signature (for this Mac only)
#
# What it uses:
#   TESSEL                  the tessel command (default ~/.tessel/bin/tessel; it builds
#                           with the version tessel.toml pins)
#   REEL_SIGN_IDENTITY   the certificate's name (default: "Developer ID Application")
#   REEL_NOTARY_PROFILE  a notarytool keychain profile (default: draftwork-notary), made once with
#       xcrun notarytool store-credentials "name" --apple-id you@example.com --team-id TEAMID
#
# The app's name, identifier, version and document types come from tessel.toml,
# its icon from icon.png. The result is build/dist/Reel-<version>.dmg
# (Apple silicon, as Tessel builds it).
#
# Author: Alexius Academia
# Date: 2026-10-27
set -euo pipefail
cd "$(dirname "$0")/.."
tessel="${TESSEL:-$HOME/.tessel/bin/tessel}"

identity="${REEL_SIGN_IDENTITY:-Developer ID Application}"
profile="${REEL_NOTARY_PROFILE:-draftwork-notary}"
notarize=1
for arg in "$@"; do
    case "$arg" in
        --no-notarize) notarize=0 ;;
        --adhoc) identity="-"; notarize=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
version="$(sed -n 's/^version = "\(.*\)"/\1/p' tessel.toml | head -1)"
app="build/bundle/Reel.app"
out="build/dist"
dmg="$out/Reel-$version.dmg"

echo "==> Reel $version"
rm -rf build/bundle
mkdir -p build/bundle "$out"
"$tessel" build . -o build/bundle/reel --bundle | tail -1
[ -d "$app" ] || { echo "error: $app wasn't made" >&2; ls build/bundle >&2; exit 1; }
plutil -lint "$app/Contents/Info.plist" > /dev/null

echo "→ signing ($identity)"
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$app"
else
    codesign --force --timestamp --options runtime --entitlements packaging/entitlements.plist --sign "$identity" "$app"
fi
codesign --verify --strict --verbose=2 "$app" 2>&1 | tail -2

if [ "$notarize" = 1 ]; then
    # The app first, so its ticket can be stapled to it before it goes in the
    # disk image (it then opens without asking Apple, even offline).
    zip="$out/Reel-$version.zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    echo "→ notarizing the app (profile $profile)"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait | tee "$out/notary-app.txt" | grep -E "id:|status:" | tail -2
    grep -q "status: Accepted" "$out/notary-app.txt"
    rm -f "$zip"
    xcrun stapler staple "$app" | tail -1
fi

echo "→ making the disk image"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto --noextattr --norsrc "$app" "$staging/Reel.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "Reel $version" -srcfolder "$staging" -ov -format UDZO "$dmg" > /dev/null
if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi
if [ "$notarize" = 1 ]; then
    echo "→ notarizing the disk image"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait | tee "$out/notary-dmg.txt" | grep -E "id:|status:" | tail -2
    grep -q "status: Accepted" "$out/notary-dmg.txt"
    xcrun stapler staple "$dmg" | tail -1
    xcrun stapler validate "$dmg" | tail -1
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg" 2>&1 | tail -2
fi
echo "→ $dmg ($(du -sh "$dmg" | cut -f1))"
shasum -a 256 "$dmg"
