#!/bin/bash
# Build the Ubuntu 26.04 rootfs for the R36 Max 2 (v2: http mirror, mkdir -p, module metadata).
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ROOT=/root/r36/rootfs
OUT=/root/r36/out
KDIR=/root/r36/linux-6.12.79
KVER=$(cat /root/r36/kversion 2>/dev/null || echo 6.12.79)
TARBALL=$REPO/downloads/ubuntu-base-26.04.1-base-arm64.tar.gz
CRED=$REPO/build/wifi-cred.txt
# R36_BAKE_WIFI=0 builds an image with NO credentials in it - that is the mode
# to use before handing the image to somebody else; they then drop wifi.txt on
# the BOOT partition (see r36-wifi-setup).  Default keeps the builder's own
# network baked in so reflashing during development stays friction-free.
BAKE_WIFI=${R36_BAKE_WIFI:-1}
if [ "$BAKE_WIFI" = "1" ] && [ -f "$CRED" ]; then
    SSID=$(grep '^Name=' "$CRED" | cut -d= -f2- | tr -d '\r')
    PSK=$(grep '^Passphrase=' "$CRED" | cut -d= -f2- | tr -d '\r')
else
    SSID=""; PSK=""
fi
echo "target SSID: ${SSID:-<none, BOOT:\wifi.txt will be used>}   kernel: $KVER"

if [ ! -d "$ROOT/lib" ]; then
  echo "=== extracting ubuntu-base ==="
  mkdir -p "$ROOT"
  tar -xvpPf "$TARBALL" -C "$ROOT" >/dev/null 2>&1 || { echo "FATAL: extract failed"; exit 1; }
fi

echo "=== apt sources (http, aliyun ubuntu-ports) ==="
mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/apt.conf.d"
rm -f "$ROOT/etc/apt/sources.list"
cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<'SRC'
Types: deb
URIs: http://mirrors.aliyun.com/ubuntu-ports/
Suites: resolute resolute-updates resolute-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SRC
printf 'APT::Install-Recommends "false";\nAPT::Install-Suggests "false";\nAcquire::Retries "3";\n' > "$ROOT/etc/apt/apt.conf.d/99lean"
mkdir -p "$ROOT/etc"
# ubuntu-base ships /etc/resolv.conf as an ABSOLUTE symlink into /run (systemd-resolved stub),
# which does not exist inside a chroot -> must replace it with a real file.
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
echo "build-time resolver: $WSLNS"
rm -f "$ROOT/etc/resolv.conf"
printf 'nameserver %s\n' "$WSLNS" > "$ROOT/etc/resolv.conf"

echo "=== mounts ==="
mount -t proc proc "$ROOT/proc" 2>/dev/null
mount -t sysfs sys "$ROOT/sys" 2>/dev/null
mount --rbind /dev "$ROOT/dev" 2>/dev/null
mount -t devpts devpts "$ROOT/dev/pts" 2>/dev/null
rm -f "$ROOT/etc/hostname"

echo "=== apt update ==="
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tail -6

echo "=== install packages ==="
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
    ca-certificates openssh-server sudo wpasupplicant iw \
    iproute2 iputils-ping curl wget vim git htop tmux less procps \
    kmod usbutils tzdata net-tools 2>&1 | tail -8

echo "=== verify installs ==="
for b in sshd wpa_supplicant ip apt-get depmod; do
  printf "%-16s " "$b"; chroot "$ROOT" /bin/sh -c "command -v $b || ls /usr/sbin/$b 2>/dev/null" || echo MISSING
done

echo "=== kernel modules ==="
# Which .ko belongs to which kernel cannot be answered by a filename or an mtime:
# the joypad source tree and the AIC tree have each been built against both 6.12
# and 7.2 in this project, and a module built for the wrong kernel boots into
# "no WiFi / no buttons" with nothing but one line in dmesg.  So: pick the source
# by kernel, then assert vermagic before it is allowed into the image.
#   6.12.79 -> legacy integer-GPIO joypad driver (hardware-verified since v11)
#   7.2.8   -> the gpiod conversion in artifacts/joypad (needs the polarity flags
#              in projects/r36max2/dt/rk3326-xifan-r36max2.dts; see projects/r36max2/patches/joypad-gpiod.patch)
mkdir -p "$ROOT/lib/modules"
rm -rf "$ROOT/lib/modules/$KVER"
cp -a "$OUT/lib/modules/$KVER" "$ROOT/lib/modules/"
# modules_install leaves build/source symlinks into the multi-GB kernel tree;
# shipping them means a dangling symlink on every card (and anything copying with
# -r follows them and dumps the source tree into the image)
rm -f "$ROOT/lib/modules/$KVER/build" "$ROOT/lib/modules/$KVER/source"
mkdir -p "$ROOT/lib/modules/$KVER/extra"
cp -v "$KDIR/modules.order" "$KDIR/modules.builtin" "$KDIR/modules.builtin.modinfo" "$ROOT/lib/modules/$KVER/" 2>/dev/null

case "$KVER" in
  6.12.79) JPDIR=/root/r36/joypad/src;              JPSFX="" ;;
  *)       JPDIR=$REPO/artifacts/joypad;    JPSFX="-$KVER" ;;
