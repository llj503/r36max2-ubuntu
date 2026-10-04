#!/bin/bash
# Offline forensics on the prepared rootfs + kernel: why might WiFi be down, and
# can we get a USB gadget network as a keyboard-free fallback?
set -uo pipefail
R=/root/r36/rootfs
K=/root/r36/linux-6.12.79
DTB=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb

echo "=== wpa_supplicant units available in the rootfs ==="
ls /root/r36/rootfs/lib/systemd/system/ | grep -i wpa
echo "--- the one we enabled ---"
ls -l "$R/etc/systemd/system/multi-user.target.wants/" | grep -i wpa
echo "--- wpa_supplicant@.service body ---"
cat "$R/lib/systemd/system/wpa_supplicant@.service" 2>/dev/null
echo "--- wpa_supplicant-nl80211@.service body ---"
cat "$R/lib/systemd/system/wpa_supplicant-nl80211@.service" 2>/dev/null

echo "=== networkd profiles ==="
for f in "$R"/etc/systemd/network/*; do echo "--- $f"; cat "$f"; done
echo "=== journal persistence ==="
ls -ld "$R/var/log/journal" 2>/dev/null || echo "no /var/log/journal (volatile only)"
grep -E '^(#)?Storage' "$R/etc/systemd/journald.conf"

echo "=== kernel: USB gadget + wifi cfg ==="
grep -E 'CONFIG_USB_LIBCOMPOSITE|CONFIG_USB_F_ECM|CONFIG_USB_CONFIGFS|CONFIG_USB_GADGET|CONFIG_USB_DWC2|CONFIG_USB_ROLE_SWITCH|CONFIG_TYPEC' "$K/.config" | head -25
echo "=== kernel: cfg80211/rfkill ==="
grep -E 'CONFIG_CFG80211=|CONFIG_RFKILL|CONFIG_MAC80211=' "$K/.config"

echo "=== dts: usb / otg nodes ==="
dtc -I dtb -O dts "$DTB" 2>/dev/null > /tmp/r36.dts
grep -n -A6 -E 'usb@|dwc2|otg|usb2-phy|phy@ff' /tmp/r36.dts | grep -E 'dr_mode|status|compatible|usb@|otg|gadget' | head -20
echo "--- extcon / typec ---"
grep -n -E 'extcon|typec|vbus|dr_mode' /tmp/r36.dts | head -20

echo "=== aic module params / firmware list ==="
ls "$R/lib/firmware/aic8800DC/" 2>/dev/null | head
ls "$R/etc/modprobe.d/" 2>/dev/null
