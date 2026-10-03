#!/bin/bash
# k72-joypad-deploy-fix.sh - install the polarity-corrected 7.2.8 dtb and the
# gpiod joypad module on the card.  Usage:
#   bash k72-joypad-deploy-fix.sh           # copy + verify only
#   bash k72-joypad-deploy-fix.sh reboot    # ...and reboot into them
#
# Deliberately does NOT touch the 6.12 dtb on the card: that file plus
# boot-612.ini is the known-good escape hatch, and the legacy 6.12 module uses
# the integer GPIO API, which ignores DT polarity anyway.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-$(cat /mnt/e/ubuntu/build/.dev-ip 2>/dev/null || echo 192.168.31.209)}
DTB=/mnt/e/ubuntu/artifacts/dtb/rk3326-xifan-r36max2-7.2.8-gpiodfix.dtb
KO=/mnt/e/ubuntu/artifacts/joypad/rocknix-singleadc-joypad-7.2.8.ko
KO2=/mnt/e/ubuntu/artifacts/joypad/rocknix-joypad-7.2.8.ko
GO=${1:-}
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }
# the redirect has to be quoted so it is evaluated on the device, not here
COPY() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "cat > $1"; }
echo "=== device $DEV ==="
S 'uname -r | sed "s/^/  running kernel: /"' || { echo "  !! not reachable"; exit 1; }

echo "=== [0] can we still log in? ==="
sshpass -p $PW ssh -o ConnectTimeout=8 root@$DEV 'true' 2>&1 | grep -qiE "permission denied" && {
  echo "  !! password auth rejected - the card now only accepts keys."
  echo "  Push the WSL public key with the Windows OpenSSH client:"
  echo "     Get-Content \$env:USERPROFILE\\.ssh\\id_ed25519.pub | ssh root@$DEV 'mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'"
  exit 1
}

echo "=== [1] kernel-side: joypad .ko for 7.2.8 ==="
# `cat >` over ssh instead of scp: the .ko path has no FAT quirks and this
# avoids scp following stray symlinks (the pitfall that dumped 82 MB into
# /lib/modules earlier).
COPY /lib/modules/7.2.8/extra/rocknix-singleadc-joypad.ko < "$KO"
COPY /lib/modules/7.2.8/extra/rocknix-joypad.ko < "$KO2"
S 'depmod -a 7.2.8
   echo "  installed:"; ls -l /lib/modules/7.2.8/extra/*.ko | sed "s/^/    /"
   echo "  modprobe dry run: $(modprobe -n -S 7.2.8 rocknix_singleadc_joypad 2>&1 || echo OK)"
   echo "  modules-load.d lists: $(cat /etc/modules-load.d/r36max2.conf 2>/dev/null | tr "\n" " ")"
   echo "  sha on card:"
   for f in /lib/modules/7.2.8/extra/*.ko; do echo "    $(basename $f) $(sha256sum $f | cut -c1-16)"; done'
echo "  sha at home:"
sha256sum "$KO" "$KO2" | cut -c1-16,68- | sed 's/^/    /'

echo "=== [2] FAT: the 7.2.8 dtb with the corrected gpio flags ==="
S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mountpoint -q /run/r36-boot || mount -o shortname=mixed "$B" /run/r36-boot
   cp -f /run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb /run/r36-boot/rk3326-xifan-r36max2-7.2.8-prev.dtb 2>/dev/null && echo "  previous dtb kept as rk3326-xifan-r36max2-7.2.8-prev.dtb"'
COPY /run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb < "$DTB"
S 'sync
   echo "  on card : $(sha256sum /run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb | cut -c1-16) $(stat -c%s /run/r36-boot/rk3326-xifan-r36max2-7.2.8.dtb) B"
   echo "  boot.ini: $(grep -oE "Image[^ ]*|rk3326[^ ]*dtb" /run/r36-boot/boot.ini | tr "\n" " ")"
   sync; umount /run/r36-boot && echo "  FAT unmounted cleanly"'
echo "  at home : $(sha256sum "$DTB" | cut -c1-16) $(stat -c%s "$DTB") B"

echo "=== [3] reboot? ==="
if [ "$GO" = "reboot" ]; then
  S '(sleep 2; reboot) >/dev/null 2>&1 &'
  echo "  reboot issued - the DT flags only take effect on the next boot"
else
  echo "  not rebooting (pass reboot as the first argument). The dtb change needs a boot cycle."
fi
echo "=== deploy-fix done ==="
