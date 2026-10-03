#!/bin/bash
# k72-restore-weston.sh - clean up after the wedge probe: the flipprobe that was
# started with weston stopped never printed anything and the ssh session was
# killed, so it may still be sitting in the kernel holding DRM master.
#
# Runs entirely from a FILE on purpose.  Inline `wsl.exe -- bash -c "...heredoc..."`
# mangles nested quotes on this box and some lines silently execute inside WSL
# instead of on the board - that is what produced the bogus "the device rebooted"
# reading (WSL's own /proc/uptime and /proc/cmdline).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  date=$(date '+%F %T')  uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  cmdline=$(cut -c1-90 /proc/cmdline)"
echo
echo "=== leftover flip holders ==="
for p in $(pgrep -f 'r36-flipprobe|weston-simple|weston -B'); do
  echo "  pid=$p comm=$(cat /proc/$p/comm 2>/dev/null) state=$(awk '/^State/{print $2}' /proc/$p/status 2>/dev/null) wchan=$(cat /proc/$p/wchan 2>/dev/null)"
  echo "     cmdline=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"
done
[ -n "$(pgrep -f r36-flipprobe)" ] || echo "  (no flipprobe running)"
echo "  DRM lease/master check: fuser /dev/dri/card0 => $(fuser /dev/dri/card0 2>/dev/null | tr '\n' ' ')"
echo
echo "=== kill the probe, free the card, start weston ==="
pkill -9 -f r36-flipprobe 2>/dev/null; sleep 2
systemctl reset-failed weston 2>/dev/null
systemctl start weston
sleep 6
echo "  weston=$(systemctl is-active weston) pid=$(pgrep -x weston | tr '\n' ' ')  fgvt=$(fgconsole 2>/dev/null)"
journalctl -u weston --no-pager -n 8 | sed 's/^/     /'
systemctl start r36-keymapper 2>/dev/null
sleep 2
echo "  keymapper=$(systemctl is-active r36-keymapper)"
echo
echo "=== does a fresh commit complete?  count stalls in the last 90s window ==="
a=$(journalctl -b --no-pager -k --since '-90 seconds' 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')
echo "  stall messages in the last 90s: $a"
echo "  total since boot: $(journalctl -b --no-pager -k 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "  (if the panel shows the blue desktop now, the pipeline recovered on its own;"
echo "   if it is still an old frozen frame while weston says active, only a reboot clears it)"
EOS
echo "=== restore attempt finished ==="
