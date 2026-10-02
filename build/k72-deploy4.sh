#!/bin/bash
# k72-deploy4.sh - rsync-over-ssh stalled for 36 minutes with zero bytes moved
# (remote rsync --server alive, nothing transferred), so stop using rsync here.
# Kill it, then ship the module tree as one tar stream over ssh and the three
# boot files with plain scp - both of which demonstrably move data on this link.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
PW=ubuntu
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
W=/root/r36/k72test
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== [0] kill the stalled rsync/deploy ==="
for p in $(pgrep -f "k72-deploy3.sh" 2>/dev/null); do kill -9 "$p" 2>/dev/null && echo "  killed $p"; done
pkill -x rsync 2>/dev/null && echo "  killed rsync" || echo "  no rsync left"
sleep 1
ps -eo pid,cmd 2>/dev/null | grep -E "rsync|k72-deploy3" | grep -v grep | sed 's/^/  still: /' || true
S 'rm -rf /lib/modules/7.2.8; echo "  cleared empty /lib/modules/7.2.8"'

echo "=== [1] modules as one tar stream (progress reported every few MB) ==="
du -sh "$OUT/lib/modules/7.2.8" | sed 's/^/  source: /'
tar -C "$OUT/lib/modules" -cf - 7.2.8 | \
  sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'cat > /tmp/mods.tar && tar -C /lib/modules -xf /tmp/mods.tar && rm -f /tmp/mods.tar && echo "  extracted"'
S 'mkdir -p /lib/modules/7.2.8/extra'
sshpass -p $PW scp -q "$W/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" \
  "$W/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko" \
  "root@$DEV:/lib/modules/7.2.8/extra/" 2>/dev/null && echo "  aic modules copied"
S 'depmod -a 7.2.8 && echo "  depmod 7.2.8 ok"
   du -sh /lib/modules/7.2.8 | sed "s/^/    /"
   find /lib/modules/7.2.8 -name "*.ko" | wc -l | sed "s/^/    .ko count: /"
   echo "    extra: $(ls /lib/modules/7.2.8/extra/ | tr "\n" " ")"
   modprobe -n -S 7.2.8 aic8800_fdrv && echo "    modprobe -n resolves aic8800_fdrv"'

echo "=== [2] boot files to the FAT partition (scp, then verify sha256) ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot'
sshpass -p $PW scp -q "$K/arch/arm64/boot/Image" "root@$DEV:/run/r36-boot/Image-7.2.8" 2>/dev/null && echo "  Image-7.2.8 sent"
sshpass -p $PW scp -q "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" \
  "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb" 2>/dev/null && echo "  dtb sent"
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
sshpass -p $PW scp -q /tmp/boot-72.ini "root@$DEV:/run/r36-boot/boot-72.ini" 2>/dev/null && echo "  boot-72.ini sent"

echo "=== [3] byte-for-byte verification ==="
S 'sed -i "s/\r$//" /run/r36-boot/boot-72.ini; sync
   echo "  card:"
   for f in Image-7.2.8 rk3326-xifan-r36max2-7.2.8.dtb; do
     echo "    $f  $(stat -c %s /run/r36-boot/$f) B  $(sha256sum /run/r36-boot/$f | cut -c1-32)"
   done
   ls -l /run/r36-boot/*.ini | sed "s/^/    /"
   umount /run/r36-boot 2>/dev/null; echo "  BOOT unmounted"'
echo "  local:"
echo "    Image      $(stat -c %s "$K/arch/arm64/boot/Image") B  $(sha256sum "$K/arch/arm64/boot/Image" | cut -c1-32)"
echo "    dtb        $(stat -c %s "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb") B  $(sha256sum "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" | cut -c1-32)"
echo "=== deploy4 done ==="
