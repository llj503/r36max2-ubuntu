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
  wireless-regdb \
  build-essential pkg-config tree jq rsync unzip file \
  mesa-utils glmark2 libegl1 libgles2 libgbm1 \
  libgbm-dev libegl-dev libgles-dev libdrm-dev \
  weston wayland-protocols libwayland-dev libwayland-bin grim wf-recorder foot wofi kbd cmake \
  libsdl2-dev libsdl2-mixer-dev libfreeimage-dev libavcodec-dev libavformat-dev libswscale-dev \
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

  # take the tree back before touching it: a completed run leaves ${R} root-owned on
  # purpose (the image must ship root-owned files - see the chown at the end of this
  # phase), which makes this phase die on its SECOND execution with
  # "mkdir: cannot create directory '.../image/system/debs': Permission denied".
  # It only surfaced now because every earlier run reused rootfs-apt's stamp.
  SUDO chown -R "$(id -u):$(id -g)" "${R}" 2>/dev/null || true

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
  # Make the copy private before anything unmounts it.  `umount -R "${R}/dev"`
  # below would otherwise propagate through the shared peer group and take the
  # HOST's /dev/pts with it - measured: the next `sudo` after "STEP 1 unmounts
  # done" died with "unable to allocate pty: No such device", because Ubuntu's
  # sudoers sets Defaults use_pty and NOPASSWD makes that the only reason to
  # need a pty.  Every later privileged step in the recipe then fails.
  SUDO mount --make-rprivate "${R}/dev" 2>/dev/null || true
  SUDO mount -t proc proc "${R}/proc" 2>/dev/null || true

  # Every chroot below runs arm64 binaries on an x86_64 host.  Without a binfmt
  # handler the dpkg call fails with "Exec format error", the manifest comes back
  # empty, and the image ships a rootfs with no sshd and no wpa_supplicant - on a
  # board with no keyboard, no UART and no USB host that is not recoverable over the
  # network.  Measured 2026-10-04: the rule disappears by itself when an idle WSL
  # VM restarts, so this is checked per run rather than assumed from last time.
  SUDO bash "${ROOT}/scripts/require-arm64.sh" "${R}" ||
    die "rootfs-apt: this host cannot execute arm64 in a chroot (see scripts/require-arm64.sh)"

  build_msg "CLR_BUILD" "INSTALL" "${NDEB} debs via chroot dpkg" "indent"
  SUDO chroot "${R}" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    bash -c 'dpkg -i --force-confdef --force-confold /debs/*.deb' 2>&1 | tail -6

  # dpkg manifest - ships in the image and in distributions/ with the release.
  # The query format must NOT be passed as an argument across the root session:
  # `wsl.exe -u root -- chroot ... dpkg-query -f='...\t...\n'` loses the backslash
  # escapes, and the first real run proved it - 1959 bytes of package names with zero
  # newlines, which the count below rejected.  So the format lives in a script file
  # (heredoc keeps the escapes literal) and the root session runs that file.
  mkdir -p "${R}/etc/r36max2"
  local Q="${BUILD}/.${PKG_NAME}-manifest.sh"
  cat > "${Q}" <<'QEOF'
