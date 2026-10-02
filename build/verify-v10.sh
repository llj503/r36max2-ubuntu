#!/bin/bash
# Verify the v10 image offline, then dry-run the root-partition expansion on a
# copy that has been grown to 4 GiB (simulates flashing onto a bigger card).
set -eu
IMG=/root/r36/out/r36max2-ubuntu-v10.img
B=/tmp/v10dry.bin

echo "=== 1. partition table + blob offsets ==="
sfdisk -d "$IMG"
for pair in "64:idbloader" "16384:uboot" "24576:trust"; do
  s=${pair%%:*}; n=${pair##*:}
  sig=$(dd if="$IMG" bs=512 skip="$s" count=8 2>/dev/null | strings -a | grep -m1 -E 'RIFF:|LOADER|BL31|TROM|trust|U-Boot' || true)
  echo "  sector $s ($n): magic='${sig:-none}'"
done

echo "=== 2. boot partition contents ==="
losetup -P -f "$IMG"; L=$(losetup -j "$IMG" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && break; sleep 0.3; done
mkdir -p /mnt/v10boot /mnt/v10root
mount -o ro "${L}p1" /mnt/v10boot
ls -la /mnt/v10boot /mnt/v10boot/extlinux
echo "--- boot.ini ---"; cat /mnt/v10boot/boot.ini
echo "--- uInitrd header ---"; head -c 8 /mnt/v10boot/uInitrd | od -An -tx1
echo "--- Image header (magic at 0x3c..0x40) ---"; dd if=/mnt/v10boot/Image bs=1 skip=60 count=4 2>/dev/null | od -An -c

echo "=== 3. rootfs contents (no secrets printed) ==="
mount -o ro "${L}p2" /mnt/v10root
cat /mnt/v10root/etc/r36max2-build-info
echo "  init      : $(readlink /mnt/v10root/sbin/init)"
echo "  systemd   : $(ls -la /mnt/v10root/lib/systemd/systemd | awk '{print $5}') bytes"
echo "  sfdisk    : $(ls /mnt/v10root/usr/sbin/sfdisk)"
echo "  helpers   : $(ls /mnt/v10root/usr/local/sbin/ | tr '\n' ' ')"
echo "  unit link : $(ls /mnt/v10root/etc/systemd/system/multi-user.target.wants/ | tr '\n' ' ')"
echo "  extra ko  : $(ls /mnt/v10root/usr/lib/modules/6.12.79/extra/ | tr '\n' ' ')"
echo "  modules.dep: $(ls -la /mnt/v10root/usr/lib/modules/6.12.79/modules.dep | awk '{print $5}') bytes"
echo "  wpa conf  : $(test -f /mnt/v10root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf && echo present) perm=$(stat -c %a /mnt/v10root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf 2>/dev/null)"
echo "  ssid line : $(grep -c '^network=' /mnt/v10root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf 2>/dev/null) network block(s)"
echo "  ssh host keys: $(ls /mnt/v10root/etc/ssh/ | grep -c hostkey)"
echo "  firmware  : $(ls /mnt/v10root/lib/firmware/ 2>/dev/null | grep -ci aic) aic entries"
umount /mnt/v10root; umount /mnt/v10boot; losetup -d "$L"

echo "=== 4. expansion dry run on a 4 GiB copy ==="
rm -f "$B"; cp --sparse=always "$IMG" "$B"; truncate -s 4G "$B"
losetup -P -f "$B"; D=$(losetup -j "$B" | cut -d: -f1); DD=${D#/dev/}
for _ in $(seq 1 40); do [ -b "${D}p2" ] && break; sleep 0.3; done
echo "  sim card: $D size=$(cat /sys/block/$DD/size) sectors, root ${D}p2 size=$(cat /sys/block/${DD}p2/size)"
mkdir -p /mnt/v10root
mount "${D}p2" /mnt/v10root
cp /mnt/v10root/usr/local/sbin/r36-expand-root /tmp/x-expand.sh
cp /mnt/v10root/usr/local/sbin/r36-finish-expand /tmp/x-finish.sh
sed -i "s#findfs LABEL=UBUNTU#ls /dev/${DD}p2#" /tmp/x-expand.sh
echo "  --- running the expand script (LABEL lookup replaced by the loop device) ---"
sh -x /tmp/x-expand.sh 2>&1 | tail -25 || echo "  (script exited nonzero)"
echo "  after: ${D}p2 size=$(cat /sys/block/${DD}p2/size)  resize2fs says:"
resize2fs -P "${D}p2" 2>/dev/null || true
df -h /mnt/v10root | tail -1
umount /mnt/v10root; losetup -d "$D"; rm -f "$B"
echo "=== VERIFY DONE ==="
