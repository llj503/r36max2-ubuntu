# SPDX-License-Identifier: GPL-2.0-or-later
# rootfs-apt: the distro package layer.
#
# Network and root are split to survive every host:
#   * downloads happen in the BUILD-USER session (host apt against the pinned
#     snapshot, resolving the full recursive closure into a private apt root -
#     the host session is the one with working DNS/proxy);
#   * installation happens in a REAL-ROOT session (wsl.exe -u root on WSL2,
#     plain sudo elsewhere): chroot + `dpkg -i`, which updates the dpkg
#     database so the device's own apt keeps working.
# Configure-time maintainer scripts are deliberately not run (policy-rc.d
# blocks services); everything the image actually needs is configured
# explicitly below, and first-boot regeneration happens on the device
# (r36-hostkeys, machine-id).

PKG_NAME="rootfs-apt"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-base"
PKG_LONGDESC="Snapshot-pinned apt layer + r36max2 device config for the image staging tree."
PKG_TOOLCHAIN="manual"

# the exact package set v20 shipped on the device (base from build-rootfs.sh,
# device + dev chains from apply-v19.sh, wayland stack from apply-wayland.sh,
# ES cross-build deps appended)
R36_PKGS="ca-certificates openssh-server sudo wpasupplicant iw iproute2 \
  iputils-ping curl wget vim git htop tmux less procps kmod usbutils tzdata net-tools \
  udev systemd-timesyncd python3 alsa-utils evtest input-utils rfkill libnss-mdns fdisk \
  build-essential pkg-config tree jq rsync unzip file \
  mesa-utils glmark2 libegl1 libgles2 libgbm1 \
  libgbm-dev libegl-dev libgles-dev libdrm-dev \
  weston wayland-protocols libwayland-dev libwayland-bin grim wf-recorder foot wofi kbd cmake \
  libsdl2-dev libfreeimage-dev libavcodec-dev libavformat-dev libswscale-dev \
  libcurl4-openssl-dev libasound2-dev libudev-dev libfreetype-dev libfmt-dev \
  rapidjson-dev libvlc-dev gettext"

make_target() {
  :
}

