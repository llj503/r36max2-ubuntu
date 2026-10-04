#!/bin/bash
set -uo pipefail
V=${V:-v18}
I=/root/r36/out/r36max2-ubuntu-$V.img
losetup -D 2>/dev/null || true
losetup -P -f "$I"; L=$(losetup -j "$I" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/vb /mnt/vr; mount -o ro "${L}p1" /mnt/vb; mount -o ro "${L}p2" /mnt/vr
R=/mnt/vr
echo "=== $V image contents ==="
echo "  build-info : $(cat $R/etc/r36max2-build-info)"
echo "  alsa       : $(ls $R/usr/bin/amixer $R/usr/bin/speaker-test $R/usr/bin/arecord >/dev/null 2>&1 && echo present || echo MISSING)"
echo "  evtest     : $(ls $R/usr/bin/evtest >/dev/null 2>&1 && echo present || echo MISSING)"
echo "  udevd      : $(ls $R/usr/lib/systemd/systemd-udevd >/dev/null 2>&1 && echo present)"
echo "  python3    : $(ls $R/usr/bin/python3 >/dev/null 2>&1 && echo present)  fbshot: $(ls $R/usr/local/bin/r36-fbshot >/dev/null 2>&1 && echo present)"
echo "  timesyncd  : $(grep -h NTP= $R/etc/systemd/timesyncd.conf.d/r36.conf | cut -c1-42)"
echo "  audio unit : $(grep -c 'for i in \$(seq 1 60)' $R/usr/local/sbin/r36-audio) wait-loop, After=$(grep -m1 '^After=' $R/etc/systemd/system/r36-audio.service)"
echo "  power key  : $(grep -h HandlePowerKey $R/etc/systemd/logind.conf.d/99-r36-power.conf)"
echo "  masked     : $(ls $R/etc/systemd/system/ | grep -cE '^(suspend|hibernate|sleep|hybrid)')"
echo "  wpa        : $(ls $R/etc/systemd/system/multi-user.target.wants/ | grep -i wpa | tr '\n' ' ')"
echo "  wifi driver: $(strings -a $R/usr/lib/modules/6.12.79/extra/aic8800_fdrv.ko | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "  h_u02 fw   : $(ls $R/lib/firmware/aic8800DC | grep -c h_u02) files"
echo "  gpu opp    : $(dtc -I dtb -O dts /mnt/vb/rk3326-xifan-r36max2.dtb 2>/dev/null | awk '/opp-table-gpu \{/{f=1} f&&/opp-microvolt/{print $3; exit}')"
echo "  resolv     : $(grep -c nameserver $R/etc/resolv.conf) servers, locale=$(cat $R/etc/default/locale)"
echo "  BOOT       : $(ls /mnt/vb | tr '\n' ' ')"
echo "  boot.ini   : \${dtb}=$(grep -c '{dtb}' /mnt/vb/boot.ini) bytes=$(stat -c %s /mnt/vb/boot.ini)"
echo "  rootfs df  : $(df -h $R | tail -1 | awk '{print $2, $3, $4}')"
umount /mnt/vr /mnt/vb; losetup -d "$L"
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-$V.img.xz*
echo "=== DONE ==="
