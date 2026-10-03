#!/bin/bash
# k72-joypad-parse.sh - re-parse the captured evtest log with the correct format.
# evtest --raw prints:  Event: time 1696..., type 1 (EV_KEY), code 304 (BTN_SOUTH), value 1
# (the earlier regex missed the comma before "value", so it found nothing).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
F=${1:-/tmp/ev2.txt}
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "cat $F" </dev/null 2>/dev/null > /tmp/evlocal.txt
wc -l /tmp/evlocal.txt | sed 's/^/lines: /'
python3 - <<'PY'
import re, collections
txt = open("/tmp/evlocal.txt", errors="replace").read()
keys = collections.OrderedDict()
absv = {}
for m in re.finditer(r"type 1 \(EV_KEY\), code (\d+) \((\S+?)\),? +value (-?\d+)", txt):
    keys.setdefault(m.group(2), []).append(int(m.group(3)))
for m in re.finditer(r"type 3 \(EV_ABS\), code (\d+) \((\S+?)\),? +value (-?\d+)", txt):
    absv.setdefault(m.group(2), []).append(int(m.group(3)))
print("=== EV_KEY (button) ===")
if not keys:
    print("   none captured")
for k, v in keys.items():
    print(f"   {k:14s} events={len(v):3d}  press={v.count(1)} release={v.count(0)} repeat={v.count(2)}")
print("=== EV_ABS (axes / analog buttons) ===")
if not absv:
    print("   none captured")
for k, v in sorted(absv.items()):
    print(f"   {k:8s} n={len(v):5d}  min={min(v):7d}  max={max(v):7d}  idle~{v[0]}")
print("=== other event types ===")
for m in collections.Counter(re.findall(r"type \d+ \(([A-Z_]+)\)", txt)).items():
    print(f"   {m[0]:16s} {m[1]}")
PY
