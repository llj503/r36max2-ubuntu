#!/bin/bash
# dev-disk-usage.sh - how big is the running rootfs and the staging rootfs, and
# does the 2 GiB image partition still have room for the dev packages?
set -uo pipefail
DEV=${DEV:-192.168.31.209}
echo "=== device (v17 + everything installed live) ==="
sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV \
  'df -h /; echo; du -sh /usr /var /etc /root /home 2>/dev/null; echo; dpkg -l | wc -l; echo "--- biggest dirs under /usr:"; du -sh /usr/* 2>/dev/null | sort -h | tail -6' </dev/null 2>/dev/null
echo
echo "=== staging rootfs in WSL (what pack copies) ==="
if [ -d /root/r36/rootfs ]; then
  du -sh /root/r36/rootfs 2>/dev/null
  du -sh /root/r36/rootfs/usr /root/r36/rootfs/var /root/r36/rootfs/lib 2>/dev/null | sort -h | tail -5
  df -h /root/r36 | tail -1
else
  echo "  /root/r36/rootfs missing"
fi
echo
echo "=== image partition budget ==="
grep -nE 'size=4194304|start=262144|mkfs.ext4' /mnt/e/ubuntu/scripts/pack-v10.sh | head -6
