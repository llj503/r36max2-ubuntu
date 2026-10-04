#!/bin/bash
# k72-gaps.sh - pin down exactly how big the 7.2.8 port is: (a) did mainline
# drop input-polldev (the joypad driver depends on it), (b) are the 13
# conflicting panfrost patches already upstream, (c) which of our dts bindings
# really are missing (the previous grep only looked under drivers/).
set -uo pipefail
K=/root/r36/linux-7.2.8
cd "$K" || exit 1

echo "=== (a) polled input device API in 7.2.8 ==="
ls include/linux/ | grep -iE "input.*poll|polldev" || echo "  no polldev header"
grep -rn "input_allocate_polled_device\|struct input_polled_dev" include/linux/input.h include/linux/input/*.h 2>/dev/null | head -5
echo "  in-tree users of polled devices:"
grep -rl "input_polled_dev" drivers/ | head -8
echo "  CONFIG_INPUT_POLLDEV still a symbol?"; grep -rn "INPUT_POLLDEV" drivers/input/Kconfig | head -3 || echo "    gone from Kconfig"

echo "=== (b) are the conflicting panfrost features already upstream? ==="
for t in SYSTEM_TIMESTAMP DRM_PANFROST_CYCLES GEM_SET_LABELS LABEL panfrost_gem_open; do
  n=$(grep -rl "$t" drivers/gpu/drm/panfrost/ include/uapi/drm/panfrost_drm.h 2>/dev/null | wc -l)
  echo "  '$t' -> $n file(s) in panfrost"
done
grep -n "CYCLES\|TIMESTAMP\|LABEL" include/uapi/drm/panfrost_drm.h 2>/dev/null | head -8

echo "=== (c) re-check the dts bindings across the whole tree ==="
for c in simple-audio-card simple-audio-amplifier rocknix,generic-dsi rocknix-singleadc-joypad xifan,r36max2; do
  n=$(grep -rl "\"$c\"" --include=*.c --include=*.h --include=*.yaml --include=*.dts --include=*.dtsi . 2>/dev/null | head -1)
  printf '  %-28s %s\n' "$c" "${n:-NOT IN TREE}"
done
echo "  Rocknix's own driver sources we would have to carry:"
ls /mnt/e/ubuntu/build/rocknix/drivers 2>/dev/null | head -10
ls /mnt/e/ubuntu/build/rocknix/dts 2>/dev/null | head -10

echo "=== (d) what does the 6.12 -> 7.2 delta say about our other deps? ==="
for cfg in CONFIG_DRM_PANEL_SIMPLE CONFIG_SND_SOC_RK817 CONFIG_SND_SOC_ROCKCHIP_I2S CONFIG_TOUCHSCREEN_CAPACITIVE CONFIG_IIO_CONFIGFS CONFIG_PWM; do
  v=$(grep -m1 "^$cfg" .config || echo "$cfg is not set")
  echo "  $v"
done
echo "=== gaps done ==="
