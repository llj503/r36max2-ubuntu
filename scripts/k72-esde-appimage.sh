#!/bin/bash
# k72-esde-appimage.sh - try the ES-DE aarch64 AppImage the user dropped in the repo
# root, without waiting for a source build to finish.
#
# What this proves either way: ES-DE wants desktop GL 3.3+/Vulkan; we measured GL 3.1
# compat and no Vulkan ICD on this board (build/r36-glprobe.sh), so a clean failure
# here is real information, not a fluke.  Extracting first (no FUSE needed) also tells
# us whether the bundled glibc libs can even start against Ubuntu 26.04's libc.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/ES-DE_aarch64.AppImage
[ -f "$SRC" ] || { echo "!! $SRC missing"; exit 1; }

echo "=== push the AppImage (132 MB over wifi) ==="
if ! timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
      'test -f /root/ESDE.AppImage -a "$(stat -c %s /root/ESDE.AppImage)" = "'"$(stat -c %s "$SRC")"'"' ; then
  timeout 600 sshpass -p $PW scp -o ConnectTimeout=25 -q "$SRC" root@$DEV:/root/ESDE.AppImage || { echo "!! scp failed"; exit 1; }
fi
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  'ls -l /root/ESDE.AppImage; sha256sum /root/ESDE.AppImage | cut -c1-16'
echo "  local sha256 head: $(sha256sum "$SRC" | cut -c1-16)"

timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
echo "  host=$(hostname) weston=$(systemctl is-active weston)"
cd /root || exit 1
chmod +x /root/ESDE.AppImage
echo "=== AppImage metadata (no FUSE needed) ==="
./ESDE.AppImage --appimage-version 2>&1 | head -2 | sed 's/^/  /'
timeout 120 ./ESDE.AppImage --appimage-extract 2>&1 | tail -3 | sed 's/^/  /'
echo "  extracted: $(ls /root/squashfs-root 2>/dev/null | tr '\n' ' ')"
echo
echo "=== what does the bundled binary need? ==="
BIN=$(ls /root/squashfs-root/usr/bin/* 2>/dev/null | head -3 | tr '\n' ' ')
echo "  candidates: $BIN"
ls -l /root/squashfs-root/AppRun 2>/dev/null | sed 's/^/  AppRun: /'
echo "  glibc bundled? $(ls /root/squashfs-root/usr/lib/aarch64-linux-gnu/libc.so* 2>/dev/null | head -1 || echo 'no - uses system libc')"
echo
echo "=== try to start it headless-ly: --version, then a 12s window on weston ==="
(timeout 25 /root/squashfs-root/AppRun --version 2>&1 | head -12) | sed 's/^/  /'
echo "  version rc=$?"
(setsid timeout 12 /root/squashfs-root/AppRun --fullscreen >/tmp/esde.log 2>&1 &)
sleep 13
echo "  --- run log (first 25 lines) ---"
head -25 /tmp/esde.log 2>/dev/null | sed 's/^/     /'
echo "  still alive? $(pgrep -c -f 'AppRun|emulationstation-de' 2>/dev/null)"
echo "  stall messages since boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== ES-DE AppImage attempt done ==="
