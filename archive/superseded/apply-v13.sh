#!/bin/bash
# v13 = the real AICSemi bundle driver (radxa-pkg/aic8800, RELEASE_DATE 2026_0123)
# which handles chip_sub_id == 2 (our chip) including the h_u02 calib table,
# plus the cleanups the boot log asked for.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
W=/root/r36/aic8800-radxa/src/USB/driver_fw
KVER=6.12.79
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 1. the new modules ==="
modinfo -F vermagic "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko"
modinfo -F vermagic "$W/drivers/aic8800/aic_load_fw/aic_load_fw.ko"
strings -a "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" | grep -E '^fmacfw_(patch|calib).*h_u02' | sort
strings -a "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" | grep -E 'RELEASE_DATE|2026_' | head -3
cp -f "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" "$R/usr/lib/modules/$KVER/extra/"
cp -f "$W/drivers/aic8800/aic_load_fw/aic_load_fw.ko"   "$R/usr/lib/modules/$KVER/extra/"

echo "=== 2. firmware: make sure every name the driver asks for is on the card ==="
for f in $(strings -a "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" | grep -E '^(fmacfw|lmacfw|aic_)[a-z0-9_]*\.(bin|txt)$' | sort -u); do
  if [ -f "$R/lib/firmware/aic8800DC/$f" ]; then
    echo "  ok      $f"
  elif [ -f "$W/fw/aic8800DC/$f" ]; then
    cp -f "$W/fw/aic8800DC/$f" "$R/lib/firmware/aic8800DC/"; echo "  +added  $f (from the bundle)"
  else
    echo "  MISSING $f (not on the card, not in the bundle)"
  fi
done

echo "=== 3. packages the log said were missing ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
chroot "$R" /usr/bin/env apt-get update -qq >/dev/null 2>&1 || echo "  (apt update failed - continuing)"
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install rfkill wireless-regdb nss-mdns 2>&1 | tail -3
echo "  rfkill      : $(ls "$R/usr/sbin/rfkill" 2>/dev/null || echo absent)"
echo "  regulatory  : $(ls -la "$R/usr/lib/firmware/regulatory.db" 2>/dev/null | awk '{print $5" bytes"}' || echo MISSING)"
echo "  nss-mdns    : $(grep '^hosts' "$R/etc/nsswitch.conf")"

echo "=== 4. depmod, then unmount proc ==="
chroot "$R" /usr/bin/env depmod -a "$KVER"
chroot "$R" /bin/sh -c "modinfo -F vermagic /usr/lib/modules/$KVER/extra/aic8800_fdrv.ko"
umount -f "$R/proc" 2>/dev/null || true
mount | grep "$R" && { echo "!! rootfs still has mounts"; exit 1; }

echo "=== 5. wpa_supplicant drop-in that does not need the rfkill binary ==="
cat > "$R/etc/systemd/system/wpa_supplicant-nl80211@.service.d/r36.conf" <<'EOF'
[Unit]
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
RuntimeDirectory=wpa_supplicant
RuntimeDirectoryMode=0750
Group=netdev
ExecStartPre=/bin/sh -c 'for d in /sys/class/rfkill/rfkill*; do [ -e "$d/state" ] && echo 1 > "$d/state"; done; exit 0'
Restart=always
RestartSec=5
EOF

echo "=== 6. refreshed status reporter + unit permissions ==="
cp -f "$SRC/r36-bootlog" "$R/usr/local/sbin/r36-bootlog"
chmod 755 "$R/usr/local/sbin/r36-bootlog"
for u in r36-bootlog.service r36-bootlog.timer r36-resize-root.service r36-usb-gadget.service; do
  [ -f "$SRC/$u" ] && cp -f "$SRC/$u" "$R/etc/systemd/system/$u"
  [ -f "$R/etc/systemd/system/$u" ] && chmod 644 "$R/etc/systemd/system/$u"
done
sh -n "$R/usr/local/sbin/r36-bootlog" && echo "  bootlog parses ok"
ls -l "$R/etc/systemd/system/"r36-* | awk '{print "  "$1, $NF}'
grep -n 'os-release\|PRETTY' "$R/usr/local/sbin/r36-bootlog" | head -3

echo "=== 7. clean caches ==="
chroot "$R" /usr/bin/env apt-get clean 2>/dev/null || true
rm -rf "$R"/var/lib/apt/lists/*
du -sk "$R" | awk '{printf "rootfs: %.2f GiB\n", $1/1048576}'
echo "=== apply-v13 done ==="
