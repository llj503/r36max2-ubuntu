#!/bin/bash
# k72-osk-test.sh - verify the on-screen keyboard's typing half automatically:
# watch the uinput keyboard through libinput (the same library weston uses) while
# r36-osk types a known string, and check that the right key codes with the right
# shift combinations come out.  No user interaction needed for this part.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/build

echo "=== push r36-osk.py ==="
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'cat > /usr/local/bin/r36-osk' < "$SRC/r36-osk.py"

timeout 180 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
chmod 755 /usr/local/bin/r36-osk
python3 -m py_compile /usr/local/bin/r36-osk && echo "  compiles on the device"
if ! command -v libinput >/dev/null 2>&1; then
  echo "  installing libinput-tools (the debug-events viewer)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q libinput-tools >/dev/null 2>&1
  echo "  libinput: $(command -v libinput || echo still-missing)"
fi

echo "=== [1] dry check: does the mapping produce the expected codes? ==="
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("osk", "/usr/local/bin/r36-osk")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)          # safe: main() only runs under __main__
sent = []
class Fake:
    def hold(self, code, down): sent.append("%s%s" % (m.CODES.get(code, code), "-down" if down else "-up"))
    def tap(self, code): self.hold(code, True); self.hold(code, False)
m.CODES = {v: k for k, v in m.K.items()}
for ch in ["A", "a", "9", "!", " ", "x"]:
    before = len(sent)
    shown = m.send_char(Fake(), ch)
    print("  %-4r -> %-6s %s" % (ch, shown, sent[before:]))
PY

echo
echo "=== [2] live: libinput sees what? ==="
rm -f /tmp/osk-li.log
( timeout 15 libinput debug-events --show-keycodes > /tmp/osk-li.log 2>&1 & )
sleep 3
grep -n "r36 on-screen" /tmp/osk-li.log | head -2 | sed 's/^/  device: /'
/usr/local/bin/r36-osk --type 'Hi 36! x' --verbose
sleep 2
echo "  --- libinput events from the osk keyboard ---"
grep -A200 "r36 on-screen" /tmp/osk-li.log | grep -E "KEY_[A-Z0-9_]+|POINTER" | head -30 | sed 's/^/    /'
echo "  --- counts ---"
echo "    KEY_DOWN lines: $(grep -c 'KEY_DOWN' /tmp/osk-li.log)   KEY_UP lines: $(grep -c 'KEY_UP' /tmp/osk-li.log)"
echo "    SHIFT seen: $(grep -c 'KEY_LEFTSHIFT' /tmp/osk-li.log)   (expect 4: H, !, and their releases)"
pkill -f "libinput debug-events" 2>/dev/null
echo
echo "  weston still healthy: $(systemctl is-active weston)   flip errors: $(journalctl -b -k | grep -cE 'wait_for_vblanks|flip_done timed out')"
EOS
echo "=== osk typing test done ==="
