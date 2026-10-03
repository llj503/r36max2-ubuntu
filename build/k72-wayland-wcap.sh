#!/bin/bash
# k72-wayland-wcap.sh - weston answered one of the injected combos with
# "starting recorder for output DSI-1, file capture.wcap".  Find that file, work
# out what a .wcap actually is, and see whether it contains viewable frames.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
R() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }

R 'echo "=== where is it ==="
   find / -xdev -name "*.wcap" -printf "%TY-%Tm-%Td %TH:%TM:%TS %s %p\n" 2>/dev/null | sed "s/^/  /"
   echo "  weston cwd: $(ls -l /proc/$(pgrep -x weston | head -1)/cwd 2>/dev/null | sed "s/.* -> //")"
   echo "  journal lines about the recorder:"
   journalctl -u weston --no-pager | grep -iE "record|wcap|capture" | tail -6 | sed "s/^/    /"'

R 'F=$(find / -xdev -name "*.wcap" -size +0 2>/dev/null | head -1)
   if [ -z "$F" ]; then echo "  no .wcap found"; exit 0; fi
   echo "=== $F ($(stat -c%s $F) bytes) ==="
   echo "  file: $(file -b "$F" 2>/dev/null)"
   echo "  first bytes:"; head -c 64 "$F" | od -An -tx1c | head -6 | sed "s/^/    /"
   echo "  is it a directory/tar?"; ls -la "$F" 2>/dev/null | head -3
   if [ -d "$F" ]; then ls -la "$F" | head -20 | sed "s/^/    /"; fi
   echo "  strings sample:"; strings -a "$F" 2>/dev/null | head -20 | sed "s/^/    /"
   echo "  any PNG inside?"; grep -c -a "PNG" "$F" 2>/dev/null | sed "s/^/    png markers: /"'
echo "=== done ==="
