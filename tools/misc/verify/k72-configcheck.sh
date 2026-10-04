#!/bin/bash
# k72-configcheck.sh - the busybox initramfs is kernel-agnostic only if the
# things it needs (ext4, the SD host controller, the root device) are built in.
# Check the 7.2.8 .config against what the 6.12.79 one had.
set -uo pipefail
for K in /root/r36/linux-6.12.79 /root/r36/linux-7.2.8; do
  echo "=== $(basename "$K") ==="
  grep -E "^(CONFIG_EXT4_FS|CONFIG_MMC_BLOCK|CONFIG_MMC_DW|CONFIG_MMC_DW_ROCKCHIP|CONFIG_MFD_RK808|CONFIG_REGULATOR_RK808|CONFIG_DRM_ROCKCHIP|CONFIG_DRM_PANFROST|CONFIG_DRM_PANEL_GENERIC_DSI|CONFIG_INPUT_POLLDEV|CONFIG_SND_SOC_RK817|CONFIG_SND_SOC_ROCKCHIP_I2S|CONFIG_SND_SOC_ROCKCHIP_PDM|CONFIG_IIO|CONFIG_INPUT_JOYSTICK|CONFIG_USB_SERIAL|CONFIG_USB_NET_RNDIS_HOST|CONFIG_USB_CONFIGFS)=?" "$K/.config" 2>/dev/null | sort
  echo "  Image: $(ls -l "$K/arch/arm64/boot/Image" 2>/dev/null | awk '{print $5, $6, $7, $8}')"
done
echo "=== what the initrd insmods (if anything) ==="
grep -nE "insmod|modprobe" /mnt/e/ubuntu/scripts/build-initrd3.sh | head -8
