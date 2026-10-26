#!/bin/bash
# Runs tests/export (which writes its files to build/scratch/export/out),
# then checks those files with ffprobe/ffmpeg (tests/export/check.py).
#
# Author: Alexius Academia
# Date: 2026-10-26
cd "$(dirname "$0")/../.."
tessel build tests/export -o build/scratch/export/t || exit 1
./build/scratch/export/t | grep -E "^(FAIL|export:)"
python3 -I tests/export/check.py
