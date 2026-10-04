#!/bin/bash
# Repair the FAT boot.ini on the card that is plugged in (drive F:) so the
# v14 rootfs on it can boot again without a reflash, and clear error.log.
set -uo pipefail
B=/f
[ -d "$B" ] || { echo "F: not present"; exit 1; }
[ -f "$B/boot.ini" ] || { echo "no boot.ini on F:"; exit 1; }

cp -f "$B/boot.ini" "$B/boot.ini.broken-variable-dtb"
cat > "$B/boot.ini" <<'INI'
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1"

if test -e mmc 1:1 rescue; then
  setenv bootargs "${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
fi

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image
load mmc 1:1 ${initrd_loadaddr} uInitrd
load mmc 1:1 ${dtb_loadaddr} rk3326-xifan-r36max2.dtb

booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
INI
sed 's/rk3326-xifan-r36max2.dtb/rk3326-xifan-r36max2-usbhost.dtb/' "$B/boot.ini" > "$B/boot-usbhost.ini"
rm -f "$B/error.log"
echo "=== boot.ini now (no \${dtb}) ==="
cat "$B/boot.ini"
echo "=== checks ==="
grep -c '{dtb}' "$B/boot.ini" || true
echo "usbhost variant line: $(grep -c usbhost "$B/boot-usbhost.ini")"
ls -la "$B" | tail -12
sync
