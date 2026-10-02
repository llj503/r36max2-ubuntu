#!/bin/bash
# v8 prep:
#  (a) install systemd-sysv (provides /sbin/init) + dbus + wireless-regdb + avahi-daemon
#  (b) make sure the simple-audio-card machine driver is enabled (log: "No soundcards found")
#  (c) harden the initramfs: fall back to /lib/systemd/systemd, and never let PID1 exit
#      (an exiting init = panic = watchdog reboot loop, which is what we saw)
set -eu
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
OUT=/root/r36/out
IR=/root/r36/initrd

echo "=== (b) sound machine driver config ==="
cd "$K"
grep -E "SND_SOC_SIMPLE_AUDIO_CARD|SND_SOC_ROCKCHIP=|SND_SOC_RK817=|SND_SOC_ROCKCHIP_I2S" .config || true
if ! grep -q "^CONFIG_SND_SOC_SIMPLE_AUDIO_CARD=y" .config; then
  echo "  -> enabling SND_SOC_SIMPLE_AUDIO_CARD (+ TDM, codec helpers)"
  printf 'CONFIG_SND_SOC_SIMPLE_AUDIO_CARD=y\nCONFIG_SND_SOC_AUDIO_GRAPH_CARD=y\n' >> .config
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
  grep -E "^CONFIG_SND_SOC_SIMPLE_AUDIO_CARD" .config || echo "  !! symbol still off (check Kconfig name)"
  echo "  -> rebuilding Image + dtbs + modules"
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image dtbs modules > /root/r36/b8.log 2>&1 || true
  tail -3 /root/r36/b8.log
  ls -la arch/arm64/boot/Image
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT" modules_install >/dev/null 2>&1
fi

echo "=== (a) rootfs packages ==="
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
cp -f "$ROOT/etc/resolv.conf" /tmp/resolv.runtime 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$ROOT/etc/resolv.conf"
mount -t proc proc "$ROOT/proc" 2>/dev/null || true
mount --rbind /dev "$ROOT/dev" 2>/dev/null || true
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends systemd-sysv dbus wireless-regdb avahi-daemon 2>&1 | tail -5
echo "--- init now present? ---"
ls -la "$ROOT/sbin/init" "$ROOT/usr/sbin/init" 2>&1 | tail -2
chroot "$ROOT" /bin/sh -c 'systemctl enable ssh.service ssh.socket avahi-daemon.service 2>&1 | tail -3' || true
cp -f /tmp/resolv.runtime "$ROOT/etc/resolv.conf" 2>/dev/null || printf 'nameserver 192.168.31.1\nnameserver 223.5.5.5\n' > "$ROOT/etc/resolv.conf"
umount -R "$ROOT/dev" 2>/dev/null || true
umount "$ROOT/proc" 2>/dev/null || true

echo "=== (c) initramfs hardening ==="
cp -f "$K/arch/arm64/boot/Image" "$OUT/boot/Image"
cp -f "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
rm -rf "$IR"; mkdir -p "$IR"/{bin,sbin,dev,proc,sys,newroot,etc}
cp -f /root/r36/bs/busybox "$IR/bin/busybox"
for a in sh mount umount switch_root cat ls grep mkdir sleep dmesg insmod echo test; do
  ln -sf busybox "$IR/bin/$a"
done
cat > "$IR/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin
mount -t devtmpfs devtmpfs /dev  2>/dev/null
mount -t proc      proc      /proc 2>/dev/null
mount -t sysfs     sysfs     /sys  2>/dev/null
echo "== r36max2 initrd: start"
MARKER=etc/r36max2-build-info
FOUND=""
i=0
while [ "$i" -lt 40 ]; do
    for d in /dev/mmcblk*p* /dev/sda*; do
        [ -b "$d" ] || continue
        if mount -t ext4 -o rw "$d" /newroot 2>/dev/null; then
            if [ -f "/newroot/$MARKER" ]; then FOUND="$d"; break; fi
            umount /newroot 2>/dev/null
        fi
    done
    [ -n "$FOUND" ] && break
    sleep 0.5; i=$((i + 1))
done
if [ -z "$FOUND" ]; then
    echo "== r36max2 initrd: rootfs NOT found; devices:"; ls -l /dev/ | grep -E "mmcblk|sd[a-z]"
else
    echo "== r36max2 initrd: rootfs on $FOUND"
    cat "/newroot/$MARKER"
fi
for b in /sys/class/backlight/*; do
    [ -w "$b/brightness" ] || continue
    m=$(cat "$b/max_brightness" 2>/dev/null || echo 255)
    echo "$m" > "$b/brightness" 2>/dev/null && echo "== r36max2 initrd: backlight -> $m"
done
INIT=""
for cand in /sbin/init /lib/systemd/systemd /usr/lib/systemd/systemd; do
    [ -x "/newroot$cand" ] && { INIT="$cand"; break; }
done
echo "== r36max2 initrd: init = ${INIT:-NONE}"
umount /proc 2>/dev/null; umount /sys 2>/dev/null
if [ -n "$INIT" ]; then exec switch_root /newroot "$INIT"; fi
echo "== r36max2 initrd: no init in rootfs, staying alive with a shell =="
sh
while true; do sleep 30; done
EOF
chmod +x "$IR/init"
cd "$IR"
find . | cpio -o -H newc --quiet 2>/dev/null | gzip -9 > /tmp/initrd.cpio.gz
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd-r36max2" -d /tmp/initrd.cpio.gz "$OUT/boot/uInitrd" >/dev/null
ls -la "$OUT/boot"
echo "=== V8 PREP DONE ==="
