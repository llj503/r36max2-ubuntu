#!/bin/bash
# v11 = v10 + a keyboard-free diagnostic channel and the WiFi ordering fix.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 0. apt needs its lists again (we cleaned them for v10) ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
chroot "$R" /usr/bin/env apt-get update -qq 2>&1 | tail -2
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install usbutils 2>&1 | tail -2

echo "=== 1. WiFi: use the unit that WAITS for wlan0, and keep retrying ==="
echo "  old unit started at multi-user.target whether or not the AIC driver had"
echo "  created wlan0 yet -> wpa_supplicant exited and nothing retried it"
cp -f "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" \
      "$R/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf"
chmod 600 "$R/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf"
rm -f "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
ln -sf /usr/lib/systemd/system/wpa_supplicant-nl80211@.service \
       "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service"
mkdir -p "$R/etc/systemd/system/wpa_supplicant-nl80211@.service.d"
cat > "$R/etc/systemd/system/wpa_supplicant-nl80211@.service.d/r36.conf" <<'EOF'
[Unit]
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
# the supplicant needs /run/wpa_supplicant and must not stay dead
RuntimeDirectory=wpa_supplicant
RuntimeDirectoryMode=0750
Group=netdev
ExecStartPre=/usr/sbin/rfkill unblock wlan
Restart=always
RestartSec=5
EOF

echo "=== 2. DNS: v10 shipped WSL's nameserver as a static file ==="
cat > "$R/etc/resolv.conf" <<'EOF'
# static: router + public resolver, independent of whatever manages the link
nameserver 192.168.31.1
nameserver 223.5.5.5
EOF
grep -c nameserver "$R/etc/resolv.conf"
chroot "$R" /bin/sh -c 'grep -E "DNS|Domains" /etc/systemd/network/*.network'

echo "=== 3. the keyboard-free channel: status report onto the FAT partition ==="
cp -f "$SRC/r36-bootlog"          "$R/usr/local/sbin/r36-bootlog"
cp -f "$SRC/r36-usb-gadget"       "$R/usr/local/sbin/r36-usb-gadget"
chmod 755 "$R/usr/local/sbin/r36-bootlog" "$R/usr/local/sbin/r36-usb-gadget"
cp -f "$SRC/r36-bootlog.service"  "$R/etc/systemd/system/"
cp -f "$SRC/r36-bootlog.timer"    "$R/etc/systemd/system/"
cp -f "$SRC/r36-usb-gadget.service" "$R/etc/systemd/system/"
mkdir -p "$R/etc/systemd/system/timers.target.wants"
ln -sf /etc/systemd/system/r36-bootlog.timer "$R/etc/systemd/system/timers.target.wants/r36-bootlog.timer"
ln -sf /etc/systemd/system/r36-bootlog.service "$R/etc/systemd/system/multi-user.target.wants/r36-bootlog.service"
# the gadget is NOT enabled: the AIC WiFi may sit on the same dwc2 controller,
# so switching it to peripheral mode could kill WiFi. Start it by hand if needed.
echo "  enabled: r36-bootlog.timer (+service).  r36-usb-gadget: installed, not enabled"
sh -n "$R/usr/local/sbin/r36-bootlog" && sh -n "$R/usr/local/sbin/r36-usb-gadget" && echo "  scripts parse ok"

echo "=== 4. trim the boot-time noise for a 1 GB device ==="
for u in apport.service landscape-client.service ua-reboot-cmds.service ubuntu-advantage.service unattended-upgrades.service snapd.service snapd.socket; do
  rm -f "$R/etc/systemd/system/multi-user.target.wants/$u" "$R/etc/systemd/system/sockets.target.wants/$u" 2>/dev/null || true
done
chroot "$R" /bin/sh -c 'ls /etc/systemd/system/multi-user.target.wants/'

echo "=== 5. clean caches again ==="
umount -f "$R/proc" 2>/dev/null || true
mount | grep "$R" && { echo "!! still has mounts"; exit 1; }
chroot "$R" /usr/bin/env apt-get clean
rm -rf "$R"/var/lib/apt/lists/*
du -sk "$R" | awk '{printf "rootfs: %.2f GiB\n", $1/1048576}'
echo "=== apply-v11 done; now run: V=v11 bash pack-v10.sh ==="
