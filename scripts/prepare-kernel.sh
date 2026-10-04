#!/bin/bash
# Prepare mainline 6.12.79 for the XiFan R36 Max 2 using Rocknix's RK3326 recipe.
set -u
R=/mnt/e/ubuntu/build/rocknix
cd /root/r36 || exit 1

if [ ! -d linux-6.12.79 ]; then
  echo "== extracting kernel =="
  tar xf linux-6.12.79.tar.xz || exit 1
fi
cd linux-6.12.79 || exit 1

echo "== applying patches =="
for p in "$R"/patches/*.patch; do
  if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
    patch -p1 -s -i "$p" >/dev/null 2>&1 && echo "ok    $(basename "$p")" || echo "FAIL  $(basename "$p")"
  else
    echo "SKIP  $(basename "$p")  (does not apply cleanly)"
  fi
done

echo "== installing board device trees =="
cp -v "$R"/dts/* arch/arm64/boot/dts/rockchip/
if ! grep -q "rk3326-xifan-r36max2" arch/arm64/boot/dts/rockchip/Makefile; then
  sed -i '/^dtb-\$(CONFIG_ARCH_ROCKCHIP) += rk3326-odroid-go3.dtb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3326-xifan-r36max2.dtb' \
      arch/arm64/boot/dts/rockchip/Makefile
  echo "added rk3326-xifan-r36max2.dtb to Makefile"
else
  echo "board dtb already in Makefile"
fi

echo "== installing generic-dsi panel driver =="
cp -v "$R"/drivers/panel-generic-dsi.c drivers/gpu/drm/panel/
if ! grep -q panel-generic-dsi drivers/gpu/drm/panel/Makefile; then
  echo 'obj-y += panel-generic-dsi.o' >> drivers/gpu/drm/panel/Makefile
fi

echo "== configuring =="
cp "$R"/config/linux.aarch64.conf .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig 2>&1 | tail -5

echo "== resulting critical options =="
grep -E "^(CONFIG_MEMCG|CONFIG_CGROUP_PIDS|CONFIG_CGROUP_BPF|CONFIG_BPF_SYSCALL|CONFIG_PSI|CONFIG_DRM_ROCKCHIP|CONFIG_DRM_PANFROST|CONFIG_CHARGER_RK817|CONFIG_SND_SOC_RK817|CONFIG_MFD_RK8XX_I2C|CONFIG_JOYSTICK_ADC|CONFIG_TOUCHSCREEN|CONFIG_RFKILL|CONFIG_USB_NET_.*)=" .config
grep -cE "rocknix|singleadc|single-adc" .config
echo "== done =="
