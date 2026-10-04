#!/bin/bash
# k72-osk-read.sh - read back what r36-osk sent vs what the target window actually
# received, and diff them.  The OSK logs every pick, the foot capture lands in a
# file, so a divergence (focus lost, Shift stuck, a key dropped) is visible from
# SSH without anyone looking at the panel.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
echo "  running: $(ps -o comm= -C foot,wofi 2>/dev/null | tr '\n' ' ') osk=$(pgrep -c -f r36-osk)"
echo "  --- osk log ---"
tail -40 /tmp/osk.log 2>/dev/null | sed 's/^/     /'
cat > /tmp/osk-diff.py <<'PY'
import re
import sys

# what a terminal should echo back for each thing r36-osk says it sent
TERM = {"SPC": " ", "RET": "\n", "TAB": "\t", "DEL<": "\x7f", ">DEL": "\x08",
        "ESC": "\x1b"}
log = open("/tmp/osk.log", errors="replace").read()
picks = re.findall(r"^\s*\[\s*\d+\] (\S+)", log, re.M)
caps = {m.group(1): m.group(2) for m in re.finditer(r"^\s*(shift|caps) (on|off)", log, re.M)}
got = open("/tmp/osk-typed.txt", "rb").read().decode("utf-8", "replace")

exp, caps_on = [], caps.get("caps") == "on"
for p in picks:
    if p in TERM:
        exp.append(TERM[p])
    elif len(p) == 1:
        ch = p.upper() if (caps_on or caps.get("shift") == "on") else p
        exp.append(ch)
        if p.isalpha() and p.isupper():
            pass
    else:
        exp.append("<?%s>" % p)                      # page switch / modifier key
expected = "".join(exp)
print("  picks reported by r36-osk : %s" % picks)
print("  expected in the terminal  : %r" % expected)
print("  actually received         : %r" % got)
if expected == got:
    print("  => MATCH: every pick landed in the focused window, in order")
    rc = 0
else:
    i = 0
    while i < min(len(expected), len(got)) and expected[i] == got[i]:
        i += 1
    print("  => DIFFERS at offset %d: expected %r got %r" % (
        i, expected[i:i + 6], got[i:i + 6]))
    print("     (missing/late chars usually mean focus went to the wrong window;")
    print("      wrong case means the SHFT/CAPS latch state is not what the prompt said)")
    rc = 1
print("  bytes: typed=%d expected=%d" % (len(got), len(expected)))
sys.exit(rc)
PY
echo "  --- compare ---"
python3 /tmp/osk-diff.py 2>&1 | sed 's/^/     /'
echo "  rc=$?"
echo "  stall messages since boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== read done ==="
