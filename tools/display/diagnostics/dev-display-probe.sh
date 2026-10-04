#!/bin/bash
# dev-display-probe.sh - what display stack is actually on this box? (X11?
# Wayland? neither?) Read-only.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== display servers installed? ==="
S 'for b in Xorg X Wayland weston sway Weston Xwayland cage kwin_gles mutter; do
     p=$(command -v $b 2>/dev/null); [ -n "$p" ] && echo "  $b -> $p"; done
   echo "  (nothing listed = none installed)"
   dpkg -l 2>/dev/null | grep -iE "xserver-xorg|weston|sway|libwayland|wayland-|x11-" | head -8'

echo "=== running processes / sessions ==="
S 'ps -eo comm= | sort -u | tr "\n" " "; echo
   echo "  login control:"; loginctl list-sessions --no-legend 2>&1 | head -3
   echo "  active VT: $(ls /sys/class/vtconsole/ 2>/dev/null | head -0; fgrep -m1 . /sys/class/vtconsole/vtcon1/name 2>/dev/null)"
   systemctl get-default'

echo "=== what is actually driving the panel ==="
S 'ls -l /dev/dri/; echo "  fb: $(ls /dev/fb* 2>/dev/null | tr "\n" " ")"
   echo "  driver: $(cat /sys/class/drm/card0/device/uevent 2>/dev/null | awk -F= "/DRIVER/{print \$2}")"
   echo "  gl: $(eglinfo -p gbm 2>/dev/null | grep -m1 "GL renderer")"
   echo "  env of a login shell: DISPLAY=[$DISPLAY] WAYLAND_DISPLAY=[$(env | grep -c WAYLAND)]"'

echo "=== graphics-ish packages we do have ==="
S 'dpkg -l | awk "/^ii/{print \$2}" | grep -iE "mesa|libdrm|gbm|egl|gles|glmark|panfrost|xkb" | head -15'
