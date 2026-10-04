#!/bin/bash
# verify-v19.sh - check the staging rootfs and the packed image really contain
# everything this session added, before telling the user v19 is done.
set -uo pipefail
R=/root/r36/rootfs
O=/root/r36/out
IMG=/mnt/e/ubuntu/out/r36max2-ubuntu-v19.img.xz

echo "=== image ==="
ls -l "$IMG"
sha256sum "$IMG"
xz -t "$IMG" && echo "  xz integrity: OK"

echo "=== GPU demo shipped in the rootfs ==="
ls -l "$R/usr/local/bin/r36-gles2-demo" "$R/usr/local/bin/egl-probe" "$R/usr/local/bin/r36-glcheck" 2>&1
ls -l "$R/usr/local/share/r36-gpu/" 2>&1
file "$R/usr/local/bin/r36-gles2-demo" 2>/dev/null | sed 's/^/  /'

echo "=== dev chain present ==="
for b in usr/bin/gcc usr/bin/make usr/bin/pkg-config usr/bin/eglinfo usr/bin/glmark2 usr/bin/amixer usr/bin/evtest usr/bin/python3 usr/bin/git usr/bin/rsync usr/sbin/sshd; do
  printf '  %-22s %s\n' "$(basename $b)" "$([ -e "$R/$b" ] && echo yes || echo MISSING)"
done
printf '  %-22s %s\n' "gbm.h" "$([ -e "$R/usr/include/gbm.h" ] && echo yes || echo MISSING)"
printf '  %-22s %s\n' "EGL/egl.h" "$([ -e "$R/usr/include/EGL/egl.h" ] && echo yes || echo MISSING)"
printf '  %-22s %s\n' "GLES2/gl2.h" "$([ -e "$R/usr/include/GLES2/gl2.h" ] && echo yes || echo MISSING)"
printf '  %-22s %s\n' "xf86drmMode.h" "$([ -e "$R/usr/include/xf86drmMode.h" ] && echo yes || echo MISSING)"

echo "=== things that must NOT be in the image ==="
echo "  policy-rc.d      : $([ -e "$R/usr/sbin/policy-rc.d" ] && echo 'STILL THERE (bad)' || echo removed)"
echo "  resolv.conf      : $(grep '^nameserver' "$R/etc/resolv.conf" | tr '\n' ' ')"
echo "  apt lists left   : $(du -sk "$R/var/lib/apt/lists" 2>/dev/null | cut -f1) KiB"
echo "  wpa creds file   : $(grep -c psk "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" 2>/dev/null || echo 0) line(s) [expected: 1, private 600]"
ls -l "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" 2>/dev/null | awk '{print "  perms           :", $1}'

echo "=== units / masks ==="
W="$R/etc/systemd/system"
ls "$W/multi-user.target.wants/" 2>/dev/null | tr '\n' ' '; echo
ls "$W/timers.target.wants/" 2>/dev/null | sed 's/^/  timer: /'
for t in suspend.target hibernate.target sleep.target; do
  printf '  %-22s %s\n' "$t" "$([ -L "$W/$t" ] && echo masked || echo NOT-masked)"
done
grep -E '^HandlePowerKey' "$R/etc/systemd/logind.conf.d/99-r36-power.conf" | sed 's/^/  /'

echo "=== portable-for-other-networks checks ==="
echo "  machine-id size : $(wc -c < "$R/etc/machine-id") bytes (0 = regenerated on first boot)"
echo "  dbus machine-id : $([ -e "$R/var/lib/dbus/machine-id" ] && echo present || echo absent)"
echo "  resolv order    : $(grep '^nameserver' "$R/etc/resolv.conf" | tr '\n' ' ')"
echo "  wlan0.network   : $(grep -E '^DNS=' "$R/etc/systemd/network/80-wlan0.network" | tr '\n' ' ')"
echo "  wifi.txt units  : $(ls "$W"/r36-wifi-setup.* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
echo "  wifi-setup deps : $(chroot "$R" /bin/sh -c 'for t in wpa_passphrase findfs blkid iw md5sum mountpoint; do command -v $t >/dev/null 2>&1 && printf "%s " $t; done')"

echo "=== staged boot files ==="
ls -l "$O/boot/" | awk '{print "  ", $5, $9}' | tail -6
echo "  dtb opp 200MHz voltage: $(dtc -I dtb -O dts "$O/boot/rk3326-xifan-r36max2.dtb" 2>/dev/null | awk '/opp-table-gpu \{/{f=1} f&&/opp-microvolt/{print $3; exit}')"
echo "  (boot.ini lives inside the FAT partition of the image; pack-v10.sh asserts the literal dtb name)"
du -sh "$R" | sed 's/^/rootfs: /'
