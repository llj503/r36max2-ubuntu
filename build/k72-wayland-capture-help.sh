#!/bin/bash
# k72-wayland-capture-help.sh - weston 14 answered weston-screenshooter with
# "Output capture error: unauthorized".  Find the switch that allows it (and the
# correct [shell] background-type value while we are in the man page).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== weston.ini man page: capture / screenshot / security ==="
zgrep -hiE "^[[:space:]]*(capture|screenshooter|security|allow)[a-z-]*|unauthorized|READ_SCREEN|WRITE_SCREEN" \
  /usr/share/man/man5/weston.ini.5.gz 2>/dev/null | head -20 | sed 's/^/  /'
echo
echo "=== [core] section keys mentioning screen/capture ==="
zcat /usr/share/man/man5/weston.ini.5.gz 2>/dev/null |
  grep -iE "^\s+(capture|screenshooter|shell|security|restrict)" -A3 | head -30 | sed 's/^/  /'
echo
echo "=== background-type values ==="
zcat /usr/share/man/man5/weston.ini.5.gz 2>/dev/null |
  grep -iE "background-type|solid-colour|solid-color|uniform" -A2 | head -20 | sed 's/^/  /'
echo
echo "=== weston strings: capture-related option names ==="
strings /usr/bin/weston /usr/lib/aarch64-linux-gnu/weston/*.so 2>/dev/null |
  grep -iE "capture|screenshooter|unauthorized" | sort -u | head -20 | sed 's/^/  /'
echo
echo "=== does weston advertise a capture interface? (socket check with wayland info) ==="
ls /usr/bin | grep -iE "weston-info|wayland-info" | sed 's/^/  /'
EOS
echo "=== done ==="
