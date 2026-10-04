#!/bin/bash
# dev-audio4.sh - pin down which mux position actually drives the speakers, with
# two clearly separated tones, and fix the power-button behaviour on the way.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

echo "=== power button: 短按=suspend, 长按=关机 ==="
sshpass -p "$PW" scp -q /mnt/e/ubuntu/config/rootfs/99-r36-power.conf "$DEV:/etc/systemd/logind.conf.d/99-r36-power.conf" 2>/dev/null || \
  S 'mkdir -p /etc/systemd/logind.conf.d' 
S 'mkdir -p /etc/systemd/logind.conf.d'
sshpass -p "$PW" scp -q /mnt/e/ubuntu/config/rootfs/99-r36-power.conf "$DEV:/etc/systemd/logind.conf.d/99-r36-power.conf"
S 'systemctl restart systemd-logind; grep -E "HandlePowerKey|IdleAction" /run/systemd/logind.conf.d/* 2>/dev/null | head -4; echo "logind: $(systemctl is-active systemd-logind)"'

echo
echo "=== 现在放两段音，注意分辨：先 3 秒 HP(660Hz)，停 3 秒，再 3 秒 SPK(330Hz) ==="
S 'amixer -c 0 sset Master 230,230 >/dev/null 2>&1
   echo -n "  mux during phase A: "; amixer -c 0 sget "Playback Mux" | grep Item0
   amixer -c 0 sset "Playback Mux" "HP" >/dev/null 2>&1
   timeout 3 speaker-test -D plughw:0,0 -c 2 -t sine -f 660 -l 2 >/dev/null 2>&1
   sleep 3
   echo -n "  mux during phase B: "; amixer -c 0 sget "Playback Mux" | grep Item0
   amixer -c 0 sset "Playback Mux" "SPK" >/dev/null 2>&1
   timeout 3 speaker-test -D plughw:0,0 -c 2 -t sine -f 330 -l 2 >/dev/null 2>&1
   echo "  both phases played"'
S 'amixer -c 0 sget "Playback Mux" | grep Item0'
