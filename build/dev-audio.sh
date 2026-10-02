#!/bin/bash
# dev-audio.sh - list the mixer, set a safe level, play a short test tone.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

echo "=== cards / pcm ==="
S 'cat /proc/asound/cards; echo; ls /dev/snd/; echo; aplay -L 2>/dev/null | head -12'

echo "=== mixer controls ==="
S 'amixer -c 0 scontrols 2>&1 | head -20; echo "---"; amixer -c 0 2>&1 | head -30'

echo "=== set ~60% and unmute ==="
S 'for c in Master "Speaker" "Headphone" PCM Lineout; do amixer -c 0 set "$c" 60% unmute >/dev/null 2>&1 && echo "  set $c"; done; amixer -c 0 contents 2>/dev/null | grep -A3 -E ";|values" | head -20'

echo "=== 3 秒白噪声（注意听）==="
S 'timeout 3 speaker-test -D plughw:0,0 -c 2 -t wav -r 48000 -l 1 2>&1 | tail -4'
echo "=== 左/右声道各 1 秒 ==="
S 'timeout 1 speaker-test -D plughw:0,0 -c 2 -t sine -f 440 -l 1 >/dev/null 2>&1; echo done'
