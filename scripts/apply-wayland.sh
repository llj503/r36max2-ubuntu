#!/bin/bash
# apply-wayland.sh - fold the Wayland + joypad-input work into a staging rootfs,
# so a reflash reproduces what the running card has.  Same five files the live
# deploy pushed, plus the apt set, installed into $R (chroot, no systemd running).
#
#   R=/root/r36/rootfs bash scripts/apply-wayland.sh
#
# Kept separate from apply-v19.sh because the graphical stack is opt-in: weston
# and the keymapper are installed but NOT enabled, since weston on 7.2.8 can stall
# the VOP (see documentation/PER_DEVICE_DOCUMENTATION/r36max2/WAYLAND.md) and a card that boots straight into a
# frozen panel is a card nobody can debug without a serial cable they do not have.
set -euo pipefail
R=${R:-/root/r36/rootfs}
SRC=/mnt/e/ubuntu/build
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== rootfs: $R ($(du -sh "$R" 2>/dev/null | cut -f1)) ==="
[ -d "$R" ] || { echo "!! no staging rootfs at $R"; exit 1; }

echo "=== [1] packages (weston, pointer/keyboard helpers, kbd for chvt) ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 755 "$R/usr/sbin/policy-rc.d"
# one unknown package name makes apt install NOTHING and still exit 0, so filter
# the list through apt-cache first (learned the hard way: no weston-examples here)
PKGS="weston wayland-protocols libwayland-dev libwayland-bin grim wf-recorder foot wofi kbd cmake pkg-config"
HAVE=""
for p in $PKGS; do
  c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  case "$c" in ""|none) echo "  skip (not in this release): $p";; *) HAVE="$HAVE $p";; esac
done
chroot "$R" apt-get update -qq >/dev/null 2>&1 || echo "  (apt update noisy)"
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -q install $HAVE 2>&1 | tail -3
echo "  installed: $HAVE"

echo "=== [2] files ==="
mkdir -p "$R/etc/xdg/weston" "$R/usr/local/bin"
cp -f "$SRC/weston.ini"            "$R/etc/xdg/weston/weston.ini"
cp -f "$SRC/weston.service"        "$R/etc/systemd/system/weston.service"
cp -f "$SRC/r36-keymapper.service" "$R/etc/systemd/system/r36-keymapper.service"
cp -f "$SRC/r36-keymapper.py"      "$R/usr/local/bin/r36-keymapper.py"
cp -f "$SRC/r36-wayland"           "$R/usr/local/bin/r36-wayland"
cp -f "$SRC/r36-shot.py"           "$R/usr/local/bin/r36-shot.py"
cp -f "$SRC/r36-shot2.py"          "$R/usr/local/bin/r36-shot2.py"
cp -f "$SRC/r36-osk.py"            "$R/usr/local/bin/r36-osk"
cp -f "$SRC/r36-evsnap.py"         "$R/usr/local/bin/r36-evsnap"
cp -f "$SRC/zz-r36-wayland.sh"     "$R/etc/profile.d/zz-r36-wayland.sh"
chmod 644 "$R/etc/xdg/weston/weston.ini" "$R/etc/systemd/system/weston.service" \
          "$R/etc/systemd/system/r36-keymapper.service" "$R/etc/profile.d/zz-r36-wayland.sh"
chmod 755 "$R/usr/local/bin/r36-keymapper.py" "$R/usr/local/bin/r36-wayland" \
          "$R/usr/local/bin/r36-shot.py" "$R/usr/local/bin/r36-shot2.py" \
          "$R/usr/local/bin/r36-osk" "$R/usr/local/bin/r36-evsnap"
python3 -m py_compile "$R/usr/local/bin/r36-keymapper.py" && echo "  keymapper compiles"
python3 -m py_compile "$R/usr/local/bin/r36-osk" && echo "  osk compiles"

echo "=== [3] opt-in, not enabled ==="
for u in weston r36-keymapper; do
  rm -f "$R/etc/systemd/system/multi-user.target.wants/$u.service" \
        "$R/etc/systemd/system/weston.service.wants/$u.service" 2>/dev/null || true
done
echo "  start manually:  r36-wayland start    (weston pulls the keymapper in)"
echo "  bridge alone  :  systemd-run --unit=r36-km-test /usr/bin/python3 /usr/local/bin/r36-keymapper.py -v"
echo "  type with no keyboard:  r36-osk        (uinput keyboard driven by wofi's grid)"

echo "=== [4] the two things that must not regress ==="
grep -q 'locking=false' "$R/etc/xdg/weston/weston.ini" || { echo "!! locking is on: a locked panel cannot be unlocked without a keyboard"; exit 1; }
grep -q 'ExecStopPost=.*chvt 1' "$R/etc/systemd/system/weston.service" || { echo "!! weston.service lost its console restore"; exit 1; }
# the on-screen keyboard is the only way to type here, and its front-end is wofi:
# no wofi in the package list means r36-osk ships a keyboard with no keys to click
case " $PKGS " in *" wofi "*) : ;; *) echo "!! wofi dropped from PKGS - r36-osk has no grid"; exit 1;; esac
[ -x "$R/usr/local/bin/r36-osk" ] || { echo "!! r36-osk not staged"; exit 1; }
chroot "$R" /usr/local/bin/r36-osk --list >/dev/null 2>&1 \
  && echo "  r36-osk --list works in the chroot (pages: $(chroot "$R" /usr/local/bin/r36-osk --list | grep -c columns))" \
  || { echo "!! r36-osk --list failed in the chroot"; exit 1; }
command -v chroot >/dev/null
[ -e "$R/usr/bin/chvt" ] || echo "  !! kbd missing: weston.service's chvt restore will fail silently again"
echo "  weston backends present: $(ls "$R"/usr/lib/*/libweston-*/ 2>/dev/null | grep -c backend)"
rm -f "$R/usr/sbin/policy-rc.d"
umount -f "$R/proc" 2>/dev/null || true
echo "=== apply-wayland done ==="
