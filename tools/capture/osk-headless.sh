#!/bin/bash
# k72-osk-headless.sh - verify r36-osk end to end WITHOUT a usable panel.
#
# The screen is currently wedged, so instead of asking anyone to click: replace
# wofi with a stub that replays a fixed sequence of "clicks", let r36-osk drive
# its uinput keyboard for real, and capture the raw EV_KEY stream from the event
# node (r36-evsnap).  That proves the grid->entry mapping, the Shift latch, the
# page switch and the action keys, which is everything except eyeballs.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
B=/mnt/e/ubuntu/build

timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > /usr/local/bin/r36-osk" < "$B/r36-osk.py" || { echo "!! push r36-osk failed"; exit 1; }
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > /usr/local/bin/r36-evsnap" < "$B/r36-evsnap.py" || { echo "!! push r36-evsnap failed"; exit 1; }

timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
chmod 755 /usr/local/bin/r36-osk /usr/local/bin/r36-evsnap
python3 -c 'import py_compile; py_compile.compile("/usr/local/bin/r36-osk", doraise=True); py_compile.compile("/usr/local/bin/r36-evsnap", doraise=True)' && echo "  syntax ok"

rm -rf /tmp/oskstub /tmp/evsnap.seq /tmp/osk-headless.log
mkdir -p /tmp/oskstub
# the "clicks", in wofi label form (what the grid actually prints on stdout)
cat > /tmp/oskstub/sequence <<'SEQ'
h
i
SHFT
a
RET
#!?
@
SPC
DEL<
X
SEQ
cat > /tmp/oskstub/wofi <<'STUB'
#!/bin/sh
# stub wofi: sleep first (so the capture can attach), then print the next label
n=$(cat /tmp/oskstub/count 2>/dev/null || echo 0)
if [ "$n" = 0 ]; then sleep 2.5; else sleep 1.0; fi
echo $((n+1)) > /tmp/oskstub/count
sed -n "$((n+1))p" /tmp/oskstub/sequence
STUB
chmod 755 /tmp/oskstub/wofi

echo "=== run r36-osk against the stub (weston irrelevant: uinput only) ==="
(setsid env PATH=/tmp/oskstub:$PATH /usr/local/bin/r36-osk --settle 0.05 --pick-timeout 120 >/tmp/osk-headless.log 2>&1 &)
/usr/local/bin/r36-evsnap "r36 on-screen keyboard" 18 /tmp/evsnap.seq
echo "  osk log:"
tail -16 /tmp/osk-headless.log | sed 's/^/     /'

echo "=== compare with the expected key stream ==="
cat > /tmp/osk-check.py <<'PY'
import importlib.machinery
import importlib.util
import sys
# the installed tool has no .py suffix, so spec_from_file_location() would return
# None - load it explicitly as a source file
loader = importlib.machinery.SourceFileLoader("osk", "/usr/local/bin/r36-osk")
spec = importlib.util.spec_from_loader("osk", loader)
osk = importlib.util.module_from_spec(spec)
loader.exec_module(osk)

# Expected presses, by key NAME (never by number: KEY_1=2, KEY_2=3 ... is exactly
# the sort of off-by-one that fakes a failure).  h i [SHFT latch] a RET [#!? page]
# @ SPC DEL< X
want_names = ["h", "i", "SHIFT", "a", "ENTER", "SHIFT", "2", "SPACE", "BACKSPACE"]
want = [osk.K[n] for n in want_names]
raw = open("/tmp/evsnap.seq").read().split()
got, downs, ups = [], {}, {}
for item in raw:
    code, value = item.split(",")
    code, value = int(code), int(value)
    if value == 1:
        got.append(code)
        downs[code] = downs.get(code, 0) + 1
    elif value == 0:
        ups[code] = ups.get(code, 0) + 1
names = {v: k for k, v in osk.K.items()}
show = lambda seq: " ".join("%s(%d)" % (names.get(c, "?%d" % c), c) for c in seq)
print("  presses captured : %s" % show(got))
print("  presses expected : %s" % show(want))
ok = got == want
print("  order/contents   : %s" % ("MATCH" if ok else "DIFFERENT"))
# a key with more presses than releases is really stuck; extra releases are
# harmless (evdev can report the initial "all keys up" state to a new reader)
stuck = [c for c in downs if downs[c] > ups.get(c, 0)]
print("  unbalanced down/up (stuck keys): %s" % (stuck if stuck else "none"))
shift_ok = downs.get(42, 0) == 2 and ups.get(42, 0) >= 2
print("  SHIFT pressed twice and always released (latch + symbol): %s" % ("yes" if shift_ok else "NO"))
print("=== headless osk check: %s ===" % ("PASS" if ok and not stuck and shift_ok else "FAIL"))
sys.exit(0 if (ok and not stuck and shift_ok) else 1)
PY
python3 /tmp/osk-check.py
rc=$?
pkill -f "r36-osk" 2>/dev/null
rm -rf /tmp/oskstub /tmp/osk-check.py
echo "  uinput node now: $(grep -l 'r36 on-screen keyboard' /sys/class/input/*/device/name 2>/dev/null | tr '\n' ' ')(empty = device destroyed with the process, good)"
exit $rc
EOS
echo "=== headless verification rc=$? ==="
