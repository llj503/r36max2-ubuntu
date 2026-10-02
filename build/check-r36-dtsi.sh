#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip
echo "=== does mainline rk3326.dtsi have the ff340000/ff350000 host nodes at all? ==="
grep -n -B4 -A14 'usb@ff340000' "$D/rk3326.dtsi" | head -40
echo "=== rk3326-device-group-r36.dtsi (mainline support for the R36 family) ==="
ls -la "$D/rk3326-device-group-r36.dtsi" 2>/dev/null
grep -nE 'usb|dr_mode|wifi|bt|vbus|extcon|otg' "$D/rk3326-device-group-r36.dtsi" 2>/dev/null | head -30
echo "=== which boards include it? ==="
grep -ln 'rk3326-device-group-r36.dtsi' "$D"/*.dts "$D"/*.dtsi 2>/dev/null | head
echo "=== how does rg351v set up usb20_otg + the aic/esp wifi? ==="
grep -n -A6 -E '&usb20_otg|&u2phy' "$D/rk3326-anbernic-rg351v.dts" 2>/dev/null | head -30
echo "=== mainline: any aic8800 driver? ==="
ls /root/r36/linux-6.12.79/drivers/net/wireless/ | head -30
