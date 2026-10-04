#!/bin/bash
# k72-verify-72.sh - wait for the device to come back on 7.2.8 and check whether
# the ported AIC driver now really talks to the firmware (chip_id + h_u02
# uploads + association), plus a quick health sweep.
set -uo pipefail
PW=ubuntu
DEV=""
for i in $(seq 1 30); do
  for ip in 192.168.31.209 192.168.31.210; do
    if sshpass -p $PW ssh -o ConnectTimeout=4 root@$ip 'echo ok' >/dev/null 2>&1; then DEV=$ip; break; fi
  done
  [ -n "$DEV" ] && break
  sleep 5
done
if [ -z "$DEV" ]; then
  echo "still unreachable after 150s - it is either booting slowly, on another IP, or 7.2.8 did not come up"
  exit 1
fi
echo "device: $DEV (after $((i*5))s of waiting)"
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== identity ==="
S 'echo "  kernel : $(uname -r)"; echo "  uptime : $(cut -d" " -f1 /proc/uptime)s"; echo "  ip     : $(ip -4 -br addr show wlan0 | awk "{print \$3}")"'

echo "=== did the RIGHT driver load? (chip id + h_u02 uploads) ==="
S 'dmesg | grep -aiE "chip_id|chip_sub_id|Upload|calib|dpd|RELEASE DATE|New interface|rwnx_start|firmware path" | head -20 | sed "s/^/  /"'

echo "=== association ==="
S 'iw dev wlan0 link 2>/dev/null | head -4 | sed "s/^/  /"; echo "  wpa: $(systemctl is-active r36-wpa@wlan0.service)"; echo "  ping: $(ping -c2 -W2 223.5.5.5 >/dev/null 2>&1 && echo OK || echo FAIL)"'

echo "=== crashes or errors from the wifi stack ==="
S 'dmesg | grep -aiE "cmd queue|timed-out|alignment exception|Internal error|BUG:|Oops|aic8800_fdrv: probe" | head -10 | sed "s/^/  /" || true'
S 'echo "  loaded: $(lsmod | awk "/aic/{print \$1\"=\"\$3\" refs\"}" | tr "\n" " ")"'

echo "=== everything else still healthy ==="
S 'echo "  failed units: $(systemctl --failed --no-legend | wc -l)"
   echo "  drm: $(ls /dev/dri | tr "\n" " ")"
   echo "  gpu freq: $(cat /sys/class/devfreq/ff400000.gpu/cur_freq 2>/dev/null) Hz"
   echo "  sound: $(ls /dev/snd 2>/dev/null | tr "\n" " ")"
   echo "  input: $(ls /dev/input/by-path 2>/dev/null | wc -l) by-path devices"
   echo "  back: $(cat /sys/class/backlight/*/brightness 2>/dev/null)/$(cat /sys/class/backlight/*/max_brightness 2>/dev/null)"'
