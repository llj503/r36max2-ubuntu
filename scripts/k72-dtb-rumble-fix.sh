#!/bin/bash
# k72-dtb-rumble-fix.sh - rebuild the board dtb with the corrected rumble
# polarity in BOTH kernel trees, install it on the card, release the sysfs
# claim on the pin, and reboot into 7.2.8.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DTS=/mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

for K in /root/r36/linux-7.2.8 /root/r36/linux-6.12.79; do
  D=$K/arch/arm64/boot/dts/rockchip
  cp -f "$DTS" "$D/"
  cp -f /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2-usbhost.dts \
        /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2-gadget.dts \
        /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2-dram-timing.dtsi "$D/" 2>/dev/null
  echo "=== dtbs in $(basename "$K") ==="
  make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | \
    grep -E "DTC|Error|error|warning" | tail -5 | sed 's/^/  /'
  ls -l "$D/rk3326-xifan-r36max2.dtb" | awk '{print "  ", $5, $9}'
done

echo "=== confirm the polarity actually changed in the compiled dtb ==="
dtc -I dtb -O dts /root/r36/linux-7.2.8/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb 2>/dev/null | \
  grep -i "rumble" | sed 's/^/  /'

echo "=== release the sysfs claim on the pin, then install the new dtb ==="
S 'echo 527 > /sys/class/gpio/unexport 2>/dev/null && echo "  unexported gpio527" || echo "  nothing to unexport"
   B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot'
sshpass -p $PW scp -q /root/r36/linux-7.2.8/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb \
  "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb" 2>/dev/null
sshpass -p $PW scp -q /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb \
  "root@$DEV:/run/r36-boot/rk3326-xifan-r36max2.dtb" 2>/dev/null
S 'sync
   echo "  installed:"; ls -l /run/r36-boot/*.dtb | sed "s/^/    /"
   echo "  sha 7.2.8 dtb: $(sha256sum /run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb | cut -c1-24)"
   umount /run/r36-boot 2>/dev/null'
echo "  local sha 7.2.8: $(sha256sum /root/r36/linux-7.2.8/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb | cut -c1-24)"

echo "=== reboot into 7.2.8 with the fixed dtb ==="
S 'echo "  rebooting"; (sleep 2; reboot) >/dev/null 2>&1 &'
echo "=== reboot issued ==="