#!/bin/sh
# $1 = chroot dir, $2 = manifest path; both inside the tree the root session owns
chroot "$1" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' > "$2"
QEOF
  chmod 755 "${Q}"
  SUDO bash "${Q}" "${R}" "${R}/etc/r36max2/dpkg-manifest.txt"
  rm -f "${Q}"

  # Proof the install actually happened, not just that dpkg returned 0: a rootfs
  # without a working sshd cannot be reached, and without wpa_supplicant it cannot
  # join a network, and there is no console on this board to discover that from.
  local npkgs=$(wc -l < "${R}/etc/r36max2/dpkg-manifest.txt")
  [ "${npkgs}" -gt 100 ] || die "rootfs-apt: dpkg manifest has ${npkgs} entries - nothing got installed"
  build_msg "CLR_OK" "VERIFY" "dpkg database: ${npkgs} packages" "indent"
  local absent=""
  for b in sshd wpa_supplicant depmod ip; do
    SUDO chroot "${R}" /bin/sh -c \
      "command -v ${b} >/dev/null 2>&1 || ls /usr/sbin/${b} /usr/bin/${b} >/dev/null 2>&1" \
      || absent="${absent} ${b}"
  done
  [ -n "${absent}" ] && die "rootfs-apt: not executable in the rootfs:${absent}"
  build_msg "CLR_OK" "VERIFY" "sshd, wpa_supplicant, depmod, ip present" "indent"

  SUDO umount "${R}/proc" 2>/dev/null || SUDO umount -l "${R}/proc" 2>/dev/null || true
  SUDO umount -R "${R}/dev" 2>/dev/null || SUDO umount -l "${R}/dev" 2>/dev/null || true
  # never walk a still-mounted proc/dev (live PIDs -> chown dies); the mountpoint
  # dirs must be empty before anything chowns the tree
  while SUDO mountpoint -q "${R}/proc" 2>/dev/null; do sleep 1; done
  build_msg "CLR_OK" "STEP" "1 unmounts done" "indent"
  rm -rf "${R}/debs"
  # dpkg ran as root; hand the tree back to the build user for the config
  # steps below (everything is chowned back to root at the very end)
  SUDO chown -R "$(id -u):$(id -g)" "${R}" 2>/dev/null || true
  build_msg "CLR_OK" "STEP" "2 tree handed back to $(id -un)" "indent"

  # --- device config (all verified on hardware, see documentation/) ----------
  echo "r36max2" > "${R}/etc/hostname" || die "rootfs-apt: cannot write /etc/hostname"
  ln -sf /usr/share/zoneinfo/Asia/Shanghai "${R}/etc/localtime" ||
    die "rootfs-apt: cannot set /etc/localtime"
  echo "Asia/Shanghai" > "${R}/etc/timezone"
  build_msg "CLR_OK" "STEP" "3 hostname/timezone written" "indent"

  # Accounts must be created inside the chroot (useradd needs the target's /etc/passwd
  # and shadow, and the image's own adduser config applies).  Same rule as the manifest
  # above: do not hand a multi-statement quoted string across the root session - the
  # first run of this recipe died on exactly this call, and the log could only name
  # `wsl.exe -u root -- "$@"`, not what broke.  A script file has no quoting to lose.
  local U="${BUILD}/.${PKG_NAME}-accounts.sh"
  cat > "${U}" <<'UEOF'
#!/bin/sh
# $1 = chroot dir
set -e
chroot "$1" /bin/sh -euc '
  groupadd -f netdev
  echo "root:ubuntu" | chpasswd
  useradd -m -s /bin/bash ubuntu || true
  echo "ubuntu:ubuntu" | chpasswd
  usermod -aG sudo,netdev ubuntu
