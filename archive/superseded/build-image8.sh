#!/bin/bash
# v8 = v6 (verbose boot, rescue switch) + two preemptive fixes for the silent stall:
#   (1) SSH host keys pre-generated  -> Ubuntu's sshd refuses to start without them,
#       and in a hand-built rootfs the postinst may not have created them.
#   (2) backlight forced to max      -> a handheld whose PWM backlight drops to 0 at the
#       DRM/fbcon handover looks exactly like "system hung", while it is actually running.
set -eu
OUT=/root/r36/out
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
IMG="$OUT/r36max2-ubuntu-v8.img"
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG_GB=${1:-58}

echo "=== (1) host keys + (2) backlight unit inside the rootfs ==="
mount -t proc proc "$ROOT/proc" 2>/dev/null || true
mount --rbind /dev "$ROOT/dev" 2>/dev/null || true
chroot "$ROOT" /usr/bin/env PATH=/usr/bin:/bin ssh-keygen -A 2>&1 | tail -4
ls "$ROOT/etc/ssh/" | grep -c "^ssh_host_" | sed 's/^/  host keys: /'

cat > "$ROOT/etc/systemd/system/r36-backlight.service" <<'U'
[Unit]
Description=Force R36 Max 2 backlight to maximum early in boot
DefaultDependencies=no
After=systemd-udev-settle.service
Before=getty.target multi-user.target
ConditionPathExistsGlob=/sys/class/backlight/*

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for b in /sys/class/backlight/*; do [ -w "$b/brightness" ] || continue; max=$(cat "$b/max_brightness" 2>/dev/null || echo 255); echo "$max" > "$b/brightness" && echo "r36-backlight: $b -> $max"; done'

[Install]
WantedBy=sysinit.target
U
ln -sf /etc/systemd/system/r36-backlight.service "$ROOT/etc/systemd/system/sysinit.target.wants/r36-backlight.service" 2>/dev/null || true
mkdir -p "$ROOT/etc/systemd/system/sysinit.target.wants"
ln -sf /etc/systemd/system/r36-backlight.service "$ROOT/etc/systemd/system/sysinit.target.wants/r36-backlight.service"
chroot "$ROOT" /bin/sh -c 'systemctl enable ssh.service ssh.socket 2>&1 | tail -2' || true
umount -R "$ROOT/dev" 2>/dev/null || true
umount "$ROOT/proc" 2>/dev/null || true

echo "=== (3) image assembly (uInitrd already rebuilt by build-initrd3.sh) ==="
[ -f "$BOOT_SRC/uInitrd" ] || { echo "FATAL: $BOOT_SRC/uInitrd missing - run build-initrd3.sh first"; exit 1; }

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt7
sfdisk -q "$IMG" < /tmp/pt7
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none
losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")

MNT=/mnt/r36v8
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"
cp "$BOOT_SRC/Image" "$MNT/boot/Image"
cp "$BOOT_SRC/uInitrd" "$MNT/boot/uInitrd"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"

cat > "$MNT/boot/boot.ini" <<INI
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1"

# Create an empty file named "rescue" on this BOOT partition to get a root shell
# on the panel instead of the normal boot (minimal services only).
if test -e mmc 1:1 rescue; then
  setenv bootargs "\${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
fi

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 \${loadaddr} Image
load mmc 1:1 \${initrd_loadaddr} uInitrd
load mmc 1:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb

booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
INI
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1
ELX

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=6.12.79 hostkeys=pre backlight=forced init=systemd-sysv built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== verify ==="
losetup -P -f "$IMG"; L2=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v8/boot /mnt/v8/root
mount -o ro "${L2}p1" /mnt/v8/boot; mount -o ro "${L2}p2" /mnt/v8/root
ls /mnt/v8/boot
echo -n "  host keys in image: "; ls /mnt/v8/root/etc/ssh/ | grep -c "^ssh_host_.*_key$"
echo -n "  backlight unit: "; [ -e /mnt/v8/root/etc/systemd/system/r36-backlight.service ] && echo present || echo MISSING
umount /mnt/v8/root /mnt/v8/boot; losetup -d "$L2"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v8.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v8.img.xz | tee r36max2-ubuntu-v8.img.xz.sha256
echo "=== V7 DONE ==="
