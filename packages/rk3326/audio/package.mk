# SPDX-License-Identifier: GPL-2.0-or-later
# audio: amp mux + usable volume defaults (rk817 codec + external amp).
# Materialized verbatim from the v20 apply-v19.sh heredocs.

PKG_NAME="audio"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Waits for the deferred-probed sound card, sets amp mux + volume."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  # the rk817 'Master' curve is steep (55% == -42.85 dB, effectively mute) and
  # the external amp needs the mux/switch set explicitly.  The sound card only
  # shows up after a deferred probe, so wait for it - After=sound.target alone
  # is too early and the old script silently did nothing.
  cat > ${INSTALL}/usr/local/sbin/audio <<'EOS'
#!/bin/sh
for i in $(seq 1 60); do [ -e /proc/asound/card0 ] && break; sleep 1; done
[ -e /proc/asound/card0 ] || { echo "audio: no sound card after 60s"; exit 0; }
amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1
amixer -c 0 sset 'Internal Speakers' on >/dev/null 2>&1
# both mux positions measure audible; the external amp is fed from HPOL/HPOR per
# the DT routing, so park it on HP
for m in SPK HP; do amixer -c 0 sset 'Playback Mux' "$m" >/dev/null 2>&1; done
amixer -c 0 sget 'Master' 2>/dev/null | grep -E 'Front Left:' | sed 's/^/audio: /'
exit 0
EOS
  chmod 755 ${INSTALL}/usr/local/sbin/audio

  cat > ${INSTALL}/usr/lib/systemd/system/audio.service <<'EOS'
[Unit]
Description=r36max2 audio defaults (amp mux + usable volume)
After=sound.target multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/audio

[Install]
WantedBy=multi-user.target
EOS
  enable_service audio.service
}
