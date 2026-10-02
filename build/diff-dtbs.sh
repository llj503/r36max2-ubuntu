#!/bin/bash
cd /mnt/e/ubuntu/artifacts/dtb || exit 1
for f in default usbhost gadget; do
  d=rk3326-xifan-r36max2-$f.dtb
  echo "### $f ($d)"
  dtc -I dtb -O dts "$d" 2>/dev/null > /tmp/v-$f.dts
  echo "-- dwc2 ff300000:"
  sed -n '/usb@ff300000 {/,/^\t\t};/p' /tmp/v-$f.dts | grep -E 'dr_mode|status|vbus'
  echo "-- ehci ff340000 / ohci ff350000:"
  sed -n '/usb@ff340000 {/,/^\t\t};/p;/usb@ff350000 {/,/^\t\t};/p' /tmp/v-$f.dts | grep -E 'usb@|status'
  echo "-- usb2-phy ports:"
  sed -n '/usb2-phy@100/,/^\t\t};/p' /tmp/v-$f.dts | grep -E 'host-port|otg-port|status' | head -6
done
echo "### md5 of the three (identical means the overrides did nothing)"
md5sum rk3326-xifan-r36max2-*.dtb
