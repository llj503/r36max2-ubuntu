#!/bin/bash
# k72-wayland-runtest.sh - first real test: can weston take the DSI panel on this
# 7.2.8 kernel, does a GL client render into it, and can we capture what the panel
# shows so the user gets visual proof over SSH instead of "does it look right?".
#
# Everything runs on a spare VT (tty2) with a timeout, so the console on tty1
# comes back by itself; nothing here is persistent.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
T=${T:-40}

timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<EOS
RT=/run/wl-test; DUR=$T
rm -rf \$RT; mkdir -p -m 0700 \$RT
cat > /root/weston-test.ini <<'INI'
[core]
backend=drm-backend.so
gbm-format=xrgb8888
xkb-layout=us

[shell]
locking=false
background-type=uniform-color
background-color=0x102030ff
idle-time=0

[output]
name=DSI-1
mode=1024x768
scale=1

[libinput]
enable_tap=false
INI

export XDG_RUNTIME_DIR=\$RT
echo "=== starting weston (drm backend) for \${DUR}s ==="
# no --tty here: weston 14 dropped that option (it died with "fatal: unhandled
# option"), the VT comes from the session/libseat and root over ssh gets DRM
# master anyway - the first log showed DSI-1 modeset + EGL config succeeding.
(timeout \$DUR weston -B drm -c /root/weston-test.ini -S wl0 > /tmp/weston.log 2>&1 &)
i=0
while [ \$i -lt 15 ]; do
  sleep 1; i=\$((i+1))
  [ -S \$RT/wl0 ] && { echo "  socket up after \${i}s"; break; }
done
echo "  socket: \$(ls -l \$RT 2>/dev/null | tr -s ' ' | tr '\n' ' ')"
echo "  weston running: \$(pgrep -c weston)"
echo "  drm master holder: \$(cat /sys/class/drm/card0/master 2>/dev/null || ls -l /dev/dri/card0 | sed 's/.* //')"
echo "  log so far:"; tail -22 /tmp/weston.log | sed "s/^/    /"
echo
echo "=== a GL client inside it (8s) ==="
(WAYLAND_DISPLAY=wl0 XDG_RUNTIME_DIR=\$RT timeout 8 weston-simple-egl > /tmp/egl.log 2>&1 &)
sleep 4
echo "  egl client log:"; tail -6 /tmp/egl.log | sed "s/^/    /"
echo "  weston log (new lines):"; tail -6 /tmp/weston.log | sed "s/^/    /"
echo
echo "=== screenshot attempts ==="
rm -f /tmp/wl-shot.png /tmp/wl-shot.bmp
(WAYLAND_DISPLAY=wl0 XDG_RUNTIME_DIR=\$RT timeout 8 weston-screenshooter /tmp/wl-shot.png > /tmp/shot.log 2>&1)
echo "  weston-screenshooter rc=\$? :"; tail -4 /tmp/shot.log | sed "s/^/    /"
(WAYLAND_DISPLAY=wl0 XDG_RUNTIME_DIR=\$RT timeout 8 grim /tmp/wl-shot2.png > /tmp/grim.log 2>&1)
echo "  grim rc=\$? :"; tail -3 /tmp/grim.log | sed "s/^/    /"
ls -l /tmp/wl-shot*.png /tmp/wl-shot*.bmp 2>/dev/null | sed "s/^/  /"
echo
echo "=== shutting the test down and restoring the console ==="
pkill -f weston-simple-egl 2>/dev/null
pkill -x weston 2>/dev/null
sleep 2
chvt 1 2>/dev/null
echo "  weston left running: \$(pgrep -c weston)"
echo "  active vt: \$(fgconsole 2>/dev/null)"
echo "  meminfo after weston exited: \$(sed -n 2p /proc/meminfo)"
echo "  final weston log:"; tail -14 /tmp/weston.log | sed "s/^/    /"
EOS
echo "=== runtest done: pull screenshots with k72-wayland-pull.sh ==="
