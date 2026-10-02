#!/bin/bash
# Build two experiment DTBs the user can drop onto the FAT BOOT partition
# (no reflash needed - boot.ini loads the dtb by name from there).
set -eu
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip
K=/root/r36/linux-6.12.79
OUTW=/mnt/e/ubuntu/artifacts/dtb
mkdir -p "$OUTW"

echo "=== where do the ff340000/ff350000 host nodes come from? ==="
grep -rn 'ff340000\|ff350000' "$D"/rk3326*.dtsi "$D"/rk3326*.dts 2>/dev/null | head
echo "=== labels ==="
grep -rnE 'usb_host[0-9a-z_]*:|usb20_otg:' "$D"/rk3326.dtsi "$D"/rk3326-xifan-r36max2.dts 2>/dev/null | head

echo "=== variant A: Type-C as USB HOST (enable ehci/ohci + vbus_host) ==="
cat > "$D/rk3326-xifan-r36max2-usbhost.dts" <<'EOF'
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/* r36max2 + the second USB2 host port turned on (OTG keyboard / mouse test) */
#include "rk3326-xifan-r36max2.dts"

&u2phy {
	status = "okay";

	u2phy_host: host-port {
		status = "okay";
	};
};

&usb_host0_ehci {
	status = "okay";
};

&usb_host0_ohci {
	status = "okay";
};
EOF

echo "=== variant B: Type-C as USB DEVICE (gadget/RNDIS; WiFi will drop) ==="
cat > "$D/rk3326-xifan-r36max2-gadget.dts" <<'EOF'
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/* r36max2 with the dwc2 pinned to peripheral mode -> USB gadget networking */
#include "rk3326-xifan-r36max2.dts"

&usb20_otg {
	dr_mode = "peripheral";
	vbus-supply = <&vbus_host1>;
};
EOF

cd "$K"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs -j4 2>&1 | tail -6
ls -la "$D"/rk3326-xifan-r36max2*.dtb
cp -f "$D"/rk3326-xifan-r36max2-usbhost.dtb "$OUTW/" 2>/dev/null || echo "A failed"
cp -f "$D"/rk3326-xifan-r36max2-gadget.dtb "$OUTW/" 2>/dev/null || echo "B failed"
cp -f "$D"/rk3326-xifan-r36max2.dtb "$OUTW/rk3326-xifan-r36max2-default.dtb"
ls -la "$OUTW"
echo "dtc warnings for variant A/B:"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | grep -iE 'error|warning.*(usb_host|dr_mode)' | head -5 || echo "  clean"
