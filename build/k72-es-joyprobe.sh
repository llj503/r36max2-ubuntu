#!/bin/bash
# k72-es-joyprobe.sh - pre-seed EmulationStation's joystick config instead of relying
# on its first-boot wizard (which needs a readable panel, and screenshots are blocked
# by weston's capture authority).
#
# 1. ask SDL on the board for each joystick's name + GUID (that is exactly the key ES
#    uses), 2. look it up in Batocera's 324-device controllers/es_input.cfg database,
# 3. write whatever matches into build/es-input-matched.cfg so it can be installed to
#    ~/.emulationstation/es_input.cfg before the first ES run.
# If the name matches but the GUID differs (GUIDs depend on the driver's id fields),
# the script says so and emits their block with the GUID rewritten - that is the
# documented, safe adaptation rather than guessing button numbers by hand.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WIN=/mnt/e/ubuntu/build
BAT_URL=https://raw.githubusercontent.com/batocera-linux/batocera.linux/master/package/batocera/emulationstation/batocera-emulationstation/controllers/es_input.cfg

# --- the database, kept next to the repo (WSL /tmp evaporates when the VM is recycled)
mkdir -p "$WIN/vendor"
DB=$WIN/vendor/batocera-controllers-es_input.cfg
[ -s "$DB" ] || timeout 120 curl -sSL "$BAT_URL" -o "$DB"
echo "  Batocera controller db: $(wc -l < "$DB" 2>/dev/null) lines, $(grep -c '<inputConfig' "$DB") devices"

# --- probe on the board
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'mkdir -p /usr/local/src; cat > /usr/local/src/r36-sdljoy.c' \
  < "$WIN/r36-sdljoy.c" || { echo "!! push failed"; exit 1; }
rm -f /tmp/joy.txt
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' > /tmp/joy.txt <<'EOS'
echo "  host=$(hostname)"
rm -f /usr/local/bin/r36-sdljoy
cc -O2 -Wall -o /usr/local/bin/r36-sdljoy /usr/local/src/r36-sdljoy.c $(sdl2-config --cflags --libs) 2>&1 | head -8
[ -x /usr/local/bin/r36-sdljoy ] || { echo "  !! probe did not build"; exit 1; }
# r36-keymapper grabs the event nodes; js0 is a different interface so this is safe,
# but say who is holding what so a confusing result is not misread
echo "  keymapper=$(systemctl is-active r36-keymapper) js0=$(ls /dev/input/js0 2>/dev/null) grabbed: $(grep -l . /sys/class/input/event*/device/../grab 2>/dev/null | head -2 | tr '\n' ' ')"
/usr/local/bin/r36-sdljoy
EOS
sed 's/^/  /' /tmp/joy.txt | head -40

echo
echo "=== cross-reference against the Batocera database ==="
: > "$WIN/es-input-matched.cfg"
python3 - "$DB" /tmp/joy.txt "$WIN/es-input-matched.cfg" <<'PY'
import re, sys
db_path, joy_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
db = open(db_path, errors="replace").read()
joy = open(joy_path, errors="replace").read()

devices = re.findall(r'<inputConfig\b[^>]*>.*?</inputConfig>', db, re.S)
by_guid, by_name = {}, {}
for d in devices:
    g = re.search(r'deviceGUID="([0-9a-fA-F]+)"', d)
    n = re.search(r'deviceName="([^"]*)"', d)
    if g: by_guid.setdefault(g.group(1).lower(), []).append(d)
    if n: by_name.setdefault(n.group(1), []).append(d)

found = []
# the probe prints one block per device: "  [0] guid=...", "      name=..."
blocks = re.split(r"\n  \[\d+\]", joy)
for b in blocks:
    g = re.search(r"guid=([0-9a-f]{32})", b)
    n = re.search(r"name=(.+)", b)
    if g:
        found.append((n.group(1).strip() if n else "(unnamed)", g.group(1)))
print("  board reports %d joystick(s)" % len(found))
written = 0
for name, guid in found:
    name = name.strip()
    if guid in by_guid:
        block = by_guid[guid][0]
        print("  %s / %s -> EXACT match in Batocera db" % (name, guid))
    elif name in by_name:
        block = by_name[name][0]
        old = re.search(r'deviceGUID="([0-9a-fA-F]+)"', block).group(1)
        block = block.replace('deviceGUID="%s"' % old, 'deviceGUID="%s"' % guid)
        print("  %s / %s -> name matches, GUID differs (db had %s) -> GUID rewritten" % (name, guid, old))
    else:
        print("  %s / %s -> NOT in the database; ES will have to ask a human to map it" % (name, guid))
        continue
    with open(out_path, "a") as fh:
        fh.write(block.strip() + "\n")
    written += 1
print("  wrote %d device block(s) to %s" % (written, out_path))
if written:
    with open(out_path) as fh:
        txt = fh.read()
    keys = sorted(set(re.findall(r'<input name="([a-z_]+)"', txt)))
    print("  ES action names covered: %s" % " ".join(keys))
PY
