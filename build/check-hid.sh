#!/bin/bash
set -uo pipefail
K=/root/r36/linux-6.12.79
D=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
echo "=== HID / keyboard input in the kernel config ==="
grep -E 'CONFIG_USB_HID=|CONFIG_HID=|CONFIG_INPUT=|CONFIG_INPUT_KEYBOARD=|CONFIG_USB_SUPPORT=|CONFIG_USB_XHCI_HCD|CONFIG_USB_EHCI_HCD=|CONFIG_USB_OHCI_HCD=|CONFIG_KEYBOARD_GPIO=' "$K/.config" || echo "(none of the optional ones)"
echo "=== the dts: who owns which controller ==="
grep -n -B2 -A8 -E '^&usb_host|^&usb20_otg|^&u2phy|usb_host[01]|vcc5_usb' "$D" | head -60
echo "=== the vendor BSP dts (from the device) for comparison: usb_host nodes ==="
grep -n -A10 -E 'usb_host[0-9]?_ehci|usb_host[0-9]?_ohci|&usb_host' /mnt/e/ubuntu/artifacts/live.dts 2>/dev/null | head -40
echo "=== vendor BSP: which controller carries wifi (look for the 5v/wifi supply names) ==="
grep -nE 'vbus_wifi|vcc5_usb1|vcc5_usb\b|otg_vbus|dr_mode' /mnt/e/ubuntu/artifacts/live.dts 2>/dev/null | head -20
