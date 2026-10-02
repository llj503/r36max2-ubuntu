#!/bin/bash
# dev-audio2.sh - route to the internal speakers (Playback Mux = SPK) and replay.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

echo "=== jack / mux state before ==="
S "amixer -c 0 contents | grep -iE 'jack|mux|Speaker|Headphone' -A2 | head -24"

echo "=== switch to the internal speakers ==="
S "amixer -c 0 sset 'Playback Mux' 'SPK' 2>&1 | tail -2
   amixer -c 0 sset 'Internal Speakers' on 2>&1 | tail -2
   amixer -c 0 sset 'Master' 55% >/dev/null
   amixer -c 0 contents | grep -A3 'Playback Mux' | tail -2"

echo "=== 5 秒左声道 440Hz ==="
S 'timeout 5 aplay -q -D plughw:0,0 /dev/urandom -f S16_LE -c 2 -r 8000 >/dev/null 2>&1 &
   sleep 0.3
   sox -n -t alsa plughw:0,0 synth 2 sine 440 remix 1,0 2>/dev/null || timeout 2 speaker-test -D plughw:0,0 -c 2 -t sine -f 440 -l 1 >/dev/null 2>&1
   wait 2>/dev/null; echo left-done'

echo "=== 2 秒双声道噪声 ==="
S 'timeout 2 speaker-test -D plughw:0,0 -c 2 -t wav -l 1 >/dev/null 2>&1; echo noise-done'

echo "=== 录音通路自检（1 秒）==="
S 'timeout 1 arecord -q -D plughw:0,0 -f S16_LE -c 2 -r 16000 /tmp/rec.wav 2>&1 | tail -2; ls -l /tmp/rec.wav 2>/dev/null'
