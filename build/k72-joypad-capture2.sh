#!/bin/bash
# k72-joypad-capture2.sh - fresh 75-second capture (kills any previous evtest so
# the exclusive grab does not conflict) with a summary of every code seen.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
EV=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

S 'pkill -x evtest 2>/dev/null; pkill -x jstest 2>/dev/null; sleep 1; echo "  previous capture cleared"'
S "rm -f /tmp/ev2.txt; ( timeout 75 evtest --raw $EV > /tmp/ev2.txt 2>&1 & ) ; echo '  capturing 75s - press everything now'"
sleep 78
S 'echo "=== events: $(wc -l < /tmp/ev2.txt) lines ==="
   echo "--- EV_KEY codes seen (button name + number of reports):"
   grep -oE "code [0-9]+ \([A-Z_0-9]+\)" /tmp/ev2.txt | sort | uniq -c | sort -rn | sed "s/^/     /"
   echo "--- EV_ABS axes seen:"
   grep -oE "type 3 \(EV_ABS\), code [0-9]+ \([A-Z_0-9]+\)" /tmp/ev2.txt | sort | uniq -c | sed "s/^/     /"
   echo "--- axis value range per code:"
   awk "/EV_ABS/{code=\$0; getline; print}" /tmp/ev2.txt | grep -oE "\([A-Z_]+\).*value +[-0-9]+" | sed "s/value *//" | sort -u | head -8 | sed "s/^/     /"
   echo "--- min/max per axis:"
   python3 - <<PY
import re
txt=open("/tmp/ev2.txt",errors="replace").read()
vals={}
for m in re.finditer(r"type 3 \(EV_ABS\), code \d+ \(([A-Z_]+)\) +value (-?\d+)", txt):
    vals.setdefault(m.group(1), []).append(int(m.group(2)))
for k,v in sorted(vals.items()):
    print(f"     {k:8s} n={len(v):4d} min={min(v):7d} max={max(v):7d}")
if not vals: print("     (no EV_ABS captured)")
PY
   echo "--- key press/release pairs:"
   python3 - <<PY
import re
txt=open("/tmp/ev2.txt",errors="replace").read()
keys={}
for m in re.finditer(r"type 1 \(EV_KEY\), code \d+ \(([A-Z_0-9]+)\) +value (\d)", txt):
    keys.setdefault(m.group(1), []).append(int(m.group(2)))
for k,v in sorted(keys.items()):
    print(f"     {k:12s} events={len(v):3d} values={sorted(set(v))}")
if not keys: print("     (no EV_KEY captured - were any buttons pressed?)")
PY
   dmesg | tail -4 | sed "s/^/  dmesg: /"'
echo "=== capture2 done ==="
