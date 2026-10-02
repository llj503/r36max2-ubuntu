#!/bin/bash
# Apply Rocknix's "mainline" patch layer (polldev, gpiolib revert, pwm helper, adc-keys redirect)
# to the already device-patched tree, verifying each step.
set -u
K=/root/r36/linux-6.12.79
M=/mnt/e/ubuntu/build/rocknix/patches-mainline
cd "$K" || exit 1

echo "=== dry-run all mainline patches ==="
for p in "$M"/*.patch; do
  if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
    echo "clean: $(basename "$p")"
  else
    echo "CONFLICT: $(basename "$p")"
  fi
done

echo "=== applying ==="
for p in "$M"/*.patch; do
  patch -p1 -s -i "$p" >/dev/null 2>&1 && echo "applied: $(basename "$p")" || echo "FAILED: $(basename "$p")"
done

echo "=== polldev restored? ==="
ls -la include/linux/input-polldev.h drivers/input/input-polldev.c 2>&1
echo "=== INPUT_POLLDEV kconfig ==="
grep -rn "INPUT_POLLDEV" drivers/input/Kconfig 2>/dev/null | head -3
