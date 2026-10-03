#!/bin/bash
# k72-wayland-keys.sh - weston took our uinput keyboard (event4 "is tagged by udev
# as: Keyboard") but Super+Print produced no file.  Find the real screenshot
# action name and its default binding so r36-shot.py can press the right keys.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
R() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }

R 'echo "=== weston action / binding names in desktop-shell ==="
   strings -a /usr/lib/aarch64-linux-gnu/weston/desktop-shell.so | grep -iE "screenshot|Screenshooter|print" | sort -u | sed "s/^/  /"
   echo
   echo "=== the [keybindings] keys weston understands ==="
   strings -a /usr/lib/aarch64-linux-gnu/weston/desktop-shell.so /usr/lib/aarch64-linux-gnu/libweston-14.so.0 2>/dev/null |
     grep -xE "(Screenshot|UnlockScreen|Terminate|Debug|SwitchScreenMode|Fullscreen|RotateN|RotateS|Zoom|Transform|TakeScreenshot|Kill|MoveCurrentSurface|ResizeCurrentSurface|Maximize|Minimize|Configure|ShowDebug|CollectDebugger|SwitchToVT[0-9]|AbandonKeys|Capture)" | sort -u | sed "s/^/  /"
   echo
   echo "=== anything that looks like a default binding table (KEY_ names) ==="
   strings -a /usr/lib/aarch64-linux-gnu/weston/desktop-shell.so | grep -E "^KEY_[A-Z0-9]+$" | sort -u | head -20 | sed "s/^/  /"
   echo
   echo "=== capture authorization strings in libweston ==="
   strings -a /usr/lib/aarch64-linux-gnu/libweston-14.so.0 | grep -iE "authoriz|capture|screenshot" | sort -u | head -25 | sed "s/^/  /"
   echo
   echo "=== does the r36-shot keyboard still exist? ==="
   grep -i "r36-shot" /sys/class/input/event4/device/name 2>/dev/null | sed "s/^/  /"
   ls /sys/class/input/ | sed "s/^/  /" | tr "\n" " "; echo
   echo "  weston log around the injection:"
   journalctl -u weston --no-pager | grep -iE "keyboard|libinput|screenshot|capture|unautho" | tail -8 | sed "s/^/    /"'
echo "=== done ==="