'
UEOF
  chmod 755 "${U}"
  # The binfmt rule can vanish mid-recipe (no systemd here to restore it after a WSL
  # restart), and this is the second phase that execs arm64 binaries out of the tree -
  # measured: dpkg worked, then this call died with Exec format error 6 seconds later.
  SUDO bash "${ROOT}/scripts/require-arm64.sh" "${R}" ||
    die "rootfs-apt: no arm64 handler before the account chroot"
  SUDO bash "${U}" "${R}" 2>&1 | sed 's/^/      /'
  arc=${PIPESTATUS[0]}
  rm -f "${U}"
  [ "${arc}" = 0 ] || die "rootfs-apt: account setup failed inside the chroot (rc=${arc})"
  # The accounts chroot runs as root, so anything it creates inside the tree lands
  # root-owned - and every step after this one writes as the build user.  That is what
  # killed the first two runs here: `mkdir -p /etc/ssh/sshd_config.d` ran inside the
  # chroot, and the `printf ... > .../99-r36.conf` right after it died with Permission
  # denied while the framework could only report `wsl.exe -u root -- "$@"` as the
  # failing command.  Hand the tree back once more, then own the directory ourselves.
  SUDO chown -R "$(id -u):$(id -g)" "${R}" 2>/dev/null || true
  build_msg "CLR_OK" "STEP" "4 accounts created (ubuntu in passwd: $(grep -c '^ubuntu:' "${R}/etc/passwd")), tree back to $(id -un)" "indent"
  # the tree is the build user's again at this point, so the file below is written here
  # rather than inside the chroot; it is chowned to root at the end of this recipe
  mkdir -p "${R}/etc/ssh/sshd_config.d"
  [ -w "${R}/etc/ssh/sshd_config.d" ] ||
    die "rootfs-apt: sshd_config.d not writable by $(id -un) (owner $(stat -c%U "${R}/etc/ssh/sshd_config.d"))"
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    > "${R}/etc/ssh/sshd_config.d/99-r36.conf" ||
    die "rootfs-apt: cannot write the sshd drop-in (owner $(stat -c%U "${R}/etc/ssh/sshd_config.d"))"
  # Ubuntu's openssh-server postinst runs inside this chroot and *generates host
  # keys into the tree*, so an image built from it would give every card the same
  # SSH host identity.  r36-hostkeys.service regenerates them on first boot, and
  # the packing check asserts zero of them survive into the image.
  rm -f "${R}"/etc/ssh/ssh_host_*
  [ -z "$(ls "${R}"/etc/ssh/ssh_host_* 2>/dev/null)" ] ||
    die "rootfs-apt: preseeded SSH host keys are still in the tree"
  build_msg "CLR_OK" "STEP" "5 sshd drop-in written, preseeded host keys removed" "indent"

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
  build_msg "CLR_OK" "STEP" "6 wpa/network/modules-load/timesyncd/locale written" "indent"

  # --- enable / mask set (apply-v19.sh section 5, carried over) --------------
  local W="${R}/etc/systemd/system"
  mkdir -p "${W}/multi-user.target.wants" "${W}/sysinit.target.wants" \
           "${W}/sockets.target.wants" "${W}/timers.target.wants"
  ln -sf /usr/lib/systemd/system/r36-wpa@.service          "${W}/multi-user.target.wants/r36-wpa@wlan0.service"
  # systemd-networkd is what actually runs DHCP for wlan0 (etc/systemd/network/
  # 80-wlan0.network), but nothing in this tree ever enabled it: the router listed
  # the board as associated with 0.0.0.0, and the card reported
  # "systemd-networkd: active=inactive enabled=disabled".  The only thing that ever
  # started it was r36-wifi-setup's "wifi.txt changed" branch, which early-exits on
  # an unchanged file - so on a normal boot no client ever asked for a lease.
  ln -sf /lib/systemd/system/systemd-networkd.service     "${W}/multi-user.target.wants/systemd-networkd.service"
  # only the templated instance is enabled from here - enable_service cannot
  # instantiate a template.  the other r36-* units are enabled by their own
  # packages, and r36-audio.service in particular was a link to a unit nobody
  # ships (the audio package installs audio.service), i.e. a dangling wants
  # symlink on every card and a not-found unit at boot.
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
  build_msg "CLR_OK" "STEP" "7 units enabled/masked (wants: $(ls "${W}/multi-user.target.wants" 2>/dev/null | wc -l) links)" "indent"

  # --- re-mirror the multiarch sysroot (headers/libs arrived with the apt
  # layer: SDL2/mesa/drm -dev etc.) so cross builds (gpu-demos, emulationstation)
  # link against exactly what the image ships
  local SR="${SYSROOT_PREFIX}"
  # ${SR} here is this package's PRIVATE sysroot copy, and it has no lib/ at all until
  # we make one - the first run proved it:
  #   cp: cannot create directory '.../.sysroot/rootfs-apt.target/lib/aarch64-linux-gnu':
  #       No such file or directory
  # rootfs-base does the same mkdir before mirroring; the re-mirror needs it too.
  mkdir -p "${SR}/usr" "${SR}/lib"
  rm -rf "${SR}/usr/include" "${SR}/usr/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"
  cp -a "${R}/usr/include" "${SR}/usr/include" ||
    die "rootfs-apt: cannot re-mirror headers into ${SR}/usr/include"
  [ -d "${R}/usr/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/usr/lib/aarch64-linux-gnu" "${SR}/usr/lib/aarch64-linux-gnu"
  [ -d "${R}/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"
  build_msg "CLR_OK" "STEP" "8 sysroot re-mirrored for cross builds" "indent"

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
