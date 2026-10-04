#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip
echo "=== our board dts: includes + tail overrides ==="
head -12 "$D/rk3326-xifan-r36max2.dts"
echo "..."
grep -nE '^&[a-z0-9_]+' "$D/rk3326-xifan-r36max2.dts" | tail -30
echo "=== mainline rk3326.dtsi usb/phy labels ==="
ls "$D" | grep -E '^rk3326' | head
grep -nE 'usb20_otg:|usb_host0_ehci:|usb_host0_ohci:|u2phy:|u2phy_host:|u2phy_otg:|usb_host1' "$D/rk3326.dtsi" | head -12
echo "=== the host controller nodes' properties in mainline dtsi ==="
sed -n '/usb_host0_ehci:/,/^};/p' "$D/rk3326.dtsi" | head -20
