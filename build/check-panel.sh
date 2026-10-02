#!/bin/bash
K=/root/r36/linux-6.12.79
cd "$K"
echo "=== panel-generic-dsi: is the missing panel-timing fatal? ==="
sed -n '630,700p' drivers/gpu/drm/panel/panel-generic-dsi.c
echo
echo "=== does the r36max2 dts provide panel-timing or only panel_description? ==="
grep -n "panel-timing\|panel_description\|display-timings" arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts | head -8
echo
echo "=== busybox-static applets we can rely on in the initramfs ==="
/root/r36/bs/busybox busybox 2>/dev/null | head -2 || true
for a in sh mount umount switch_root blkid cat ls grep mkdir mknod sleep usleep modprobe; do
  printf "  %-12s " "$a"; /root/r36/bs/busybox "$a" --help >/dev/null 2>&1 && echo yes || echo no
done
echo
echo "=== kernel rebuild status ==="
tail -3 /root/r36/b5.log; ls -la arch/arm64/boot/Image
