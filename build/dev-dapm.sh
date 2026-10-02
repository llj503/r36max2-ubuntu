#!/bin/bash
# dev-dapm.sh - why is it silent? dump the ASoC widget power states while a tone
# is playing, plus the amp-enable GPIO and the codec register map.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; ls /sys/kernel/debug/asoc/ 2>/dev/null'
CARD=$(S 'ls /sys/kernel/debug/asoc/ 2>/dev/null | grep -v -E "^(devices_component|platforms|codecs)$" | head -1' | tr -d "\r")
echo "ASoC card dir: [$CARD]"

echo "=== start a 12s tone in the background, then inspect ==="
S 'nohup sh -c "timeout 12 speaker-test -D plughw:0,0 -c 2 -t sine -f 440 -l 5 >/dev/null 2>&1" >/dev/null 2>&1 & echo started'
sleep 2

echo "--- DAPM widgets (name / power) while playing ---"
S "cat /sys/kernel/debug/asoc/$CARD/dapm_widget 2>/dev/null | awk '{printf \"  %-28s %s\n\", \$1, \$3}' | head -40"

echo "--- jack + mux + switches ---"
S 'amixer -c 0 contents | grep -iE "jack|mux|Internal|Headphone|Switch" -A2 | grep -E "name=|values=|Item0" | head -20'

echo "--- pinctrl/gpio for the speaker amp (GPIO3_A7 = 103) and hp detect (GPIO2_C6 = 86) ---"
S 'grep -iE "gpio-86|gpio-103|hp-det|spk|amp" /sys/kernel/debug/gpio 2>/dev/null | head -10; echo "-- all claimed gpios --"; grep -E "^\s+gpio-[0-9]+" /sys/kernel/debug/gpio | head -25'

echo "--- PCM runtime state ---"
S 'cat /proc/asound/card0/pcm0p/substatus 2>/dev/null | grep -E "^state|^avail|^hw_ptr|^prepare|^trigger" ; echo "-- i2s --"; cat /proc/asound/card0/i2s* 2>/dev/null | head -5'

echo "--- codec regmap (rk817) ---"
S 'ls -d /sys/kernel/debug/regmap/*rk817* /sys/kernel/debug/regmap/*20* 2>/dev/null | head -5; for d in /sys/kernel/debug/regmap/*; do case "$d" in *rk817*|*0020*) echo "== $d"; head -24 "$d/registers" 2>/dev/null;; esac; done'

echo "--- try forcing the headphone path on (the speakers are fed from HPOL/HPOR) ---"
S 'amixer -c 0 sset "Headphones" on 2>&1 | tail -1; amixer -c 0 sset "HP" on 2>&1 | tail -1; amixer -c 0 controls | head -20'
sleep 6
echo "=== done ==="
