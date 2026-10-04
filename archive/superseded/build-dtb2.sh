#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip
K=/root/r36/linux-6.12.79
OUTW=/mnt/e/ubuntu/artifacts/dtb

echo "=== who defines the ff340000 node? ==="
grep -rln 'ff340000' "$D" 2>/dev/null | head
echo "=== labels around it ==="
grep -rn -B2 'usb@ff340000' "$D" 2>/dev/null | head -8
echo "=== our board dts: the usb/phy override blocks ==="
grep -n -A6 -E '^&usb20_otg|^&u2phy' "$D/rk3326-xifan-r36max2.dts"

echo "=== register the two variants in the Makefile ==="
grep -q 'rk3326-xifan-r36max2-usbhost.dtb' "$D/Makefile" || \
	sed -i 's/dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3326-xifan-r36max2.dtb/dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3326-xifan-r36max2.dtb\ndtb-$(CONFIG_ARCH_ROCKCHIP) += rk3326-xifan-r36max2-usbhost.dtb\ndtb-$(CONFIG_ARCH_ROCKCHIP) += rk3326-xifan-r36max2-gadget.dtb/' "$D/Makefile"
grep -n 'xifan' "$D/Makefile"

echo "=== build just those ==="
cd "$K"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | grep -E 'DTC|Error|error' | head -12
ls -la "$D"/rk3326-xifan-r36max2*.dtb
for f in usbhost gadget; do
  if [ -f "$D/rk3326-xifan-r36max2-$f.dtb" ]; then
	cp -f "$D/rk3326-xifan-r36max2-$f.dtb" "$OUTW/"
	echo "copied $f"
  else
	echo "MISSING $f"
  fi
done
echo "=== what changed in each variant ==="
for f in default usbhost gadget; do
  src=$OUTW/rk3326-xifan-r36max2-${f}.dtb
  [ -f "$src" ] || continue
  echo "--- $f"
  dtc -I dtb -O dts "$src" 2>/dev/null | grep -A3 -E 'usb@ff300000|usb@ff340000|host-port|otg-port' | grep -E 'usb@|dr_mode|status|port' | head -12
done
