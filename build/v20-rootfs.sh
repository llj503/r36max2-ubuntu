#!/bin/bash
# v20-rootfs.sh - put BOTH kernels' module trees into the staging rootfs, with the
# out-of-tree .ko that were each verified on hardware, and prove it with depmod +
# modprobe --dry-run inside the chroot.
#
# Two traps this script exists to avoid:
#   * modules_install leaves `build` and `source` symlinks into the 1.8 GB kernel
#     tree; if they survive into the image every card gets a dangling multi-GB
#     symlink (and anything copying with -r follows them).
#   * a tree can only be built for one kernel at a time, so "which .ko is this"
#     must be answered by vermagic + sha, never by the filename or the mtime.
set -uo pipefail
R=/root/r36/rootfs
K6=/root/r36/linux-6.12.79
K7=/root/r36/linux-7.2.8
OUT=/root/r36/out
OUT72=/root/r36/out72
AJ=/mnt/e/ubuntu/artifacts/joypad
AA=/mnt/e/ubuntu/artifacts/aic72
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== [1] 7.2.8 module tree ==="
rm -rf "$R/lib/modules/7.2.8"
cp -a "$OUT72/lib/modules/7.2.8" "$R/lib/modules/"
rm -f "$R/lib/modules/7.2.8/build" "$R/lib/modules/7.2.8/source"
echo "  staged $(find "$R/lib/modules/7.2.8" -name '*.ko' | wc -l) .ko, $(du -sh "$R/lib/modules/7.2.8" | cut -f1)"
echo "  build/source symlinks left: $(find "$R/lib/modules/7.2.8" -maxdepth 1 -name build -o -maxdepth 1 -name source | wc -l)"

echo
echo "=== [2] out-of-tree .ko for 7.2.8 (each one proven on the card) ==="
mkdir -p "$R/lib/modules/7.2.8/extra"
cp -f "$AA/aic8800_fdrv-7.2.8.ko"  "$R/lib/modules/7.2.8/extra/aic8800_fdrv.ko"
cp -f "$AA/aic_load_fw-7.2.8.ko"   "$R/lib/modules/7.2.8/extra/aic_load_fw.ko"
cp -f "$AJ/rocknix-singleadc-joypad-7.2.8.ko" "$R/lib/modules/7.2.8/extra/rocknix-singleadc-joypad.ko"
cp -f "$AJ/rocknix-joypad-7.2.8.ko"            "$R/lib/modules/7.2.8/extra/rocknix-joypad.ko"
for f in "$R"/lib/modules/7.2.8/extra/*.ko; do
  echo "  $(basename "$f"): $(stat -c%s "$f") B vermagic=$(modinfo -F vermagic "$f" | awk '{print $1}') $(sha256sum "$f" | cut -c1-16)"
done

echo
echo "=== [3] 6.12.79 side stays as shipped in v19 (legacy joypad .ko, hardware-verified) ==="
for f in "$R"/lib/modules/6.12.79/extra/*.ko; do
  [ -e "$f" ] && echo "  $(basename "$f"): $(stat -c%s "$f") B vermagic=$(modinfo -F vermagic "$f" | awk '{print $1}') $(sha256sum "$f" | cut -c1-16)"
done
echo "  6.12 tree: $(find "$R/lib/modules/6.12.79" -name '*.ko' | wc -l) .ko"

echo
echo "=== [4] chroot housekeeping + depmod for both kernels ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 755 "$R/usr/sbin/policy-rc.d"
chroot "$R" /usr/bin/env depmod -a 7.2.8  && echo "  depmod 7.2.8 ok"
chroot "$R" /usr/bin/env depmod -a 6.12.79 && echo "  depmod 6.12.79 ok"
for m in aic8800_fdrv aic_load_fw rocknix_singleadc_joypad; do
  for kv in 7.2.8 6.12.79; do
    out=$(chroot "$R" /usr/bin/env modprobe -n -S "$kv" "$m" 2>&1)
    echo "  modprobe -n $m @ $kv : ${out:-OK}"
  done
done
echo "  modules-load.d: $(tr '\n' ' ' < "$R/etc/modules-load.d/r36max2.conf")"

echo
echo "=== [5] the boot files the packer will copy ==="
ls -l "$OUT/boot" | sed 's/^/  /'
echo "  polarity check (want amux-a flags 0x00, amux-en 0x01, rumble 0x00):"
for f in "$OUT/boot/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb"; do
  echo "    $(basename "$f"):"
  dtc -I dtb -O dts "$f" 2>/dev/null | grep -E "amux-a-gpios|amux-en-gpios|rumble-gpio" | sed 's/^/        /'
done
rm -f "$R/usr/sbin/policy-rc.d"
echo "=== rootfs staging done ==="
