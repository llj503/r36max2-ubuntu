#!/bin/bash
# Can this build boot a USB keyboard on the handheld's Type-C port?
set -uo pipefail
K=/root/r36/linux-6.12.79
R=/root/r36/rootfs
echo "=== host / xhci / ehci ==="
grep -E 'CONFIG_USB_XHCI_HCD|CONFIG_USB_EHCI_HCD|CONFIG_USB_OHCI_HCD|CONFIG_USB_ROCKCHIP_INNO_USB2|CONFIG_USB_DWC2' "$K/.config"
echo "=== gadget functions ==="
grep -E 'CONFIG_USB_CONFIGFS_(ECM|NCM|RNDIS)|CONFIG_USB_GADGET=' "$K/.config"
echo "=== input / keyboard ==="
grep -E 'CONFIG_INPUT_KEYBOARD|CONFIG_KEYBOARD_GPIO|CONFIG_USB_HID|CONFIG_HID_GENERIC|CONFIG_INPUT_EVDEV|CONFIG_NEW_LEDS|CONFIG_LEDS_CLASS' "$K/.config"
echo "=== console fb (so the keyboard reaches the login prompt) ==="
grep -E 'CONFIG_FRAMEBUFFER_CONSOLE|CONFIG_DRM_PANEL_GENERIC_DSI|CONFIG_DRM_ROCKCHIP|CONFIG_VT' "$K/.config"
echo "=== does the rootfs have on-device console tools? ==="
for b in showkeys evtest readkey kbd loadkeys openvt; do
  chroot "$R" /bin/sh -c "command -v $b" >/dev/null 2>&1 && echo "have $b" || echo "no $b"
done
echo "=== rockchip usb phy nodes in the board dts ==="
D=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
grep -nE 'usb|phy|otg|dr_mode|vbus' "$D" | head -25
echo "=== the EHCI/OHCI hosts in the compiled dtb (are they status=okay?) ==="
dtc -I dtb -O dts "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" 2>/dev/null > /tmp/x.dts
awk '/usb@ff3[45]0000|usb@ff300000/{p=1} p{print NR": "$0} /^\t};/{p=0}' /tmp/x.dts | grep -E 'usb@|status|dr_mode|phy_type|vbus|compatible' | head -30