esac
for m in rocknix-singleadc-joypad rocknix-joypad; do
  src="$JPDIR/$m$JPSFX.ko"
  [ -e "$src" ] || { echo "!! missing $src"; exit 1; }
  v=$(modinfo -F vermagic "$src" | awk '{print $1}')
  [ "$v" = "$KVER" ] || { echo "!! $src is vermagic $v, not $KVER"; exit 1; }
  cp -v "$src" "$ROOT/lib/modules/$KVER/extra/$m.ko"
done
cp -v "$KDIR/net/wireless/cfg80211.ko" "$ROOT/lib/modules/$KVER/kernel/net/wireless/" 2>/dev/null
# the radxa-pkg AIC tree, rebuilt for THIS kernel (7.2 needs
# projects/r36max2/patches/aic8800-7.2.8-compat.patch applied with: patch -p1 -d drivers -i ...)
AICDIR=${AIC_STAGED:-$REPO/artifacts/aic72}
for m in aic8800_fdrv aic_load_fw; do
  src=""
  for cand in "$AICDIR/$m-$KVER.ko" "$KDIR/../$m.ko"; do
    [ -e "$cand" ] && src="$cand" && break
  done
  [ -n "$src" ] || { echo "!! no $m.ko staged for $KVER (build it first: v20-aic72b.sh)"; exit 1; }
  v=$(modinfo -F vermagic "$src" | awk '{print $1}')
  [ "$v" = "$KVER" ] || { echo "!! $src is vermagic $v, not $KVER"; exit 1; }
  cp -v "$src" "$ROOT/lib/modules/$KVER/extra/$m.ko"
done
chroot "$ROOT" /usr/bin/env depmod -a "$KVER" && echo "depmod ok"
for m in rocknix_singleadc_joypad aic8800_fdrv; do
  echo "  modprobe -n $m: $(chroot "$ROOT" /usr/bin/env modprobe -n -S "$KVER" "$m" 2>&1 || echo OK)"
done

echo "=== firmware ==="
mkdir -p "$ROOT/lib/firmware"
cp -rf "$OUT/firmware/aic8800DC" "$ROOT/lib/firmware/" && echo "aic8800DC firmware installed"

echo "=== autostart modules ==="
mkdir -p "$ROOT/etc/modules-load.d"
{ echo "rocknix_singleadc_joypad"; echo "aic_load_fw"; echo "aic8800_fdrv"; } > "$ROOT/etc/modules-load.d/r36max2.conf"

echo "=== network config ==="
mkdir -p "$ROOT/etc/wpa_supplicant" "$ROOT/etc/systemd/network"
if [ -n "$SSID" ]; then
cat > "$ROOT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" <<WPAS
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=CN

network={
    ssid="$SSID"
    psk="$PSK"
    priority=1
}
WPAS
else
cat > "$ROOT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" <<WPAS
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=CN

# No network baked into this image.  Put a two-line file named wifi.txt on the
# BOOT (FAT) partition from Windows:
#     SSID=your-network-name
#     PSK=your-passphrase
# and r36-wifi-setup will install it within a minute - the device has no
# keyboard and no serial port, so that file is the input channel.
WPAS
fi
chmod 600 "$ROOT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"

cat > "$ROOT/etc/systemd/network/80-wlan0.network" <<'NET'
[Match]
Name=wlan0
[Network]
DHCP=yes
# 223.5.5.5 works on any network; the router's own DNS still arrives via DHCP
# (UseDNS=yes is the default), so do NOT hardcode a LAN address here - it would
# be a dead first server for anybody else.
DNS=223.5.5.5
[DHCP]
RouteMetric=10
NET
cat > "$ROOT/etc/systemd/network/85-usb0.network" <<'NET'
[Match]
Name=usb0
[Network]
Address=192.168.7.2/24
Gateway=192.168.7.1
NET

echo "=== users, hostname, timezone, ssh ==="
echo "r36max2" > "$ROOT/etc/hostname"
ln -sf /usr/share/zoneinfo/Asia/Shanghai "$ROOT/etc/localtime"
echo "Asia/Shanghai" > "$ROOT/etc/timezone"
chroot "$ROOT" /bin/sh -c "
  groupadd -f netdev;
  echo 'root:ubuntu' | chpasswd;
  useradd -m -s /bin/bash ubuntu 2>/dev/null || true;
  echo 'ubuntu:ubuntu' | chpasswd;
  usermod -aG sudo,netdev ubuntu;
  mkdir -p /etc/ssh/sshd_config.d;
"
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > "$ROOT/etc/ssh/sshd_config.d/99-r36.conf"

echo "=== enable services ==="
chroot "$ROOT" /bin/sh -c '
  systemctl enable ssh.service ssh.socket 2>&1 | tail -2;
  systemctl enable systemd-networkd.service 2>&1 | tail -1;
  systemctl enable wpa_supplicant@wlan0.service 2>&1 | tail -1;
  systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null;
  systemctl mask systemd-pstore.service 2>/dev/null;
  true'
chroot "$ROOT" /bin/sh -c 'apt-get clean'

echo "=== runtime resolv.conf (device-side DNS, not WSL's) ==="
printf 'nameserver 192.168.31.1\nnameserver 223.5.5.5\n' > "$ROOT/etc/resolv.conf"

echo "=== unmount ==="
umount -R "$ROOT/dev" 2>/dev/null
umount "$ROOT/proc" 2>/dev/null
umount "$ROOT/sys" 2>/dev/null

echo "=== result ==="
du -sh "$ROOT"
ls "$ROOT/lib/modules/$KVER/extra/"
echo "=== ROOTFS BUILD DONE ==="
