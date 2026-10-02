#!/bin/bash
# apply-v17.sh - fold everything that was verified live on the device back into
# the build rootfs, so a reflash reproduces the running system.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
K=/root/r36/linux-6.12.79
RDIR=$K/arch/arm64/boot/dts/rockchip
OUT=/root/r36/out
KVER=6.12.79
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 1. refresh the dtbs into the staging dir (the pack script copies from here) ==="
cp -f "$RDIR/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
cp -f "$RDIR/rk3326-xifan-r36max2-usbhost.dtb" "$OUT/boot/"
ls -la "$OUT/boot" | tail -5
echo "  200MHz opp in the staged dtb: $(dtc -I dtb -O dts "$OUT/boot/rk3326-xifan-r36max2.dtb" 2>/dev/null | awk '/opp-table-gpu \{/{f=1} f&&/opp-microvolt/{print $3; exit}')"

echo "=== 2. packages the live system gained ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
chroot "$R" /usr/bin/env apt-get update -qq >/dev/null 2>&1 || echo "  (apt update noisy)"
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install \
    udev systemd-timesyncd python3 alsa-utils evtest input-utils 2>&1 | tail -3
echo "  udevd      : $(ls "$R/usr/lib/systemd/systemd-udevd" >/dev/null 2>&1 && echo present)"
echo "  timesyncd  : $(ls "$R/usr/lib/systemd/systemd-timesyncd" >/dev/null 2>&1 && echo present)"
echo "  python3    : $(ls "$R/usr/bin/python3" >/dev/null 2>&1 && echo present)"
echo "  alsa       : $(ls "$R/usr/bin/amixer" "$R/usr/bin/speaker-test" >/dev/null 2>&1 && echo present)  evtest: $(ls "$R/usr/bin/evtest" >/dev/null 2>&1 && echo present)"

echo "=== 3. the scripts and units (local copies are the source of truth) ==="
cp -f "$SRC/r36-status-screen" "$R/usr/local/sbin/r36-status-screen"
cp -f "$SRC/r36-bootlog"       "$R/usr/local/sbin/r36-bootlog"
cp -f "$SRC/r36-fbshot.py"     "$R/usr/local/bin/r36-fbshot"
chmod 755 "$R/usr/local/sbin/r36-status-screen" "$R/usr/local/sbin/r36-bootlog" "$R/usr/local/bin/r36-fbshot"
cp -f "$SRC/r36-wpa@.service"  "$R/etc/systemd/system/"
cp -f "$SRC/99-r36-power.conf" "$R/etc/systemd/logind.conf.d/99-r36-power.conf" 2>/dev/null || {
    mkdir -p "$R/etc/systemd/logind.conf.d"; cp -f "$SRC/99-r36-power.conf" "$R/etc/systemd/logind.conf.d/99-r36-power.conf"; }
# the audio defaults unit (Master 230, Internal Speakers on, mux parked on HP)
cat > "$R/usr/local/sbin/r36-audio" <<'EOS'
#!/bin/sh
# r36max2: the rk817 'Master' curve is steep (55% == -42.85 dB, effectively mute)
# and the external amp needs the mux/switch set explicitly.  The sound card only
# shows up after a deferred probe, so wait for it - After=sound.target alone is
# too early and the old script silently did nothing.
for i in $(seq 1 60); do [ -e /proc/asound/card0 ] && break; sleep 1; done
[ -e /proc/asound/card0 ] || { echo "r36-audio: no sound card after 60s"; exit 0; }
amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1
amixer -c 0 sset 'Internal Speakers' on >/dev/null 2>&1
# both mux positions measure audible; the external amp is fed from HPOL/HPOR per
# the DT routing, so park it on HP
for m in SPK HP; do amixer -c 0 sset 'Playback Mux' "$m" >/dev/null 2>&1; done
amixer -c 0 sget 'Master' 2>/dev/null | grep -E 'Front Left:' | sed 's/^/r36-audio: /'
exit 0
EOS
chmod 755 "$R/usr/local/sbin/r36-audio"
cat > "$R/etc/systemd/system/r36-audio.service" <<'EOS'
[Unit]
Description=r36max2 audio defaults (amp mux + usable volume)
After=sound.target multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/r36-audio

[Install]
WantedBy=multi-user.target
EOS
mkdir -p "$R/etc/systemd/timesyncd.conf.d"
cat > "$R/etc/systemd/timesyncd.conf.d/r36.conf" <<'EOS'
# The router resolves ntp.ubuntu.com to a bogus 198.18.x.x, so name a real server
# by IP as well.
[Time]
NTP=203.107.6.88 ntp.aliyun.com cn.pool.ntp.org
FallbackNTP=192.168.31.1
EOS
printf 'LANG=C.UTF-8\n' > "$R/etc/default/locale"

echo "=== 4. enable / mask the right things ==="
W="$R/etc/systemd/system"
mkdir -p "$W/multi-user.target.wants" "$W/sysinit.target.wants" "$W/sockets.target.wants" "$W/timers.target.wants"
ln -sf /etc/systemd/system/r36-wpa@.service            "$W/multi-user.target.wants/r36-wpa@wlan0.service"
ln -sf /etc/systemd/system/r36-audio.service           "$W/multi-user.target.wants/r36-audio.service"
ln -sf /etc/systemd/system/systemd-timesyncd.service   "$W/multi-user.target.wants/systemd-timesyncd.service"
for u in systemd-udevd.service systemd-udev-trigger.service; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$W/sysinit.target.wants/$u"
done
for u in systemd-udevd-control.socket systemd-udevd-kernel.socket; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$W/sockets.target.wants/$u"
done
rm -f "$W/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service" \
      "$W/multi-user.target.wants/wpa_supplicant@wlan0.service"
# suspend sleeps fine but cannot be woken on this board yet -> keep it masked
for t in suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target; do
  ln -sf /dev/null "$W/$t"
done
chmod 644 "$W"/r36-*.service "$W"/r36-*.timer "$W"/99-r36-power.conf "$W"/r36-audio.service 2>/dev/null || true
ls "$W/multi-user.target.wants/" | tr '\n' ' '; echo
ls "$W/" | grep -E 'suspend|hibernate|sleep' | tr '\n' ' '; echo

echo "=== 5. depmod + cleanup ==="
chroot "$R" /usr/bin/env depmod -a "$KVER"
umount -f "$R/proc" 2>/dev/null || true
mount | grep "$R" && { echo "!! rootfs still has mounts"; exit 1; }
chroot "$R" /usr/bin/env apt-get clean 2>/dev/null || true
rm -rf "$R"/var/lib/apt/lists/*
# apt needed WSL's resolver; put back something that exists on the LAN
printf '# static resolver: router + public, does not depend on whatever runs the link\nnameserver 192.168.31.1\nnameserver 223.5.5.5\n' > "$R/etc/resolv.conf"
grep -c nameserver "$R/etc/resolv.conf" | sed 's/^/  resolv.conf nameservers: /'
du -sk "$R" | awk '{printf "rootfs: %.2f GiB\n", $1/1048576}'
echo "=== apply-v17 done; next: V=v17 bash pack-v10.sh ==="
