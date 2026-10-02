#!/bin/bash
# v16 = the real missing piece: the rootfs never had the `udev` package (Ubuntu
# split udev out of systemd), so there was no systemd-udevd, no device units, and
# wpa_supplicant-nl80211@wlan0.service died with "Dependency failed".
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
KVER=6.12.79
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 1. install udev ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
chroot "$R" /usr/bin/env apt-get update -qq >/dev/null 2>&1 || echo "  (apt update had errors)"
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install udev 2>&1 | tail -4
echo "--- what it brought ---"
ls -l "$R/usr/lib/systemd/systemd-udevd" 2>/dev/null || ls -l "$R/lib/systemd/systemd-udevd"
ls "$R/usr/lib/systemd/system/" 2>/dev/null | grep -E 'udev' | tr '\n' ' '; echo
echo "enabled by the postinst: $(ls "$R/etc/systemd/system/sysinit.target.wants/" 2>/dev/null | grep -i udev | tr '\n' ' ')"
echo "sockets: $(ls "$R/etc/systemd/system/sockets.target.wants/" 2>/dev/null | grep -i udev | tr '\n' ' ')"
echo "udev rules now: $(ls "$R/usr/lib/udev/rules.d/" 2>/dev/null | wc -l) files, by-path links will exist"

echo "=== 2. make sure the udev units are on ==="
mkdir -p "$R/etc/systemd/system/sysinit.target.wants" "$R/etc/systemd/system/sockets.target.wants"
for u in systemd-udevd.service systemd-udev-trigger.service; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$R/etc/systemd/system/sysinit.target.wants/$u" && echo "  enabled $u"
done
for u in systemd-udevd-control.socket systemd-udevd-kernel.socket; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$R/etc/systemd/system/sockets.target.wants/$u" && echo "  enabled $u"
done
chroot "$R" /usr/bin/env depmod -a "$KVER"

echo "=== 3. our own wpa unit: no device-unit dependency, polls, retries ==="
cp -f "$SRC/r36-wpa@.service" "$R/etc/systemd/system/r36-wpa@.service"
chmod 644 "$R/etc/systemd/system/r36-wpa@.service"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
rm -f "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service"
rm -f "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
ln -sf /etc/systemd/system/r36-wpa@.service "$R/etc/systemd/system/multi-user.target.wants/r36-wpa@wlan0.service"
echo "  enabled: r36-wpa@wlan0.service; Debian's two wpa templates are off"
ls "$R/etc/wpa_supplicant/" | tr '\n' ' '; echo
grep -q 'wpa_supplicant-wlan0.conf' <<< "x" || true
[ -f "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" ] && echo "  config present, $(stat -c %a "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf") perms"

echo "=== 4. status page back on the console, drop the tty3 experiment ==="
cp -f "$SRC/r36-status-screen" "$R/usr/local/sbin/r36-status-screen"
chmod 755 "$R/usr/local/sbin/r36-status-screen"
sh -n "$R/usr/local/sbin/r36-status-screen" && echo "  parses ok"
rm -f "$R/etc/systemd/system/getty.target.wants/getty@tty3.service"
grep -c 'chvt' "$R/usr/local/sbin/r36-status-screen" || echo "  no chvt left"
cp -f "$SRC/r36-bootlog" "$R/usr/local/sbin/r36-bootlog"
chmod 755 "$R/usr/local/sbin/r36-bootlog"
sh -n "$R/usr/local/sbin/r36-bootlog" && echo "  bootlog parses ok"

echo "=== 5. DNS back to something that exists on the LAN ==="
printf '# static resolver: router + public, does not depend on whatever runs the link\nnameserver 192.168.31.1\nnameserver 223.5.5.5\n' > "$R/etc/resolv.conf"
cat "$R/etc/resolv.conf" | tail -2

echo "=== 6. clean up ==="
umount -f "$R/proc" 2>/dev/null || true
mount | grep "$R" && { echo "!! rootfs still has mounts"; exit 1; }
chroot "$R" /usr/bin/env apt-get clean 2>/dev/null || true
rm -rf "$R"/var/lib/apt/lists/*
du -sk "$R" | awk '{printf "rootfs: %.2f GiB\n", $1/1048576}'
echo "=== apply-v16 done ==="
