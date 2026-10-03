#!/bin/bash
# k72-wedge-probe.sh - is the display pipeline actually dead right now, or is the
# stale frame only weston's problem?  Stop the compositor so DRM master is free,
# then flip dumb buffers underneath everything and time the completion events.
#   healthy  => restarting weston brings the panel back, no reboot needed
#   stalled  => the VOP/vblank path is wedged; only a reboot clears it (ask first)
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
before=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|commit wait timed out')
echo "  stall messages since boot (before): $before"
echo "  stopping keymapper + weston to release DRM master..."
systemctl stop r36-keymapper 2>/dev/null
systemctl stop weston 2>/dev/null
sleep 4
echo "  weston=$(systemctl is-active weston)  fgvt=$(fgconsole 2>/dev/null)"
if [ ! -x /usr/local/bin/r36-flipprobe ]; then
  echo "  !! probe missing on the card"; exit 5
fi
echo "  --- flipping 12 buffers with no compositor in the way ---"
timeout 90 /usr/local/bin/r36-flipprobe 12 16 2>&1 | tail -8 | sed 's/^/  /'
rc=$?
echo "  probe rc=$rc"
after=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|commit wait timed out')
echo "  stall messages since boot (after): $after   (delta $((after-before)))"
echo "  restarting weston..."
systemctl start weston
sleep 5
echo "  weston=$(systemctl is-active weston) pid=$(pgrep -c -x weston)"
systemctl start r36-keymapper 2>/dev/null
sleep 2
echo "  keymapper=$(systemctl is-active r36-keymapper)"
journalctl -u weston --no-pager -n 6 | sed 's/^/     /'
EOS
echo "=== if the probe said 'NO COMPLETION EVENT' the panel needs a reboot; ask the user first ==="
