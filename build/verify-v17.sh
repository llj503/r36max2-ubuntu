#!/bin/bash
set -uo pipefail
I=/root/r36/out/r36max2-ubuntu-v17.img
losetup -D 2>/dev/null || true
losetup -P -f "$I"
L=$(losetup -j "$I" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v17b /mnt/v17r
mount -o ro "${L}p1" /mnt/v17b; mount -o ro "${L}p2" /mnt/v17r
R=/mnt/v17r

echo "=== GPU OPP fix inside the shipped dtb ==="
awk '/opp-table-gpu \{/{f=1} f&&/opp-microvolt/{print "  first opp voltage:", $3; exit}' <(dtc -I dtb -O dts /mnt/v17b/rk3326-xifan-r36max2.dtb 2>/dev/null)
echo "  gpu points at: $(dtc -I dtb -O dts /mnt/v17b/rk3326-xifan-r36max2.dtb 2>/dev/null | awk '/gpu@ff400000 \{/,/^\t\};/' | grep operating-points)"

echo "=== wifi stack ==="
echo "  driver    : $(strings -a $R/usr/lib/modules/6.12.79/extra/aic8800_fdrv.ko | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "  h_u02 fw  : $(ls $R/lib/firmware/aic8800DC | grep -c h_u02) files"
echo "  wpa wants : $(ls $R/etc/systemd/system/multi-user.target.wants/ | grep -i wpa | tr '\n' ' ')"
echo "  wpa exec  : $(grep -m1 ExecStart= $R/etc/systemd/system/r36-wpa@.service | cut -c1-70)"

echo "=== udev / time / power ==="
echo "  udevd     : $(ls $R/usr/lib/systemd/systemd-udevd >/dev/null 2>&1 && echo present)"
echo "  sysinit   : $(ls $R/etc/systemd/system/sysinit.target.wants/ | grep -i udev | tr '\n' ' ')"
echo "  sockets   : $(ls $R/etc/systemd/system/sockets.target.wants/ | grep -i udev | tr '\n' ' ')"
echo "  timesyncd : $(ls $R/etc/systemd/system/multi-user.target.wants/ | grep timesync) / $(cat $R/etc/systemd/timesyncd.conf.d/r36.conf | grep NTP= | cut -c1-40)"
echo "  logind    : $(grep -h HandlePowerKey $R/etc/systemd/logind.conf.d/99-r36-power.conf)"
echo "  masked    : $(for t in suspend.target hibernate.target sleep.target; do [ -L $R/etc/systemd/system/$t ] && printf "%s->%s " "$t" "$(readlink $R/etc/systemd/system/$t)"; done)"

echo "=== audio / tools / misc ==="
echo "  r36-audio : $(ls $R/etc/systemd/system/multi-user.target.wants/ | grep audio) $(grep -c amixer $R/usr/local/sbin/r36-audio) amixer lines"
echo "  python3   : $(ls $R/usr/bin/python3 >/dev/null 2>&1 && echo present)  fbshot: $(ls $R/usr/local/bin/r36-fbshot >/dev/null 2>&1 && echo present)"
echo "  screen    : $(grep -c 'dev/tty1' $R/usr/local/sbin/r36-status-screen) tty1 writes, $(grep -c chvt $R/usr/local/sbin/r36-status-screen) chvt"
echo "  locale    : $(cat $R/etc/default/locale)"
echo "  resolv    : $(grep -c nameserver $R/etc/resolv.conf) servers"
echo "  build-info: $(cat $R/etc/r36max2-build-info)"
echo "  df        : $(df -h $R | tail -1 | awk '{print $2, $3, $4}')"

echo "=== BOOT partition ==="
ls /mnt/v17b | tr '\n' ' '; echo
echo "  boot.ini \${dtb} count: $(grep -c '{dtb}' /mnt/v17b/boot.ini)  size: $(stat -c %s /mnt/v17b/boot.ini)"
umount /mnt/v17b /mnt/v17r; losetup -d "$L"
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v17.img.xz*
echo "=== V17 VERIFY DONE ==="
