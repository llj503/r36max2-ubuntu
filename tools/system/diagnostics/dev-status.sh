#!/bin/bash
# dev-status.sh - one-shot status of the device: apt job, tools, services, disk.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

echo "=== apt job ==="
S 'tail -2 /root/setup.log; if pgrep -x apt-get >/dev/null; then echo "STILL RUNNING"; else echo "APT FINISHED"; fi'

echo "=== tools ==="
S 'for b in git gcc g++ make python3 evtest jstest aplay speaker-test htop tmux vim jq rsync; do p=$(command -v "$b" 2>/dev/null); [ -n "$p" ] && echo "  ok   $b" || echo "  --   $b"; done'

echo "=== services ==="
S 'for s in systemd-udevd systemd-networkd r36-wpa@wlan0 ssh avahi-daemon systemd-timesyncd r36-status-screen r36-bootlog; do printf "  %-22s %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done; systemctl --failed --no-legend --plain | head -5'

echo "=== system ==="
S 'echo -n "  ip: "; ip -4 -br addr show wlan0 | awk "{print \$3}"; echo -n "  signal: "; iw dev wlan0 link | awk "/signal/{print \$2\" \"\$3}"; echo -n "  batt: "; cat /sys/class/power_supply/battery/capacity; echo -n "  temp: "; echo "$(cat /sys/class/thermal/thermal_zone0/temp)"; echo -n "  disk: "; df -h / | tail -1 | awk "{print \$2\" used \"\$3\" avail \"\$4}"; echo -n "  mem: "; free -m | awk "/Mem/{print \$2\" MiB total, \"\$7\" avail\"}"; echo -n "  clock: "; date -Is'
