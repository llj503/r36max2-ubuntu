#!/bin/bash
# dev-vol.sh - the rk817 'Master' control is steep (-42 dB at 55%); find a level
# that is actually audible and replay the test.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

echo "=== every control on card 0 ==="
S 'for n in $(amixer -c 0 scontrols | sed -E "s/.*\x27(.*)\x27.*/\1/"); do printf "  %-28s %s\n" "$n" "$(amixer -c 0 sget "$n" 2>/dev/null | grep -E "Values|Item0|Mono|Front" | tr "\n" " ")"; done'

echo "=== raise the levels ==="
S "amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1 && echo '  Master -> 230'
   amixer -c 0 sset 'Front Left' 255 >/dev/null 2>&1; amixer -c 0 sset 'Front Right' 255 >/dev/null 2>&1
   amixer -c 0 sget 'Master' | tail -2
   amixer -c 0 contents | grep -A3 'Playback Mux' | tail -1"

echo "=== 3 beeps at the new level ==="
S 'for i in 1 2 3; do timeout 1 speaker-test -D plughw:0,0 -c 2 -t sine -f 880 -l 1 >/dev/null 2>&1; sleep 0.8; done; echo done'
echo "=== and a 4-second pink-noise sweep ==="
S 'timeout 4 speaker-test -D plughw:0,0 -c 2 -t wav -l 1 >/dev/null 2>&1; echo done'
