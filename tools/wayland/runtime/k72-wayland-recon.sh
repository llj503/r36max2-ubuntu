#!/bin/bash
# k72-wayland-recon.sh - what does a Wayland session need on this card, and what
# is already there?  Read-only: package availability, seat/logind state, DRM
# nodes, memory/disk headroom, and the two things that decide whether a GUI is
# usable at all on a handheld with no keyboard and no USB host.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s'; }

S <<'EOS'
echo "=== base system ==="
grep -E "^(PRETTY_NAME|VERSION_ID|VERSION_CODENAME)" /etc/os-release | sed "s/^/  /"
echo "  kernel   : $(uname -r)"
echo "  systemd  : $(systemctl --version | head -1)"
echo "  ram      : $(free -m | awk '/^Mem/{print $2" MiB total, "$7" available"}')"
echo "  swap     : $(free -m | awk '/^Swap/{print $2" MiB"}')"
echo "  disk     : $(df -h / | awk 'NR==2{print $4" free on /"}')"
echo
echo "=== display / input stack present today ==="
echo "  dri      : $(ls /dev/dri 2>/dev/null | tr '\n' ' ')"
echo "  fb       : $(ls /dev/fb* 2>/dev/null | tr '\n' ' ')"
echo "  uinput   : $([ -e /dev/uinput ] && echo present || echo ABSENT)  ($(lsmod | grep -c uinput) module)"
echo "  seats    : $(loginctl --no-legend list-seats | tr '\n' ' ')"
loginctl seat-status seat0 2>/dev/null | head -12 | sed "s/^/    /"
echo "  active tty session: $(loginctl --no-legend list-sessions | head -3 | tr -s ' ')"
echo "  getty@tty1: $(systemctl is-active getty@tty1 2>/dev/null)   r36-status: $(systemctl is-active r36-status@tty1 2>/dev/null || systemctl is-enabled r36-status-screen 2>/dev/null)"
echo
echo "=== EGL/GBM libs already installed (the GPU work is the reason this is easy) ==="
for f in /usr/lib/aarch64-linux-gnu/libEGL.so* /usr/lib/aarch64-linux-gnu/libgbm.so*; do
  [ -e "$f" ] && echo "  $(basename $f)"
done | sort -u | head -6
echo "  glcheck: $(command -v r36-glcheck || echo missing)"
echo
echo "=== what apt offers (no installs yet) ==="
apt-get -qq update >/dev/null 2>&1 || echo "  (apt update failed - no network?)"
for p in weston labwc cage sway foot wofi grim slurp wlroots libwlroots3 libwlroots4 \
         wayland-protocols libwayland-bin ydotool wtype i3status dinit; do
  c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  printf "  %-22s %s\n" "$p" "${c:-none}"
done
echo
echo "=== the two blockers for using a GUI without a keyboard ==="
echo "  joypad nodes: $(ls /dev/input/by-path/ 2>/dev/null | grep -c rocknix) rocknix + $(ls /dev/input/ | grep -c event) events"
echo "  usb role    : $(cat /sys/class/power_supply/usb*/type 2>/dev/null | tr '\n' ' ')"
echo "  dwc3/dr_mode: $(for d in /sys/class/extcon/*; do [ -e "$d/state" ] && echo -n "$d: "; done) $(ls /sys/class/typec 2>/dev/null | tr '\n' ' ')"
echo "  bluetooth   : $(hciconfig hci0 2>/dev/null | head -2 | tr '\n' ' ')"
EOS
echo "=== recon done ==="
