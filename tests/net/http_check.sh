#!/bin/bash
# Runs tests/net/http (net over real HTTP) against tests/net/server.py,
# which it starts on a free local port and stops again (by its PID).
# Needs python3. Prints "net-http: N of M passed"; exits 1 on failures.
#
# Author: Alexius Academia
# Date: 2026-10-26

cd "$(dirname "$0")/../.."
[ -d tests/net/fixtures ] || tests/net/make_fixtures.sh || exit 1
mkdir -p build/scratch/net
port=$((20000 + RANDOM % 20000))
python3 -I tests/net/server.py $port tests/net/fixtures 2>/dev/null &
server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -f build/scratch/net/radio_check.mp3 build/scratch/net/radio_check.mp3.part' EXIT
sleep 0.5
tessel build tests/net/http -o build/scratch/net/http_check >/dev/null || exit 1
out=$(build/scratch/net/http_check $port 2>&1)
echo "$out" | grep -E "^(FAIL|net-http|time )"
line=$(echo "$out" | grep -E "^net-http: [0-9]+ of [0-9]+ passed")
[ -n "$line" ] || { echo "$out" | tail -10; exit 1; }
counts=$(echo "$line" | sed -E 's/.*: ([0-9]+) of ([0-9]+).*/\1 \2/')
[ "${counts% *}" = "${counts#* }" ]
