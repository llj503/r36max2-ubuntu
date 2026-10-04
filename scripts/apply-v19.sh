#!/bin/bash
# apply-v19.sh - fold everything verified live on the r36max2 (GPU session)
# back into the staging rootfs, so V=v19 reproduces the running card.
#
# v17 already brought in udev/timesyncd/python3/alsa; v18 shipped the audio
# wait-loop.  What was still ONLY on the device was the whole build/dev chain
# and the two GPU demo programs, so this script adds those plus a Makefile and
# a one-shot r36-glcheck.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
GL=/mnt/e/ubuntu/artifacts/gl
K=/root/r36/linux-6.12.79
RDIR=$K/arch/arm64/boot/dts/rockchip
OUT=/root/r36/out
KVER=6.12.79
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

# keep the exact set used on the device (from /var/log/apt/history.log)
PKGS_BASE="udev systemd-timesyncd python3 alsa-utils evtest input-utils rfkill libnss-mdns fdisk"
PKGS_DEV="build-essential pkg-config git vim curl wget htop tmux tree jq rsync unzip file \
          mesa-utils glmark2 libegl1 libgles2 libgbm1 \
          libgbm-dev libegl-dev libgles-dev libdrm-dev"

echo "=== 1. staged kernel + dtb (GPU opp table must be in the copy we pack) ==="
cp -f "$RDIR/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
cp -f "$RDIR/rk3326-xifan-r36max2-usbhost.dtb" "$OUT/boot/"
echo "  200MHz opp voltage in the staged dtb: $(dtc -I dtb -O dts "$OUT/boot/rk3326-xifan-r36max2.dtb" 2>/dev/null | awk '/opp-table-gpu \{/{f=1} f&&/opp-microvolt/{print $3; exit}')"

echo "=== 2. packages ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
# postinst must not try to talk to systemd in here
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 755 "$R/usr/sbin/policy-rc.d"
chroot "$R" /usr/bin/env apt-get update -qq >/dev/null 2>&1 || echo "  (apt update noisy)"
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install $PKGS_BASE 2>&1 | tail -2
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install $PKGS_DEV  2>&1 | tail -2
echo "  gcc      : $(chroot "$R" /usr/bin/env gcc --version 2>/dev/null | head -1)"
for b in gcc make pkg-config amixer evtest eglinfo glmark2-es2 python3 sshd; do
  printf '  %-11s: %s\n' "$b" "$(ls "$R/usr/bin/$b" "$R/usr/sbin/$b" 2>/dev/null | head -1 || echo MISSING)"
done
echo "  gbm/egl headers: $(ls "$R/usr/include/gbm.h" "$R/usr/include/EGL/egl.h" >/dev/null 2>&1 && echo present)"

echo "=== 3. GPU demo: ship the binary AND the source with a Makefile ==="
install -m 755 "$GL/r36-gles2-demo" "$R/usr/local/bin/r36-gles2-demo"
install -m 755 "$GL/egl-probe"      "$R/usr/local/bin/egl-probe"
mkdir -p "$R/usr/local/share/r36-gpu"
install -m 644 "$GL/r36-gles2-demo.c" "$GL/egl-probe.c" "$R/usr/local/share/r36-gpu/"
cat > "$R/usr/local/share/r36-gpu/Makefile" <<'EMK'
# make && sudo cp ./r36-gles2-demo ./egl-probe /usr/local/bin/
CFLAGS = -O2 -Wall
LIBS   = $(shell pkg-config --cflags --libs gbm egl glesv2 libdrm) -ldrm
all: r36-gles2-demo egl-probe
r36-gles2-demo: r36-gles2-demo.c
	gcc $(CFLAGS) -o $@ $< $(LIBS)
egl-probe: egl-probe.c
	gcc $(CFLAGS) -o $@ $< $(LIBS)
clean:
	rm -f r36-gles2-demo egl-probe
EMK
cat > "$R/usr/local/bin/r36-glcheck" <<'EGC'
#!/bin/sh
# r36-glcheck - one-shot proof that kernel panfrost + Mesa + GBM + EGL work.
#   r36-glcheck          : 6 s of animated shader scanned out to the panel
#   r36-glcheck fbo      : offscreen throughput (light shader)
#   r36-glcheck heavy    : offscreen throughput (48-iteration fragment shader)
# It never touches the console for longer than the run: the demo restores the
# CRTC to the framebuffer it found.
case "${1:-scanout}" in
  scanout) R36_HOLD=6 r36-gles2-demo /dev/dri/card0 6 ;;
  fbo)     R36_FBO=1  r36-gles2-demo /dev/dri/card0 5 ;;
  heavy)   R36_FBO=1 R36_HEAVY=1 r36-gles2-demo /dev/dri/card0 5 ;;
  probe)   egl-probe /dev/dri/card0 ;;
  *) echo "usage: r36-glcheck [scanout|fbo|heavy|probe]" ; exit 2 ;;
esac
echo "gpu freq now: $(cat /sys/class/devfreq/ff400000.gpu/cur_freq 2>/dev/null) Hz"
EGC
chmod 755 "$R/usr/local/bin/r36-glcheck"

