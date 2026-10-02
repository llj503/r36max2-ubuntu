#!/bin/bash
# Which USB controller is the Type-C host port on this board? Compare the vendor
# BSP dtb (taken from the running EmuELEC) with our mainline board dts.
set -uo pipefail
A=/mnt/e/ubuntu/artifacts
K=/root/r36/linux-6.12.79
D=$K/arch/arm64/boot/dts/rockchip
ls "$A" | head -20
echo "=== vendor BSP dtb: usb nodes ==="
dtc -I dtb -O dts "$A/rk3326-evb-lp3-v12-linux.dtb" 2>/dev/null > /tmp/vendor.dts
awk '/^\t\tusb@|^\t\tpusbdt|^\t\tusb[a-z0-9_]*:/{p=1; name=$0} p{print name" | "$0} /^\t\t};/{p=0}' /tmp/vendor.dts | grep -E 'usb@|status|dr_mode|compatible|phys|phy_type' | head -40
echo "=== vendor: labels of the host controllers ==="
grep -nE 'usb_host0_ehci|usb_host1_ehci|usb20_otg|usb_host0_ohci|u2phy_host|u2phy_otg' /tmp/vendor.dts | head
echo "=== vendor: what is on the dwc2 / does it look like a wifi host ==="
grep -nE 'vbus_wifi|vcc5_usb|regulator-name = "vbus|enable-active-low|regulator-boot-on' /tmp/vendor.dts | head -20
echo "=== mainline rk3326.dtsi: the addresses behind the labels ==="
grep -nE 'usb_host0_ehci:|usb_host0_ohci:|usb_host1_ehci:|usb_host1_ohci:|usb20_otg:|u2phy:' "$D/rk3326.dtsi" | head -12
echo "=== our board dts: anything referencing usb_host*? ==="
grep -nE 'usb_host|&u2phy' "$D/rk3326-xifan-r36max2.dts"
