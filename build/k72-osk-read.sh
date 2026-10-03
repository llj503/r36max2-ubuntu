#!/bin/bash
# k72-osk-read.sh - read back what the on-screen keyboard sent vs what the target
# received.  osk.log records each click, /tmp/osk-typed.txt holds the characters
# that actually reached the focused window, so a divergence is visible without
# looking at the panel.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  still running: $(pgrep -a -f 'r36-osk|wofi|foot' | awk '{print $2}' | tr '\n' ' ')"
echo "  --- osk clicks (last 30) ---"
tail -30 /tmp/osk.log 2>/dev/null | sed 's/^/  /'
echo "  --- what the focused window received ---"
od -c /tmp/osk-typed.txt 2>/dev/null | head -12 | sed 's/^/  /'
echo "  bytes: $(wc -c < /tmp/osk-typed.txt 2>/dev/null || echo 0)"
echo "  --- new weston input/flip messages ---"
journalctl -u weston --no-pager -n 6 | sed 's/^/     /'
journalctl -b -k --no-pager 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out' | sed 's/^/  flip errors since boot: /'
EOS
echo "=== read done ==="
