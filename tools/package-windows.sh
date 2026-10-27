#!/bin/bash
# Makes Reel for Windows on this Mac: the installer Tessel builds with
# tessel build --windows --bundle (64-bit Windows 10 and 11; installs for the
# user, adds Reel to the Start menu and its document types, and an
# uninstaller; /S installs silently), as build/dist/Reel-<version>-setup.exe.
#
# The .exe isn't signed: that needs a Windows code-signing certificate, and until
# then Windows SmartScreen warns about it the first time it's opened.
#
# Author: Alexius Academia
# Date: 2026-10-27
set -euo pipefail
cd "$(dirname "$0")/.."
tessel="${TESSEL:-$HOME/.tessel/bin/tessel}"

version="$(sed -n 's/^version = "\(.*\)"/\1/p' tessel.toml | head -1)"
out="build/dist"
setup="$out/Reel-$version-setup.exe"

echo "==> Reel $version for Windows"
rm -rf build/win
mkdir -p build/win "$out"
"$tessel" build . --windows --bundle -o build/win/reel | tail -1
made="$(ls build/win/*Setup.exe 2>/dev/null | head -1)"
[ -n "$made" ] || { echo "error: no installer was made" >&2; ls build/win >&2; exit 1; }
file "$made" | grep -q "PE32+ executable (GUI) x86-64" || { echo "error: not a 64-bit Windows installer" >&2; exit 1; }
mv "$made" "$setup"
echo "→ $setup ($(du -sh "$setup" | cut -f1))"
shasum -a 256 "$setup"