makeinstall_target() {
  local R="${BUILD}/image/system"
  [ -d "${R}/usr/bin" ] || die "rootfs-apt: image staging tree missing - is rootfs-base built?"

  # --- 1. host side: resolve the closure on the pinned snapshot, download ----
  local aptroot_dir="${BUILD}/.${PKG_NAME}-aptroot"
  rm -rf "${aptroot_dir}"
  mkdir -p "${aptroot_dir}/etc/apt/preferences.d" "${aptroot_dir}/etc/apt/sources.list.d" \
    "${aptroot_dir}/etc/apt/apt.conf.d" "${aptroot_dir}/var/lib/apt/lists/partial" \
    "${aptroot_dir}/var/lib/dpkg" "${aptroot_dir}/var/cache/apt/archives/partial"
  : > "${aptroot_dir}/var/lib/dpkg/status"
  cat > "${aptroot_dir}/etc/apt/sources.list.d/snapshot.sources" <<SRC
Types: deb
URIs: https://${APT_MIRROR_HOST}/ubuntu/${APT_SNAPSHOT}
Suites: resolute resolute-updates resolute-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Architectures: arm64
SRC
  cat > "${aptroot_dir}/etc/apt/apt.conf.d/main" <<CONF
APT::Architecture "arm64";
APT::Architectures:: "arm64";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Retries "3";
Acquire::Languages "none";
Dir::State "${aptroot_dir}/var/lib/apt";
Dir::State::status "${aptroot_dir}/var/lib/dpkg/status";
Dir::Cache "${aptroot_dir}/var/cache/apt";
Dir::Etc "${aptroot_dir}/etc/apt";
CONF

  build_msg "CLR_GET" "GET" "snapshot index (host apt, arm64)" "indent"
  apt-get -c "${aptroot_dir}/etc/apt/apt.conf.d/main" update 2>&1 | tail -3

  build_msg "CLR_GET" "GET" "resolving + downloading distro closure" "indent"
  apt-get -c "${aptroot_dir}/etc/apt/apt.conf.d/main" \
    install --download-only -y --no-install-recommends ${R36_PKGS} 2>&1 | tail -4
  local NDEB=$(ls "${aptroot_dir}/var/cache/apt/archives/"*.deb 2>/dev/null | wc -l)
  [ "${NDEB}" -gt 50 ] || die "rootfs-apt: only ${NDEB} debs downloaded - snapshot resolution failed"

  # --- 2. root side: install into the staging tree ---------------------------
  # root helper: passwordless sudo if available; otherwise WSL2's root session
  # (wsl.exe -u root needs no password and shares this filesystem; NOTE its
  # outbound network is broken under NAT, which is why downloads ran above)
  if command -v wsl.exe >/dev/null 2>&1 && ! sudo -n true 2>/dev/null; then
    SUDO() { wsl.exe -u root -- "$@"; }
  else
    SUDO() { sudo "$@"; }
  fi

  mkdir -p "${R}/debs"
  cp "${aptroot_dir}"/var/cache/apt/archives/*.deb "${R}/debs/"

  # chroot DNS + CA (lent from the host; the real ones arrive with the packages)
  cp -f /etc/resolv.conf "${R}/etc/resolv.conf"
  mkdir -p "${R}/etc/ssl/certs"
  cp -a /etc/ssl/certs/. "${R}/etc/ssl/certs/" 2>/dev/null || true
  # maintainer scripts must not try to talk to systemd in here
  printf '#!/bin/sh\nexit 101\n' > "${R}/usr/sbin/policy-rc.d"
  chmod 755 "${R}/usr/sbin/policy-rc.d"

  SUDO mount --rbind /dev "${R}/dev" 2>/dev/null || true
  SUDO mount -t proc proc "${R}/proc" 2>/dev/null || true

  build_msg "CLR_BUILD" "INSTALL" "${NDEB} debs via chroot dpkg" "indent"
  SUDO chroot "${R}" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    bash -c 'dpkg -i --force-confdef --force-confold /debs/*.deb' 2>&1 | tail -6

  # dpkg manifest - ships in the image and in distributions/ with the release
  mkdir -p "${R}/etc/r36max2"
  SUDO chroot "${R}" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' \
    > "${R}/etc/r36max2/dpkg-manifest.txt"

  SUDO umount "${R}/proc" 2>/dev/null || SUDO umount -l "${R}/proc" 2>/dev/null || true
  SUDO umount -R "${R}/dev" 2>/dev/null || SUDO umount -l "${R}/dev" 2>/dev/null || true
  # never walk a still-mounted proc/dev (live PIDs -> chown dies); the mountpoint
  # dirs must be empty before anything chowns the tree
  while SUDO mountpoint -q "${R}/proc" 2>/dev/null; do sleep 1; done
  rm -rf "${R}/debs"
  # dpkg ran as root; hand the tree back to the build user for the config
  # steps below (everything is chowned back to root at the very end)
  SUDO chown -R "$(id -u):$(id -g)" "${R}" 2>/dev/null || true

  # --- device config (all verified on hardware, see documentation/) ----------
  echo "r36max2" > "${R}/etc/hostname"
  ln -sf /usr/share/zoneinfo/Asia/Shanghai "${R}/etc/localtime"
  echo "Asia/Shanghai" > "${R}/etc/timezone"

  SUDO chroot "${R}" /bin/sh -c "
    groupadd -f netdev;
    echo 'root:ubuntu' | chpasswd;
    useradd -m -s /bin/bash ubuntu 2>/dev/null || true;
    echo 'ubuntu:ubuntu' | chpasswd;
    usermod -aG sudo,netdev ubuntu;
    mkdir -p /etc/ssh/sshd_config.d;
  "
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    > "${R}/etc/ssh/sshd_config.d/99-r36.conf"

  mkdir -p "${R}/etc/wpa_supplicant" "${R}/etc/systemd/network"
  # no credentials in the image: BOOT:\wifi.txt is the only input channel
  # (this board has no keyboard, no UART, no host-mode USB)
  cat > "${R}/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" <<'WPAS'
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=CN

# No network baked into this image.  Put a two-line file named wifi.txt on the
# BOOT (FAT) partition from Windows:
#     SSID=your-network-name
#     PSK=your-passphrase
# and r36-wifi-setup will install it within a minute.  Results come back as
# wifi-status.txt on the same partition.  2.4GHz + WPA2 only (see HARDWARE.md).
WPAS
  chmod 600 "${R}/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"

  cat > "${R}/etc/systemd/network/80-wlan0.network" <<'NET'
[Match]
Name=wlan0
[Network]
DHCP=yes
DNS=223.5.5.5
[DHCP]
RouteMetric=10
NET
  cat > "${R}/etc/systemd/network/85-usb0.network" <<'NET'
[Match]
Name=usb0
[Network]
Address=192.168.7.2/24
Gateway=192.168.7.1
NET

  # autostart modules (joypad + AIC WiFi); the .ko files land via the
  # linux/rocknix-joypad/aic8800 packages
  mkdir -p "${R}/etc/modules-load.d"
  { echo "rocknix_singleadc_joypad"; echo "aic_load_fw"; echo "aic8800_fdrv"; } \
    > "${R}/etc/modules-load.d/r36max2.conf"

  # timesyncd: name a real NTP server by IP as well (from apply-v19.sh)
  mkdir -p "${R}/etc/systemd/timesyncd.conf.d"
  cat > "${R}/etc/systemd/timesyncd.conf.d/r36.conf" <<'EOS'
[Time]
NTP=203.107.6.88 ntp.aliyun.com cn.pool.ntp.org
EOS
  printf 'LANG=C.UTF-8\n' > "${R}/etc/default/locale"

  # --- enable / mask set (apply-v19.sh section 5, carried over) --------------
  local W="${R}/etc/systemd/system"
  mkdir -p "${W}/multi-user.target.wants" "${W}/sysinit.target.wants" \
           "${W}/sockets.target.wants" "${W}/timers.target.wants"
  ln -sf /etc/systemd/system/r36-wpa@.service          "${W}/multi-user.target.wants/r36-wpa@wlan0.service"
  ln -sf /etc/systemd/system/r36-wifi-setup.service    "${W}/multi-user.target.wants/r36-wifi-setup.service"
  ln -sf /etc/systemd/system/r36-wifi-setup.timer      "${W}/timers.target.wants/r36-wifi-setup.timer"
  ln -sf /etc/systemd/system/r36-audio.service         "${W}/multi-user.target.wants/r36-audio.service"
  ln -sf /lib/systemd/system/systemd-timesyncd.service "${W}/multi-user.target.wants/systemd-timesyncd.service"
  ln -sf /lib/systemd/system/ssh.service               "${W}/multi-user.target.wants/ssh.service"
  ln -sf /lib/systemd/system/ssh.socket                "${W}/sockets.target.wants/ssh.socket"
  for u in systemd-udevd.service systemd-udev-trigger.service; do
    [ -e "${R}/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "${W}/sysinit.target.wants/$u"
  done
  for u in systemd-udevd-control.socket systemd-udevd-kernel.socket; do
    [ -e "${R}/usr/lib/systemd/system/$u" ] && ln -sf "/usr/lib/systemd/system/$u" "${W}/sockets.target.wants/$u"
  done
  # Ubuntu's own wpa_supplicant units would fight r36-wpa@wlan0 for the same
  # nl80211 socket; masking is stronger than removing the alias
  for u in wpa_supplicant-nl80211@.service wpa_supplicant-wired@.service wpa_supplicant.service; do
    ln -sf /dev/null "${W}/$u"
  done
  # suspend enters but nothing wakes this board yet -> keep it masked
  for t in suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target; do
    ln -sf /dev/null "${W}/$t"
  done

  # --- re-mirror the multiarch sysroot (headers/libs arrived with the apt
  # layer: SDL2/mesa/drm -dev etc.) so cross builds (gpu-demos, emulationstation)
  # link against exactly what the image ships
  local SR="${SYSROOT_PREFIX}"
  rm -rf "${SR}/usr/include" "${SR}/usr/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"
  cp -a "${R}/usr/include" "${SR}/usr/include"
  [ -d "${R}/usr/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/usr/lib/aarch64-linux-gnu" "${SR}/usr/lib/aarch64-linux-gnu"
  [ -d "${R}/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"

  # runtime resolver: public DNS only (policy change vs v20, see header)
  printf 'nameserver 223.5.5.5\n' > "${R}/etc/resolv.conf"

  # --- machine-id: an empty file makes systemd mint a fresh one on first boot;
  # a shared one would make two identical boards look like the same host (DUID)
  : > "${R}/etc/machine-id"
  rm -f "${R}/var/lib/dbus/machine-id"
  rm -f "${R}/usr/sbin/policy-rc.d"

  # the image must be root-owned end to end (v20 built everything as root)
  SUDO chown -R root:root "${R}"
}
