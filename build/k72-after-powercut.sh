#!/bin/bash
# k72-after-powercut.sh - the user power-cycled the device while the deploy was
# copying.  Find it again, see what survived, and report what must be re-copied.
set -uo pipefail
PW=ubuntu
LOG=/mnt/e/ubuntu/logs/k72-deploy2.log

echo "=== deploy log (as far as it got) ==="
tail -25 "$LOG" 2>/dev/null || echo "  no log"

echo "=== find the device again ==="
DEV=""
for ip in 192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211 192.168.31.212; do
  if sshpass -p $PW ssh -o ConnectTimeout=4 -o BatchMode=no root@$ip 'echo ok' >/dev/null 2>&1; then
    DEV=$ip; break
  fi
done
if [ -z "$DEV" ]; then
  echo "  known addresses did not answer; sweeping 192.168.31.1-254 (arp + ssh probe)"
  for i in $(seq 1 254); do (ping -c1 -W1 192.168.31.$i >/dev/null 2>&1 &) ; done
  sleep 6
  arp -an 2>/dev/null | grep -oE "192\.168\.31\.[0-9]+" | sort -u > /tmp/lan.txt
  while read -r ip; do
    sshpass -p $PW ssh -o ConnectTimeout=3 root@$ip 'echo ok' >/dev/null 2>&1 && { DEV=$ip; break; }
  done < /tmp/lan.txt
fi
[ -n "$DEV" ] || { echo "  DEVICE NOT REACHABLE - it is probably still booting or on another address"; exit 1; }
echo "  device is at $DEV"

S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }
echo "=== state after the power cut ==="
S 'echo "  kernel  : $(uname -r)"; echo "  uptime  : $(cut -d" " -f1 /proc/uptime)s"; echo "  ip      : $(ip -4 -br addr show wlan0 | awk "{print \$3}")"
   echo "  failed  : $(systemctl --failed --no-legend --plain | wc -l) units"
   B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot
   echo "  --- BOOT partition:"
   ls -l /run/r36-boot | grep -E "Image|\.dtb|\.ini|uInitrd" | sed "s/^/      /"
   echo "  sha256 of what landed:"
   for f in Image Image-7.2.8 rk3326-xifan-r36max2.dtb rk3326-xifan-r36max2-7.2.8.dtb; do
     [ -e /run/r36-boot/$f ] && echo "      $f  $(sha256sum /run/r36-boot/$f | cut -c1-24)..."
   done
   echo "  --- modules:"
   du -sh /lib/modules/* 2>/dev/null | sed "s/^/      /"
   ls /lib/modules/7.2.8/extra/ 2>/dev/null | sed "s/^/      extra: /"
   for k in /lib/modules/7.2.8/extra/*.ko; do [ -e "$k" ] && modinfo -F vermagic "$k" >/dev/null 2>&1 && echo "      $(basename $k) loads-OK" || echo "      $(basename ${k:-none}) BROKEN/absent"; done
   echo "  --- boot-72.ini present? $([ -e /run/r36-boot/boot-72.ini ] && echo yes || echo no)"
   sync; umount /run/r36-boot'
echo "=== check done ==="
