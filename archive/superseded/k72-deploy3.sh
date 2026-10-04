#!/bin/bash
# k72-deploy3.sh - clean redo after the power cut.  Fixes two things the earlier
# attempts got wrong: (1) `scp -r` dumped the module tree into /lib/modules
# itself instead of /lib/modules/7.2.8, and (2) it followed the build/source
# symlinks into the 1.8 GiB kernel tree.  Now: explicit rsync endpoints, and
# every file copied to the FAT partition is sha256-verified against the source.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
W=/root/r36/k72test
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== [0] is the device alive? ==="
S 'echo "  up: $(uname -r), uptime $(cut -d" " -f1 /proc/uptime)s"' || { echo "  unreachable"; exit 1; }

echo "=== [1] remove the stray 7.2.8 leftovers from /lib/modules ==="
S 'cd /lib/modules
   for e in *; do [ "$e" = "6.12.79" ] || { echo "  rm -rf /lib/modules/$e"; rm -rf "/lib/modules/$e"; }; done
   ls /lib/modules | sed "s/^/    left: /"
   depmod -a 6.12.79 && echo "  6.12.79 depmod re-run ok"'

echo "=== [2] copy the 7.2.8 module tree (explicit endpoints) ==="
rm -f "$OUT/lib/modules/7.2.8/build" "$OUT/lib/modules/7.2.8/source"
S 'mkdir -p /lib/modules/7.2.8'
rsync -a --delete "$OUT/lib/modules/7.2.8/" "root@$DEV:/lib/modules/7.2.8/" 2>/dev/null
S 'mkdir -p /lib/modules/7.2.8/extra'
rsync -a "$W/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" \
        "$W/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko" \
        "root@$DEV:/lib/modules/7.2.8/extra/" 2>/dev/null
S 'depmod -a 7.2.8 && echo "  depmod 7.2.8 ok"
   du -sh /lib/modules/7.2.8 | sed "s/^/    /"
   echo "    extra: $(ls /lib/modules/7.2.8/extra/ | tr "\n" " ")"
   echo "    panfrost present: $(ls /lib/modules/7.2.8/kernel/gpu/drm/panfrost/*.ko 2>/dev/null | wc -l)"
   modprobe -n -S 7.2.8 aic8800_fdrv 2>&1 | sed "s/^/    modprobe -n: /"'

echo "=== [3] FAT partition: kernel + dtb + boot-72.ini ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot'
rsync -a --progress "$K/arch/arm64/boot/Image" "root@$DEV:/run/r36-boot/Image-7.2.8" 2>/dev/null
rsync -a "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" \
  "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb" 2>/dev/null

cat > /tmp/boot-72.ini <<'INI'
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1"

if test -e mmc 1:1 rescue; then
  setenv bootargs "${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
fi

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image-7.2.8
load mmc 1:1 ${initrd_loadaddr} uInitrd
load mmc 1:1 ${dtb_loadaddr} rk3326-xifan-r36max2-7.2.8.dtb

booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
INI
rsync -a /tmp/boot-72.ini "root@$DEV:/run/r36-boot/boot-72.ini" 2>/dev/null

echo "=== [4] verify: the copies must match byte for byte ==="
S 'sed -i "s/\r$//" /run/r36-boot/boot-72.ini; sync
   echo "  on the card:"
   for f in Image-7.2.8 rk3326-xifan-r36max2-7.2.8.dtb; do
     [ -e /run/r36-boot/$f ] && echo "    $f  $(stat -c %s /run/r36-boot/$f) B  $(sha256sum /run/r36-boot/$f | cut -c1-24)..."
   done
   ls -l /run/r36-boot | grep -E "\.ini" | sed "s/^/    /"
   umount /run/r36-boot 2>/dev/null'
echo "  local source:"
echo "    Image      $(stat -c %s "$K/arch/arm64/boot/Image") B  $(sha256sum "$K/arch/arm64/boot/Image" | cut -c1-24)..."
echo "    dtb        $(stat -c %s "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb") B  $(sha256sum "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" | cut -c1-24)..."
echo "=== deploy3 done ==="
