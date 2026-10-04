#!/bin/bash
# k72-stuck-check.sh - the deploy log has not moved in ~35 minutes.  Find out
# whether the copy process is even alive, whether the device has rsync at all,
# and what actually landed.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== is anything still copying on the WSL side? ==="
ps -eo pid,etime,cmd 2>/dev/null | grep -E "rsync|k72-deploy|ssh " | grep -v grep | sed 's/^/  /' || echo "  no rsync/deploy process -> it died or was reaped"

echo "=== does the device have rsync? ==="
S 'command -v rsync || echo "  NO rsync on the device (that is why rsync -a to it fails)"'
echo "=== what landed so far ==="
S 'ls -ld /lib/modules/7.2.8 2>/dev/null; du -sh /lib/modules/7.2.8 2>/dev/null | sed "s/^/  /"; \
   find /lib/modules/7.2.8 -name "*.ko" 2>/dev/null | wc -l | sed "s/^/  .ko count: /"; \
   echo "  BOOT:"; B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot; \
   ls -l /run/r36-boot | grep -E "7.2.8|boot-72" | sed "s/^/    /" || echo "    nothing 7.2.8 on BOOT"; \
   umount /run/r36-boot 2>/dev/null'
echo "=== device health ==="
S 'echo "  $(uname -r) up $(cut -d" " -f1 /proc/uptime)s, failed=$(systemctl --failed --no-legend | wc -l), disk=$(df -h / | awk "NR==2{print \$5}") used"'
