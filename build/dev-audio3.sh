#!/bin/bash
# dev-audio3.sh - the external amp is wired to the codec's HP outputs
# (routing says: "Speaker Amp INL" <- "HPOL"), so with Playback Mux = SPK the HP
# drivers may be muted and the amp gets nothing. Play a DIFFERENT pitch per mux
# setting so the user can tell which path actually makes sound.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

CARD=$(S 'ls /sys/kernel/debug/asoc/ 2>/dev/null | grep -iv -E "devices_component|platforms|codecs" | head -1' | tr -d '\r')
echo "card dir: [$CARD]"

echo "=== widget power states (idle) ==="
S "grep -A1 -E '^(DAC|HPOL|HPOR|Speaker Amp|Internal Speakers|Headphones|I2S|Playback)' /sys/kernel/debug/asoc/$CARD/dapm_widget 2>/dev/null | grep -E '^[A-Za-z]|power' | paste - - | sed 's/^/  /' | head -24"

echo
echo "=== A) Playback Mux = HP,  Master 230, tone 660 Hz x 4s ==="
S "amixer -c 0 sset 'Playback Mux' 'HP' >/dev/null 2>&1
   amixer -c 0 sset 'Internal Speakers' on >/dev/null 2>&1
   amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1
   amixer -c 0 contents | grep -A3 'Playback Mux' | tail -1
   timeout 4 speaker-test -D plughw:0,0 -c 2 -t sine -f 660 -l 3 >/dev/null 2>&1; echo '  (A done)'"

sleep 2
echo "=== B) Playback Mux = SPK, tone 330 Hz x 4s ==="
S "amixer -c 0 sset 'Playback Mux' 'SPK' >/dev/null 2>&1
   amixer -c 0 contents | grep -A3 'Playback Mux' | tail -1
   timeout 4 speaker-test -D plughw:0,0 -c 2 -t sine -f 330 -l 3 >/dev/null 2>&1; echo '  (B done)'"

sleep 2
echo "=== C) SPK + 强制把 HP 也点亮（若无此控件则跳过）==="
S "amixer -c 0 sset 'Headphone' on >/dev/null 2>&1 || echo '  no Headphone switch control'
   timeout 4 speaker-test -D plughw:0,0 -c 2 -t wav -l 2 >/dev/null 2>&1; echo '  (C done)'"

echo "=== substatus after the runs ==="
S 'cat /proc/asound/card0/pcm0p/substatus 2>/dev/null | sed -n "1,12p"'
echo "=== i2s clock / mclk actually requested ==="
S 'cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | grep -iE "i2s|mclk|audio" | head -12'
