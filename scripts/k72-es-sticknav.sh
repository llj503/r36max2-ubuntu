#!/bin/bash
# k72-es-sticknav.sh - bind the LEFT STICK to menu navigation in EmulationStation WITHOUT
# taking the dpad away, then restart ES through the launcher.
#
# Why this is possible (read from the fork's own source, not guessed):
#   es-core/src/InputConfig.cpp:229-238
#       isMappedLike("left")  -> isMappedTo("left")  || isMappedTo("joystick1left")
#       isMappedLike("right") -> isMappedTo("right") || isMappedTo("joystick1left", true)
#       isMappedLike("up")    -> isMappedTo("up")    || isMappedTo("joystick1up")
#       isMappedLike("down")  -> isMappedTo("down")  || isMappedTo("joystick1up", true)
#   so navigation accepts EITHER name and the reversed variant is derived from one stored
#   binding.  Only the names "joystick1left"/"joystick1up"/"joystick2left"/"joystick2up"
#   are consumed - the "leftanalogup" style entries our generated config carried from
#   Batocera's template are written by the wizard but read by nobody (grep: 0 files).
#
# Polarity, from isMappedTo (InputConfig.cpp:203-221): for TYPE_AXIS it compares the
# stored value with the live one (comp.value == input.value), and the reversed lookup
# multiplies the STORED value by -1.  Therefore the entry must store the NEGATIVE
# direction: value=-1 makes "left"/"up" fire on -1 and "right"/"down" fire on +1.
# Store +1 instead and left/right swap silently - which is why FLIP exists below.
#
#   bash scripts/k72-es-sticknav.sh verify
#   bash scripts/k72-es-sticknav.sh add
#   bash scripts/k72-es-sticknav.sh flip      # invert the two axes if the directions came out reversed
#   bash scripts/k72-es-sticknav.sh undo      # back to the previous file
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
GUID=${GUID:-19009b4d4b4800000111000000010000}
AX_L=${AX_L:-0}          # left stick X  (ABS_X)
AX_U=${AX_U:-1}          # left stick Y  (ABS_Y)
cmd=${1:-verify}

timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "GUID=$GUID AX_L=$AX_L AX_U=$AX_U cmd=$cmd sh -s" <<'EOS'
F=/root/.emulationstation/es_input.cfg
[ -f "$F" ] || { echo "  !! $F missing"; exit 1; }
echo "  host=$(hostname)  es procs=$(pgrep -c -f /root/es/emulationstation 2>/dev/null || echo 0)"

if [ "$(pgrep -c -f /root/es/emulationstation 2>/dev/null || echo 0)" != 0 ] && [ "$cmd" != verify ]; then
  echo "  ES is running - it rewrites es_input.cfg when it exits, so stopping it first"
  pkill -f /root/es/emulationstation; sleep 2
fi

python3 - "$F" "$GUID" "$cmd" "$AX_L" "$AX_U" <<'PY'
import os, sys, xml.etree.ElementTree as ET
from xml.dom import minidom

path, guid, cmd, ax_l, ax_u = sys.argv[1:6]
ax_l, ax_u = int(ax_l), int(ax_u)
tree = ET.parse(path)
root = tree.getroot()
dev = next((d for d in root if d.get("deviceGUID") == guid), None)
if dev is None:
    print("  !! no inputConfig with deviceGUID=%s in %s" % (guid, path))
    print("     devices present: %s" % ", ".join(str(d.get("deviceGUID")) for d in root))
    sys.exit(1)

def show(tag):
    print("  --- %s ---" % tag)
    for e in dev:
        if e.get("name") in ("up", "down", "left", "right", "joystick1up", "joystick1left"):
            print("      %-14s type=%-6s value=%-3s id=%s" % (
                e.get("name"), e.get("type"), e.get("value"), e.get("id")))

def find(name):
    return next((e for e in dev if e.get("name") == name), None)

if cmd == "undo":
    b = path + ".pre-sticknav"
    if not os.path.exists(b):
        print("  !! %s missing, nothing to restore" % b); sys.exit(1)
    os.replace(b, path)
    print("  restored %s from the backup" % path)
    show("after undo")
    sys.exit(0)

if cmd == "flip":
    changed = []
    for name in ("joystick1left", "joystick1up"):
        e = find(name)
        if e is None:
            print("  !! %s not bound yet - run: add" % name); continue
        v = int(e.get("value")); e.set("value", str(-v)); changed.append("%s %+d -> %+d" % (name, v, -v))
    print("  flipped: " + ", ".join(changed))
elif cmd == "add":
    if not os.path.exists(path + ".pre-sticknav"):
        import shutil; shutil.copy2(path, path + ".pre-sticknav")
        print("  backup: %s.pre-sticknav" % path)
    for name, axis in (("joystick1left", ax_l), ("joystick1up", ax_u)):
        e = find(name)
        if e is None:
            e = ET.SubElement(dev, "input")
            e.set("name", name)
            print("  added %s" % name)
        else:
            print("  %s already present, updating it" % name)
        e.set("type", "axis")
        e.set("value", "-1")          # store the NEGATIVE direction, see header
        e.set("id", str(axis))
    print("  dpad entries untouched: up/down/left/right still bound to buttons")
else:
    print("  verify only")
show("bindings now in %s" % path)

if cmd in ("add", "flip"):
    ET.register_namespace("", "")
    xml = ET.tostring(root, encoding="unicode")
    open(path, "w").write('<?xml version="1.0" encoding="UTF-8"?>\n' + xml + "\n")
    print("  wrote %s (%d bytes, %d device blocks)" % (path, os.path.getsize(path), len(list(ET.parse(path).getroot()))))
PY

echo "=== resulting file parses as ES expects? ==="
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse("/root/.emulationstation/es_input.cfg").getroot()
print("  root=%s children=%d" % (r.tag, len(list(r))))
PY
if [ "$cmd" = add ] || [ "$cmd" = flip ] || [ "$cmd" = undo ]; then
  echo "=== restarting ES through the launcher (it also keeps the joypad bridge off) ==="
  /usr/local/bin/r36-es --stop >/dev/null 2>&1
  /usr/local/bin/r36-es run 2>&1 | sed 's/^/  /'
fi
EOS
