#!/bin/bash
# k72-deploy.sh - stage the 7.2.8 kernel onto the card WITHOUT touching the
# working 6.12.79 boot files: new names on the FAT partition (Image-7.2.8,
# rk3326-xifan-r36max2-7.2.8.dtb, boot-72.ini) plus /lib/modules/7.2.8 in the
# rootfs.  To try it: rename boot-72.ini -> boot.ini on Windows (keep the old
# one).  To go back: rename boot.ini.bak-6127 (or the saved copy) back.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
W=/root/r36/k72test
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }
SCP() { sshpass -p $PW scp -o ConnectTimeout=20 -q "$@"; }

echo "=== [1] modules into the rootfs ==="
SCP -r "$OUT/lib/modules/7.2.8" "root@$DEV:/lib/modules/"
S "mkdir -p /lib/modules/7.2.8/extra"
SCP "$W/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" \
    "$W/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko" \
    "root@$DEV:/lib/modules/7.2.8/extra/"
S 'depmod -a 7.2.8 && echo "  depmod ok"; \
   ls -l /lib/modules/7.2.8/modules.dep | awk "{print \"  modules.dep:\", \$5, \"bytes\"}"; \
   echo "  aic modules: $(ls /lib/modules/7.2.8/extra/ | tr "\n" " ")"; \
   modinfo -F vermagic /lib/modules/7.2.8/extra/aic8800_fdrv.ko | sed "s/^/  vermagic: /"'

echo "=== [2] boot files onto the FAT partition ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; \
   mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot || exit 1; \
   df -h /run/r36-boot | tail -1 | sed "s/^/  /"'
SCP "$K/arch/arm64/boot/Image"        "root@$DEV:/run/r36-boot/Image-7.2.8"
SCP "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" \
    "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb"

# build the ini locally with a quoted heredoc: ${loadaddr} etc. must survive
# verbatim for u-boot, so nothing here may be expanded by a shell.
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
grep -q "Image-7.2.8" /tmp/boot-72.ini && SCP /tmp/boot-72.ini "root@$DEV:/run/r36-boot/boot-72.ini"
S 'sed -i "s/\r$//" /run/r36-boot/boot-72.ini; echo "  boot-72.ini:"; sed "s/^/    /" /run/r36-boot/boot-72.ini | head -20'

echo "=== [3] verify what is on the card now ==="
S 'ls -l /run/r36-boot | grep -E "Image|dtb|ini|uInitrd" | sed "s/^/  /"; \
   echo "  sha256 Image-7.2.8: $(sha256sum /run/r36-boot/Image-7.2.8 | cut -c1-16)..."; \
   sync'
echo "  local Image sha256: $(sha256sum "$K/arch/arm64/boot/Image" | cut -c1-16)..."
S 'umount /run/r36-boot 2>/dev/null; echo "  BOOT unmounted (files kept)"'
echo "=== deploy done ==="
