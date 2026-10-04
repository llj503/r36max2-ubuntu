#!/bin/bash
# k72-km-check.sh - is the bridge actually running and did uinput create the two
# devices?  (k72-km-rec.sh checks a fraction of a second after systemd-run, which
# is too early to see the nodes.)
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
echo "  unit: $(systemctl is-active r36-km-test)"
journalctl -u r36-km-test --no-pager -n 12 | sed 's/^/    /'
echo "  nodes by name:"
for d in /sys/class/input/event*; do
  n=$(cat $d/device/name 2>/dev/null)
  echo "    $(basename $d) = $n"
done
echo "  evtest procs: $(pgrep -c evtest)  files: $(ls -l /tmp/km-*.txt 2>/dev/null | awk '{print $5, $9}' | tr '\n' '|')"
echo "  grab holder on the joypad: $(grep -l . /proc/*/fdinfo/* 2>/dev/null | head -0; for p in $(pgrep -f r36-keymapper); do echo -n "    keymapper pid $p alive"; done)"
EOS
echo "=== check done ==="
