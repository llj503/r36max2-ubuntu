#!/bin/bash
# k72-osk-focus-test.sh - who actually has keyboard focus, the grid or foot?
# Inject real key presses through a second uinput keyboard while the grid is on
# screen.  If wofi has focus, DOWN/DOWN/ENTER submits one of its cells: wofi
# exits, r36-osk logs a keystroke, and the chosen character must land in
# /tmp/osk-typed.txt (the foot capture).  If nothing changes, wofi never got
# focus and the "click the grid" design is wrong for this compositor.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
# push the current tool first (never inline this: the outer quoting layer eats $()
# and the last thing you want is testing an old copy while reading a new log)
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /usr/local/bin/r36-osk' \
  < /mnt/e/ubuntu/build/r36-osk.py || { echo "!! upload failed"; exit 1; }
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
python3 -c 'import py_compile; py_compile.compile("/usr/local/bin/r36-osk", doraise=True); print("  r36-osk compiles")'
/usr/local/bin/r36-osk --keys BADKEY 2>&1 | head -2 | sed 's/^/  /'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
grid=$(pgrep -c wofi)
echo "  weston=$(systemctl is-active weston) foot=$(pgrep -c foot) wofi=$grid osk=$(pgrep -c -f 'r36-osk')"
echo "  osk.log lines=$(wc -l < /tmp/osk.log 2>/dev/null)  typed bytes=$(wc -c < /tmp/osk-typed.txt 2>/dev/null)"
if [ "$grid" = 0 ]; then
  echo "  grid not showing right now (it re-opens after the idle timeout) - waiting 35s"
  sleep 35
  echo "  wofi now=$(pgrep -c wofi)"
fi
echo
echo "=== inject DOWN,DOWN,DOWN,ENTER at whatever has focus ==="
/usr/local/bin/r36-osk --keys DOWN,DOWN,DOWN,ENTER -v 2>&1 | sed 's/^/  /'
sleep 3
echo "  osk.log tail:"
tail -6 /tmp/osk.log | sed 's/^/     /'
echo "  typed file now: $(wc -c < /tmp/osk-typed.txt 2>/dev/null) bytes"
od -c /tmp/osk-typed.txt 2>/dev/null | tail -4 | sed 's/^/     /'
echo "  wofi pid changed? $(pgrep wofi | tr '\n' ' ')"
echo
echo "=== if the above did nothing, inject into foot knowingly: type 'Zz9' ==="
/usr/local/bin/r36-osk --type 'Zz9' 2>&1 | sed 's/^/  /'
sleep 2
od -c /tmp/osk-typed.txt 2>/dev/null | tail -4 | sed 's/^/     /'
echo
echo "  weston focus/input tail:"
journalctl -u weston --no-pager -n 8 | sed 's/^/     /'
EOS
echo "=== focus test done ==="
