#!/bin/bash
# Why can't it wake? Check the driver side and our device tree for the missing
# wakeup-source properties.
set -uo pipefail
K=/root/r36/linux-6.12.79
D=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts

echo "=== our pmic / pwrkey node ==="
sed -n '/rk817: pmic@20/,/^\t\t};/p' "$D" | head -30
echo "--- any wakeup-source in the whole board dts? ---"
grep -n "wakeup-source" "$D" || echo "  NONE at all"

echo "=== does the mainline pwrkey driver support wakeup? ==="
f=$(grep -rl "rk805_pwrkey\|rk8xx_pwrkey" "$K/drivers/input/keyboard" "$K/drivers/power" 2>/dev/null | grep '\.c$' | head -1)
echo "  driver: $f"
[ -n "$f" ] && grep -nE "wakeup|device_init_wakeup|enable_irq_wake|of_property_read|wakeup-source" "$f" | head -12

echo "=== rk808 mfd: does it propagate wake to its irq domain? ==="
grep -nE "wake|irq_set_wake|wake_base|device_init_wakeup" "$K/drivers/mfd/rk808.c" | head -12
echo "=== rk817 codec: does it have a suspend op? ==="
grep -nE "suspend|resume|set_bias_level|STANDBY" "$K/sound/soc/codecs/rk817.c" | head -12

echo "=== kernel config: suspend support on this SoC ==="
grep -E "CONFIG_SUSPEND=|CONFIG_PM_SLEEP|CONFIG_ROCKCHIP_PM_DOMAINS|CONFIG_SUSPEND_FREEZER|CONFIG_HIBERNATION|CONFIG_PM_DEBUG" "$K/.config"

echo "=== is there a rockchip pm/sip suspend path for rk3326? ==="
grep -rnE "rk3326|px30" "$K/drivers/soc/rockchip/pm_domains.c" | head -5
ls "$K/drivers/firmware" 2>/dev/null | head -5
grep -nE "CONFIG_MFD_RK808|CONFIG_INPUT_KEYBOARD|CONFIG_RTC_DRV_RK808|CONFIG_REGULATOR_RK808" "$K/.config"
