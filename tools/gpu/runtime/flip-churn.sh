#!/bin/bash
# flip-churn.sh - reproduce the weston/VOP flip stall on demand instead of
# waiting 23 minutes for a client's timeout to tear its surfaces down, then see
# whether [core] pageflip-timeout=500 stops it from wedging the CRTC.
#
# What we know: the WARN storm started exactly when clients exited.  So churn =
# start a client, kill it hard, repeat, and sample the kernel counters after each
# cycle.  The loop stops the moment a new flip/vblank complaint appears, so the
# worst case is one stall we detected rather than one we discovered an hour later.
#
#   CYCLES=8 CLIENT_SECS=12 bash flip-churn.sh
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
CYCLES=${CYCLES:-8}
CLIENT_SECS=${CLIENT_SECS:-12}
GAP=${GAP:-4}

echo "=== push the weston.ini with pageflip-timeout ==="
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "cat > /etc/xdg/weston/weston.ini" \
  < /mnt/e/ubuntu/packages/r36-wayland/weston.ini

timeout 900 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'CY='"$CYCLES"' CS='"$CLIENT_SECS"' GAP='"$GAP"' sh -s' <<'EOS'
CY=${CY:-8}; CS=${CS:-12}; GAP=${GAP:-4}     # the first run of this script looped
count_err() { journalctl -b --no-pager -k 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out'; }
count_warn() { journalctl -b --no-pager -k 2>/dev/null | grep -c 'WARNING: drivers/gpu/drm'; }
alive() { pgrep -c -x weston; }

echo "  parameters: cycles=$CY client=${CS}s gap=${GAP}s"
echo "  pageflip-timeout in effect: $(grep -E '^pageflip-timeout' /etc/xdg/weston/weston.ini)"
echo "  pre-flight: weston=$(systemctl is-active weston) errors=$(count_err) warns=$(count_warn) vt=$(fgconsole 2>/dev/null)"

systemctl stop r36-km-test 2>/dev/null
systemctl start weston
i=0
while [ $i -lt 20 ]; do
  sleep 1; i=$((i+1))
  [ -S /run/wayland/wayland-0 ] && break
done
echo "  weston pid(s)=$(alive) after ${i}s, socket=$(ls /run/wayland 2>/dev/null | tr '\n' ' ')"
[ -S /run/wayland/wayland-0 ] || { echo "!! no wayland socket - clients would not attach and the test would prove nothing"; journalctl -u weston --no-pager -n 12; systemctl stop weston; exit 1; }

# belt and braces: nothing keeps the compositor alive past this
( sleep $((CY * (CS + GAP) + 180)); systemctl stop weston ) >/dev/null 2>&1 &
WATCHDOG=$!

base_err=$(count_err); base_warn=$(count_warn)
for c in $(seq 1 "$CY"); do
  export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
  ( timeout "$CS" weston-simple-egl >/tmp/egl-$c.log 2>&1 ) &
  cpid=$!
  sleep "$CS"
  kill -9 "$cpid" 2>/dev/null          # hard teardown: this is the suspected trigger
  wait "$cpid" 2>/dev/null
  sleep "$GAP"
  e=$(count_err); w=$(count_warn); a=$(alive)
  echo "  cycle $c: weston=$a procs, kernel errors $((e-base_err)), drm WARNs $((w-base_warn)), client log: $(head -c 60 /tmp/egl-$c.log 2>/dev/null | tr '\n' ' ')"
  if [ "$e" != "$base_err" ] || [ "$w" != "$base_warn" ]; then
    echo "  !! stall reproduced in cycle $c - stopping the experiment"
    journalctl -b --no-pager -k | grep -E 'rockchip-drm|WARNING: drivers/gpu/drm' | tail -6 | sed 's/^/     /'
    break
  fi
  if [ "$a" = 0 ]; then
    echo "  !! weston exited on its own in cycle $c"
    journalctl -u weston --no-pager -n 15 | sed 's/^/     /'
    break
  fi
done

echo
echo "=== after the churn ==="
echo "  errors now: $(count_err)  WARNs now: $(count_warn)  weston procs: $(alive)"
echo "  vt: $(fgconsole 2>/dev/null)  fb0 blank: $(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
echo "  last weston lines:"
journalctl -u weston --no-pager -n 8 | sed 's/^/    /'
echo "  flip-related kernel tail:"
journalctl -b --no-pager -k | grep -E 'rockchip-drm|drm_atomic_helper' | tail -5 | sed 's/^/    /'

echo
echo "=== tear down and hand the console back ==="
kill "$WATCHDOG" 2>/dev/null
systemctl stop weston
sleep 2
chvt 1 2>/dev/null
systemctl restart getty@tty1 2>/dev/null
echo "  weston: $(systemctl is-active weston)  getty: $(systemctl is-active getty@tty1)  vt: $(fgconsole 2>/dev/null)  fb0 blank: $(cat /sys/class/graphics/fb0/blank)"
if [ "$(count_err)" != "$base_err" ]; then
  echo "  RESULT: stall STILL happens with pageflip-timeout (needs a reboot if the panel is frozen)"
else
  echo "  RESULT: no flip/vblank complaints through $CY churn cycles with pageflip-timeout"
fi
EOS
echo "=== churn test finished - ask the user what the panel shows ==="
