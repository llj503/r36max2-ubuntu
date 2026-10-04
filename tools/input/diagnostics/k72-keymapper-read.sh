#!/bin/bash
# k72-keymapper-read.sh - what did the bridge actually emit?  Reads the two uinput
# capture files (works while the window is still open), lists every key with
# press/release pairs, pointer movement totals and wheel steps, and says which
# mapped buttons were never exercised so the next round can cover them.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
for f in /tmp/km-kbd.txt /tmp/km-mouse.txt; do
  echo "=== $f: $(wc -l < $f 2>/dev/null || echo missing) lines ==="
done
python3 - <<'PY'
import re
def scan(path):
    try:
        txt = open(path, errors="replace").read()
    except OSError:
        return None
    keys, rel = {}, {}
    for m in re.finditer(r"type (\d+) \((EV_\w+)\), code (\d+) \(([A-Z_0-9]+)\), value (-?\d+)", txt):
        t, name, val = m.group(2), m.group(4), int(m.group(5))
        if t == "EV_KEY":
            keys.setdefault(name, [0, 0])
            keys[name][1 if val else 0] += 1
        elif t == "EV_REL":
            rel.setdefault(name, []).append(val)
    return keys, rel

for label, path in (("keyboard", "/tmp/km-kbd.txt"), ("mouse", "/tmp/km-mouse.txt")):
    got = scan(path)
    if got is None:
        print("--- %s: no capture file (window not opened?)" % label)
        continue
    keys, rel = got
    print("--- %s ---" % label)
    if keys:
        for k, (down, up) in sorted(keys.items()):
            note = ""
            if down and not up:
                note = "   <= pressed, never released (stuck key!)"
            if up and not down:
                note = "   <= released without press"
            print("    %-12s down=%2d up=%2d%s" % (k, down, up, note))
    else:
        print("    (no EV_KEY events)")
    for k, v in sorted(rel.items()):
        print("    %-12s n=%4d min=%6d max=%6d sum=%8d" % (k, len(v), min(v), max(v), sum(v)))
    if not rel:
        print("    (no EV_REL events - the stick was never moved?)")

expected = ["BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE"]
kb_exp = ["KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT", "KEY_ESC", "KEY_ENTER",
          "KEY_SPACE", "KEY_BACKSPACE", "KEY_TAB", "KEY_LEFTCTRL", "KEY_LEFTALT",
          "KEY_LEFTSHIFT", "KEY_LEFTMETA", "KEY_END"]
seen_k = set()
seen_b = set()
for path in ("/tmp/km-kbd.txt", "/tmp/km-mouse.txt"):
    try:
        for m in re.finditer(r"type 1 \(EV_KEY\), code \d+ \(([A-Z_0-9]+)\)", open(path, errors="replace").read()):
            n = m.group(1)
            (seen_b if n.startswith("BTN_") else seen_k).add(n)
    except OSError:
        pass
print("--- coverage ---")
print("    mouse buttons seen : %s" % (", ".join(sorted(seen_b)) or "none"))
print("    keys seen          : %s" % (", ".join(sorted(seen_k)) or "none"))
print("    keys never pressed : %s" % (", ".join(k for k in kb_exp if k not in seen_k) or "all covered"))
PY
echo
echo "  bridge still running: $(systemctl is-active r36-keymapper)  weston: $(systemctl is-active weston)"
echo "  errors in its log:"; journalctl -u r36-keymapper --no-pager -p err -n 6 | sed "s/^/     /"
EOS
echo "=== read done ==="
