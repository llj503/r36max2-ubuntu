#!/bin/bash
# k72-ttyrun-log.sh - the ttyrun test's ssh session died mid-way, so read the state
# it left behind: the log the transient unit writes, whether weston came back, and
# whether the display pipeline stalled again while we were poking at the console.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) date=$(date +%T) uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper) vt=$(fgconsole 2>/dev/null)"
echo "  probe binary mtime: $(date -r /usr/local/bin/r36-sdlprobe +%H:%M:%S 2>/dev/null)"
echo "  leftover units: $(systemctl list-units --all --no-legend 'ttyprobe*' 2>/dev/null | head -3 | tr '\n' ' ')"
echo "  failed units: $(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l)"
echo "  --- /tmp/ttyrun.log ---"
cat /tmp/ttyrun.log 2>/dev/null | sed 's/^/    /' || echo "    (missing)"
echo "  --- journal of the transient unit(s) ---"
journalctl --no-pager -u ttyprobe.service -n 25 2>/dev/null | sed 's/^/    /'
journalctl --no-pager --since "-12 min" 2>/dev/null | grep -iE "ttyprobe|systemd-run|sdlprobe" | tail -10 | sed 's/^/    /'
echo "  stall messages in the last 12 min: $(journalctl -b -k --no-pager --since '-12 min' 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== log read done ==="
