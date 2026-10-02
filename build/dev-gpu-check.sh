#!/bin/bash
# dev-gpu-check.sh - did the v17 OPP fix actually make panfrost probe?
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=8 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== panfrost ==="
S 'dmesg | grep -iE "panfrost|mali|gpu|devfreq" | tail -14 | sed "s/^/  /"'
echo "=== dri nodes / gl driver ==="
S 'ls -l /dev/dri/ 2>/dev/null | sed "s/^/  /"; echo "  modules: $(lsmod | awk "/panfrost|gpu_sched|drm_kms_helper/{printf \"%s \", \$1}")"'
echo "=== regulators + opp now ==="
S 'grep -E "vdd_logic|vdd_arm" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed "s/^/  /"
   mount -t debugfs none /sys/kernel/debug 2>/dev/null; grep -E "vdd_logic|vdd_arm" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed "s/^/  /"
   echo "  opp files: $(ls /sys/devices/platform/ff400000.gpu/opp 2>/dev/null | wc -l)"
   echo "  gpu cur freq: $(cat /sys/class/devfreq/*gpu/cur_freq 2>/dev/null) / available: $(cat /sys/class/devfreq/*gpu/available_freq 2>/dev/null)"'
echo "=== remaining error-level kernel messages this boot ==="
S 'journalctl -b -p 3 --no-pager -o short-iso 2>/dev/null | tail -12 | sed "s/^/  /"'
echo "=== failed units ==="
S 'systemctl --failed --no-legend --plain | sed "s/^/  /"; echo "  (none if blank)"'
echo "=== services / time / audio ==="
S 'for s in systemd-udevd systemd-networkd r36-wpa@wlan0 systemd-timesyncd r36-audio r36-status-screen ssh avahi-daemon; do printf "  %-22s %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done
   timedatectl | grep -iE "synchronized|NTP service" | sed "s/^/  /"
   echo -n "  mixer: "; amixer -c 0 sget Master 2>/dev/null | grep -m1 Front | sed "s/^/        /"
   echo -n "  mux  : "; amixer -c 0 sget "Playback Mux" 2>/dev/null | grep Item0 | sed "s/^/        /"'
echo "=== wifi + ip ==="
S 'ip -br addr show wlan0 | sed "s/^/  /"; iw dev wlan0 link | head -3 | sed "s/^/  /"; echo -n "  gpu render test: "; ls /dev/dri/renderD* 2>/dev/null || echo "no render node"'
