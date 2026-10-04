#!/bin/bash
# k72-es-verify-buttons.sh - check the pre-seeded ES mapping's button numbers against
# what this board really exposes, without asking anyone to press a key.
#
# The js interface numbers buttons as the rank of each BTN_* code in ascending order,
# so the truth comes from the evdev capability bitmap - read on the device by
# r36-capdump.py (its sysfs alternative is the 64-bit-words trap that once produced a
# bogus "15 mismatches" report here).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WIN=/mnt/e/ubuntu/build

timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /usr/local/bin/r36-capdump' < "$WIN/r36-capdump.py" || exit 1
rm -f /tmp/cap.txt
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  'chmod 755 /usr/local/bin/r36-capdump; python3 /usr/local/bin/r36-capdump $(grep -l retrogame /sys/class/input/*/device/name | head -1 | sed "s|/sys/class/input/|/dev/input/|; s|/device/name||")' \
  > /tmp/cap.txt 2>/tmp/cap.err
if [ ! -s /tmp/cap.txt ]; then echo "  !! capdump produced nothing:"; cat /tmp/cap.err | sed 's/^/     /'; exit 1; fi
sed 's/^/  /' /tmp/cap.txt

python3 - <<'PY'
import re

want = {"up": "BTN_DPAD_UP", "down": "BTN_DPAD_DOWN", "left": "BTN_DPAD_LEFT",
        "right": "BTN_DPAD_RIGHT", "a": "BTN_SOUTH", "b": "BTN_EAST",
        "x": "BTN_WEST", "y": "BTN_NORTH", "start": "BTN_START",
        "select": "BTN_SELECT", "hotkey": "BTN_MODE", "l2": "BTN_TL2",
        "r2": "BTN_TR2", "l3": "BTN_THUMBL", "r3": "BTN_THUMBR",
        "pageup": "BTN_TL", "pagedown": "BTN_TR"}

cap = open("/tmp/cap.txt", errors="replace").read()
derived = {name: int(idx) for idx, _, name in re.findall(r"^BUTTON (\d+) (0x[0-9a-f]+) (\S+)", cap, re.M)}
axes = re.findall(r"^AXIS (\d+) (0x[0-9a-f]+) (\S+)", cap, re.M)
print("\n  board-derived js indices: %s" % " ".join("%s=%d" % kv for kv in sorted(derived.items())))
print("  axes: %s" % " ".join("%s=%s" % (n, i) for i, _, n in axes))

try:
    cfg = open("/mnt/e/ubuntu/packages/r36-emulationstation/es-input-matched.cfg", errors="replace").read()
except OSError:
    print("  !! no es-input-matched.cfg yet (run k72-es-joyprobe.sh)")
    raise SystemExit(1)

bad = []
for action, btn in want.items():
    m = re.search(r'<input name="%s"[^>]*type="button" id="(-?\d+)"' % action, cfg)
    if not m:
        continue
    theirs = int(m.group(1))
    ours = derived.get(btn)
    tag = "ok" if ours == theirs else "MISMATCH"
    if ours != theirs:
        bad.append((action, theirs, ours))
    print("  %-9s Batocera id=%-3s our board=%-4s %s" % (action, theirs, ours, tag))

# axes: Batocera's entry assumes which axis index is which stick
for action, ab in [("leftanalogleft", "ABS_X"), ("leftanalogright", "ABS_X"),
                   ("leftanalogup", "ABS_Y"), ("leftanalogdown", "ABS_Y"),
                   ("rightanalogleft", "ABS_RX"), ("rightanalogup", "ABS_RY")]:
    m = re.search(r'<input name="%s"[^>]*type="axis" id="(-?\d+)"' % action, cfg)
    if not m:
        continue
    ours = next((int(i) for i, _, n in axes if n == ab), None)
    tag = "ok" if ours == int(m.group(1)) else "MISMATCH"
    if tag == "MISMATCH":
        bad.append((action, int(m.group(1)), ours))
    print("  %-16s Batocera id=%-3s our board=%-4s %s" % (action, m.group(1), ours, tag))

print("=== %s ===" % ("pre-seeded config is correct for this board" if not bad
                      else "FIX NEEDED: %s" % bad))
PY
