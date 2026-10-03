#!/bin/bash
# k72-ttyrun.sh - answer "can SDL open a window on this box?" in the only
# environment that matters: a transient systemd service that owns /dev/tty1 as its
# controlling terminal.  From ssh that is impossible (SDL's kmsdrm backend needs a
# VT to switch to graphics mode), which is why an earlier run reported "kmsdrm not
# available" even with weston stopped.
#
# It also refuses to trust a stale binary: the probe is deleted before it is
# rebuilt, because `[ -x file ]` only proves *something* is there - the last run
# silently re-executed an old probe and its output looked like a new result.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'mkdir -p /usr/local/src; cat > /usr/local/src/r36-sdlprobe.c' \
  < /mnt/e/ubuntu/build/r36-sdlprobe.c || { echo "!! push failed"; exit 1; }
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  weston=$(systemctl is-active weston)"
rm -f /usr/local/bin/r36-sdlprobe
cc -O2 -Wall -o /usr/local/bin/r36-sdlprobe /usr/local/src/r36-sdlprobe.c \
   $(sdl2-config --cflags) $(pkg-config --cflags libdrm) \
   $(sdl2-config --libs) -ldrm 2>&1 | head -20
if [ ! -x /usr/local/bin/r36-sdlprobe ]; then echo "  !! build failed (see above) - stopping"; exit 1; fi
echo "  rebuilt probe: $(ls -l /usr/local/bin/r36-sdlprobe | awk '{print $5}') bytes, mtime $(date -r /usr/local/bin/r36-sdlprobe +%H:%M:%S)"

run_on_tty() {   # run_on_tty <label> <driver> [extra env]
  label=$1; drv=$2; env3=$3
  echo
  echo "=== $label : SDL_VIDEODRIVER=$drv on the real VT ==="
  /usr/bin/rm -f /tmp/ttyrun.log
  timeout 90 systemd-run --unit=ttyprobe --wait --collect --no-ask-password \
    -p Type=oneshot -p TTYPath=/dev/tty1 -p StandardInput=tty \
    -p TTYVTDisallocate=no -p WorkingDirectory=/root \
    -p Environment=HOME=/root -p Environment=XDG_VTNR=1 -p Environment=SDL_AUDIODRIVER=alsa \
    -p Environment="WAYLAND_DISPLAY=wayland-0" -p Environment="XDG_RUNTIME_DIR=/run/wayland" \
    -p TimeoutStartSec=60 \
    /bin/sh -c "SDL_VIDEODRIVER=$drv $env3 /usr/local/bin/r36-sdlprobe $drv > /tmp/ttyrun.log 2>&1; echo rc=\$? >> /tmp/ttyrun.log" >/dev/null 2>&1
  echo "  systemd-run rc=$?"
  sed 's/^/    /' /tmp/ttyrun.log 2>/dev/null || echo "    (no log produced)"
}

echo
echo "=== 1) weston UP -> wayland, from a service that owns the console ==="
run_on_tty wayland-test wayland

echo
echo "=== 2) stop weston, then kmsdrm on the bare console ==="
systemctl stop weston 2>/dev/null
i=0; while [ $i -lt 30 ] && pgrep -x weston >/dev/null; do sleep 3; i=$((i+1)); done
echo "  weston=$(systemctl is-active weston) procs=$(pgrep -cx weston) vt=$(fgconsole 2>/dev/null)"
run_on_tty kmsdrm-test kmsdrm

echo
echo "=== 3) give the panel back to weston ==="
systemctl start weston; sleep 4
echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper)"
echo "  stall messages since boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== ttyrun finished ==="
