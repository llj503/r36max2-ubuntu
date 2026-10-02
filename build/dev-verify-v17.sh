#!/bin/bash
# dev-verify-v17.sh - wait for the freshly flashed v17 to come up, then verify
# everything that v17 is supposed to carry, and grow the root partition.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=6 -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== waiting for it to boot ==="
for i in $(seq 1 30); do
  if S 'echo up' >/dev/null 2>&1; then echo "  reachable after $((i*5))s"; break; fi
  sleep 5
done
S 'echo up' >/dev/null 2>&1 || { echo "  NOT reachable yet - 屏幕现在显示什么？"; exit 1; }

echo
echo "=== identity / build ==="
S 'echo -n "  kernel : "; uname -r
   echo -n "  build  : "; cat /etc/r36max2-build-info
   echo -n "  boot   : "; uptime -s'

echo "=== GPU (the new thing in v17) ==="
S 'dmesg | grep -iE "panfrost|mali|gpu" | tail -8 | sed "s/^/  /"
   echo "  loaded: $(lsmod | awk "/panfrost/{print \"yes\"}" || true)"
   ls -l /dev/dri/ 2>/dev/null | sed "s/^/  /"'

echo "=== wifi / network ==="
S 'echo -n "  driver : "; dmesg | grep -m1 -i "RELEASE DATE" | sed "s/.*RELEASE DATE//"
   echo -n "  chipid : "; dmesg | grep -m1 -o "chip_id=.*"
   echo -n "  wlan0  : "; ip -br addr show wlan0
   echo -n "  link   : "; iw dev wlan0 link | head -1
   echo -n "  wpa    : "; systemctl is-active r36-wpa@wlan0
   ping -c2 -W2 223.5.5.5 2>&1 | tail -2 | sed "s/^/  /"'

echo "=== services / time / audio ==="
S 'systemctl --failed --no-pager | sed "s/^/  /"
   echo -n "  udevd     : "; systemctl is-active systemd-udevd
   echo -n "  timesyncd : "; systemctl is-active systemd-timesyncd; timedatectl | grep -i synchron | sed "s/^/              /"
   echo -n "  audio     : "; systemctl is-active r36-audio; amixer -c 0 sget Master 2>/dev/null | grep Front | head -1 | sed "s/^/              /"
   echo -n "  mux       : "; amixer -c 0 sget "Playback Mux" 2>/dev/null | grep Item0 | sed "s/^/              /"
   echo -n "  power key : "; grep -h HandlePowerKey /etc/systemd/logind.conf.d/99-r36-power.conf
   echo -n "  masked    : "; ls -l /etc/systemd/system/suspend.target /etc/systemd/system/sleep.target 2>/dev/null | awk "{print \$NF}" | tr "\n" " "'

echo "=== buttons ==="
S 'ls /dev/input/by-path/ 2>/dev/null | sed "s/^/  /"'

echo "=== grow the root partition to the whole card ==="
S 'df -h / | tail -1 | sed "s/^/  before: /"
   sh /usr/local/sbin/r36-expand-root 2>&1 | sed "s/^/  /"
   sleep 2; df -h / | tail -1 | sed "s/^/  after : /"'
