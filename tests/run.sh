#!/bin/bash
# Runs every module test: tests/<name>/main.tsl, each ending with a line
# "<name>: N of M passed". Makes the fixtures first if they're missing.
# `tests/run.sh name1 name2` runs only those. Exits 1 if any check failed.
#
# Author: Alexius Academia
# Date: 2026-10-25

cd "$(dirname "$0")/.."
[ -f tests/fixtures/h264_baseline.mp4.ref.json ] || tools/make_fixtures.sh || exit 1
fail=0
wanted="$*"
for t in tests/*/main.tsl; do
    dir=$(dirname "$t")
    name=$(basename "$dir")
    if [ -n "$wanted" ] && [[ " $wanted " != *" $name "* ]]; then continue; fi
    out=$(tessel run "$dir" 2>&1)
    line=$(echo "$out" | grep -E "^$name: [0-9]+ of [0-9]+ passed" | tail -1)
    if [ -z "$line" ]; then
        echo "$name: did not finish"
        echo "$out" | tail -15
        fail=1
        continue
    fi
    echo "$line"
    echo "$out" | grep "^time " | sed 's/^/    /'
    counts=$(echo "$line" | sed -E 's/.*: ([0-9]+) of ([0-9]+).*/\1 \2/')
    if [ "${counts% *}" != "${counts#* }" ]; then echo "$out" | grep FAIL | head -20; fail=1; fi
done
exit $fail