echo "=== 4. scripts and units (the Windows-side copies are the source of truth) ==="
cp -f "$SRC/r36-status-screen" "$R/usr/local/sbin/r36-status-screen"
cp -f "$SRC/r36-bootlog"       "$R/usr/local/sbin/r36-bootlog"
cp -f "$SRC/r36-fbshot.py"     "$R/usr/local/bin/r36-fbshot" 2>/dev/null || true
chmod 755 "$R/usr/local/sbin/r36-status-screen" "$R/usr/local/sbin/r36-bootlog"
cp -f "$SRC/r36-wpa@.service"  "$R/etc/systemd/system/"
# WiFi from the BOOT partition: this board has no keyboard and no UART, so a
# text file on the FAT partition is the only way somebody else can tell the
# image which network to join.  Runs at boot and every 60 s afterwards.
cp -f "$SRC/r36-wifi-setup" "$R/usr/local/sbin/r36-wifi-setup"
chmod 755 "$R/usr/local/sbin/r36-wifi-setup"
cp -f "$SRC/r36-wifi-setup.service" "$SRC/r36-wifi-setup.timer" "$R/etc/systemd/system/"
for t in wpa_passphrase findfs blkid iw md5sum mountpoint; do
  chroot "$R" /bin/sh -c "command -v $t >/dev/null 2>&1" \
    || echo "  !! r36-wifi-setup needs $t, not found in the rootfs"
done
mkdir -p "$R/etc/systemd/logind.conf.d"
cp -f "$SRC/99-r36-power.conf" "$R/etc/systemd/logind.conf.d/99-r36-power.conf"
grep -q '^HandlePowerKey=ignore' "$R/etc/systemd/logind.conf.d/99-r36-power.conf" \
  || { echo "!! HandlePowerKey is not ignore - the power key would shut down"; exit 1; }

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
# networkd: drop my router's address from the static DNS list so the image works
# on somebody else's network (DHCP still supplies the local resolver).
cat > "$R/etc/systemd/network/80-wlan0.network" <<'NET'
[Match]
Name=wlan0
[Network]
DHCP=yes
DNS=223.5.5.5
[DHCP]
RouteMetric=10
NET

echo "=== 5. enable / mask ==="
W="$R/etc/systemd/system"
mkdir -p "$W/multi-user.target.wants" "$W/sysinit.target.wants" "$W/sockets.target.wants" "$W/timers.target.wants"
ln -sf /etc/systemd/system/r36-wpa@.service          "$W/multi-user.target.wants/r36-wpa@wlan0.service"
ln -sf /etc/systemd/system/r36-wifi-setup.service    "$W/multi-user.target.wants/r36-wifi-setup.service"
ln -sf /etc/systemd/system/r36-wifi-setup.timer      "$W/timers.target.wants/r36-wifi-setup.timer"
ln -sf /etc/systemd/system/r36-audio.service         "$W/multi-user.target.wants/r36-audio.service"
ln -sf /etc/systemd/system/systemd-timesyncd.service "$W/multi-user.target.wants/systemd-timesyncd.service"
for u in systemd-udevd.service systemd-udev-trigger.service; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$W/sysinit.target.wants/$u"
done
for u in systemd-udevd-control.socket systemd-udevd-kernel.socket; do
  [ -e "$R/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "$W/sockets.target.wants/$u"
done
rm -f "$W/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service" \
      "$W/multi-user.target.wants/wpa_supplicant@wlan0.service"
# Masking is stronger than just removing the alias: NetworkManager/dbus-activated
# wpa_supplicant would otherwise start an instance that fights r36-wpa@wlan0 for
# the same nl80211 socket and steals the association.
for u in wpa_supplicant-nl80211@.service wpa_supplicant-wired@.service wpa_supplicant.service; do
  ln -sf /dev/null "$W/$u"
done
# suspend enters but nothing wakes this board yet -> keep it masked
for t in suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target; do
  ln -sf /dev/null "$W/$t"
done
chmod 644 "$W"/r36-*.service "$W"/r36-*.timer \
          "$R/etc/systemd/logind.conf.d/99-r36-power.conf" 2>/dev/null || true
echo "  wants: $(ls "$W/multi-user.target.wants/" | tr '\n' ' ')"

echo "=== 6. depmod + cleanup ==="
chroot "$R" /usr/bin/env depmod -a "$KVER"
rm -f "$R/usr/sbin/policy-rc.d"
umount -f "$R/proc" 2>/dev/null || true
mount | grep -q "$R" && { echo "!! rootfs still has mounts"; exit 1; }
chroot "$R" /usr/bin/env apt-get clean 2>/dev/null || true
rm -rf "$R"/var/lib/apt/lists/*
# A shared image must not hand every card the same machine-id: networkd's DUID
# and journald's ServerID derive from it, so two identical boards on one LAN
# would look like the same host.  An empty file makes systemd mint a fresh one
# on first boot.
: > "$R/etc/machine-id"
rm -f "$R/var/lib/dbus/machine-id"
# apt needed WSL's resolver; put back something that works on the LAN *and* on
# any other network: the public server has to come first, otherwise a reflash
# on somebody else's network waits for a timeout on my router's address.
printf '# static resolver: public first (works on any network), router second (LAN names)\nnameserver 223.5.5.5\nnameserver 192.168.31.1\n' > "$R/etc/resolv.conf"
echo "  resolv.conf nameservers: $(grep -c '^nameserver' "$R/etc/resolv.conf")"
du -sh "$R" | sed 's/^/  staging rootfs: /'
echo "=== apply-v19 done; next: V=v20 bash /mnt/e/ubuntu/scripts/pack-v20.sh ==="
