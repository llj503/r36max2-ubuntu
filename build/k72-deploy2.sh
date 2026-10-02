#!/bin/bash
# k72-deploy2.sh - the first attempt hung because modules_install leaves
# build/ and source/ symlinks pointing into the 1.8 GiB kernel tree, and
# `scp -r` follows them.  Drop those links, clean up anything the aborted copy
# left on the card, then copy the module tree with rsync (keeps symlinks as
# symlinks) and continue with the FAT partition staging.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
W=/root/r36/k72test
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== clean the aborted copy on the device ==="
S 'du -sh /lib/modules/7.2.8 2>/dev/null; rm -rf /lib/modules/7.2.8; echo "  removed; now: $(ls /lib/modules/ | tr "\n" " ")"'

echo "=== drop the build/source symlinks from the staged tree ==="
ls -l "$OUT/lib/modules/7.2.8/" | grep -E "build|source" | sed 's/^/  /'
rm -f "$OUT/lib/modules/7.2.8/build" "$OUT/lib/modules/7.2.8/source"

echo "=== copy modules with rsync (-a keeps symlinks) ==="
time rsync -a "$OUT/lib/modules/7.2.8" "root@$DEV:/lib/modules/" 2>&1 | tail -3
S 'mkdir -p /lib/modules/7.2.8/extra'
sshpass -p $PW scp -o ConnectTimeout=20 -q \
  "$W/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" \
  "$W/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko" \
  "root@$DEV:/lib/modules/7.2.8/extra/" 2>/dev/null
S 'depmod -a 7.2.8 && echo "  depmod ok"; \
   du -sh /lib/modules/7.2.8 | sed "s/^/  installed: /"; \
   echo "  extra: $(ls /lib/modules/7.2.8/extra/ | tr "\n" " ")"; \
   modinfo -F vermagic /lib/modules/7.2.8/extra/aic8800_fdrv.ko | sed "s/^/  vermagic: /"; \
   echo "  running kernel still: $(uname -r)"'

echo "=== FAT partition staging ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; \
   mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot || exit 1; \
   df -h /run/r36-boot | tail -1 | sed "s/^/  /"'
sshpass -p $PW scp -o ConnectTimeout=20 -q "$K/arch/arm64/boot/Image" \
  "root@$DEV:/run/r36-boot/Image-7.2.8" 2>/dev/null && echo "  Image-7.2.8 copied"
sshpass -p $PW scp -o ConnectTimeout=20 -q \
  "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" \
  "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb" 2>/dev/null && echo "  dtb copied"

# ${loadaddr} etc. must reach u-boot verbatim, hence the quoted heredoc
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
grep -c "Image-7.2.8" /tmp/boot-72.ini | sed 's/^/  boot-72.ini lines with the new kernel: /'
sshpass -p $PW scp -q /tmp/boot-72.ini "root@$DEV:/run/r36-boot/boot-72.ini" 2>/dev/null
S 'sed -i "s/\r$//" /run/r36-boot/boot-72.ini; \
   echo "  boot-72.ini on the card:"; cat /run/r36-boot/boot-72.ini | sed "s/^/    /" | head -22; \
   echo "  --- boot files now:"; ls -l /run/r36-boot | grep -E "Image|\.dtb|\.ini|uInitrd" | sed "s/^/    /"; \
   echo "  sha256 Image-7.2.8 : $(sha256sum /run/r36-boot/Image-7.2.8 | cut -c1-24)..."; \
   sync; umount /run/r36-boot 2>/dev/null; echo "  BOOT unmounted"'
echo "  local Image sha256 : $(sha256sum "$K/arch/arm64/boot/Image" | cut -c1-24)..."
echo "=== deploy2 done ==="
