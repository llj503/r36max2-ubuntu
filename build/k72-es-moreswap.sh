#!/bin/bash
# k72-es-moreswap.sh - the final step of the ES build is a link over a few hundred C++
# objects, and this board had 47 MB of available RAM while doing it. A killed ld means
# "build stopped with no binary" and 10 more minutes of guessing, so add a second swap
# file up front. Everything here is reversible: swapoff + rm.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  progress=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)"
grep MemAvailable /proc/meminfo | sed 's/^/  before: /'
swapon --show=FILE,SIZE --noheadings 2>/dev/null | sed 's/^/  swap: /'
if [ ! -f /swap.es2.img ]; then
  fallocate -l 1G /swap.es2.img && chmod 600 /swap.es2.img && mkswap /swap.es2.img >/dev/null && swapon /swap.es2.img
  echo "  added /swap.es2.img (1G, not in fstab)"
else
  echo "  /swap.es2.img already there"
fi
swapon --show=FILE,SIZE --noheadings 2>/dev/null | sed 's/^/  now: /'
free -m | awk '/Mem|Swap/{print "  " $0}'
echo "  (undo with: swapoff /swap.es.img /swap.es2.img; rm -f /swap.es*.img)"
EOS
echo "=== swap headroom ready ==="
