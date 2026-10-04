#!/bin/bash
# k72-install-modules.sh - device is up on 6.12 with working WiFi. Install the
# freshly ported 7.2.8 AIC modules, verify with depmod/modprobe -n, then flip
# the FAT boot files so the next boot is 7.2.8, and reboot.
set -uo pipefail
PW=ubuntu
DEV=""
for ip in 192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211 192.168.31.212; do
  sshpass -p $PW ssh -o ConnectTimeout=5 root@$ip 'echo ok' >/dev/null 2>&1 && { DEV=$ip; break; }
done
[ -n "$DEV" ] || { echo "device not reachable"; exit 1; }
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }
echo "device: $DEV"
S 'echo "  kernel $(uname -r), up $(cut -d" " -f1 /proc/uptime)s, ip $(ip -4 -br addr show wlan0 | awk "{print \$3}")"'

echo "=== [1] install the ported modules (replacing the wrong-tree ones) ==="
S 'ls -l /lib/modules/7.2.8/extra/ | sed "s/^/  before: /"'
S 'cp -f /run/r36-boot/k72mods/aic8800_fdrv.ko /run/r36-boot/k72mods/aic_load_fw.ko /lib/modules/7.2.8/extra/ 2>/dev/null || echo "  (FAT not mounted, will copy from windows side)"'
sshpass -p $PW scp -q /root/r36/k72aic/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko \
  /root/r36/k72aic/drivers/aic8800/aic_load_fw/aic_load_fw.ko \
  "root@$DEV:/lib/modules/7.2.8/extra/" 2>/dev/null
S 'depmod -a 7.2.8
   ls -l /lib/modules/7.2.8/extra/ | sed "s/^/  after:  /"
   echo "  vermagic: $(modinfo -S 7.2.8 -F vermagic aic8800_fdrv 2>/dev/null)"
   echo "  firmware deps: $(modinfo -S 7.2.8 -F firmware aic8800_fdrv 2>/dev/null | tr "\n" " ")"
   modprobe -n -S 7.2.8 aic8800_fdrv && echo "  modprobe -n: resolves"
   echo "  deps: $(modprobe -S 7.2.8 --show-depends aic8800_fdrv 2>/dev/null | tr "\n" " ")"'

echo "=== [2] keep a copy of the current (broken) modules for comparison ==="
S 'mkdir -p /root/k72-backup && ls /root/k72-backup | wc -l | sed "s/^/  backup dir entries: /"'

echo "=== [3] flip the boot files on the FAT partition ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot
   mountpoint -q /run/r36-boot || mount "$B" /run/r36-boot
   cd /run/r36-boot
   [ -f boot-612.ini ] || cp boot.ini boot-612.ini
   cp boot-72.ini boot.ini
   sync
   echo "  now boot.ini loads:"; grep -E "^load|^booti" boot.ini | sed "s/^/      /"
   ls -l boot*.ini | sed "s/^/      /"
   umount /run/r36-boot 2>/dev/null || true'

echo "=== [4] reboot into 7.2.8 ==="
S 'echo "  rebooting in 3s"; (sleep 3; reboot) >/dev/null 2>&1 &'
echo "  reboot issued - device will be back in ~60s on kernel 7.2.8"
