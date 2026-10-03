#!/bin/bash
# v20-clean-wpa.sh - apply-v19 now masks wpa_supplicant.service, but the image
# still carries a leftover wants-symlink from the v11-era recipe: a unit that is
# both masked and enabled produces a boot-time warning and a failed unit.  Drop
# the wants entry and prove the mask is what is actually in place.
set -uo pipefail
R=/root/r36/rootfs
echo "=== what is in the wants dir pointing at wpa ==="
ls -l "$R/etc/systemd/system/multi-user.target.wants/" | grep -i wpa | sed 's/^/  /'
echo "=== the unit files themselves (mask = symlink to /dev/null) ==="
for u in wpa_supplicant.service wpa_supplicant-nl80211@.service wpa_supplicant-wired@.service; do
  p="$R/etc/systemd/system/$u"
  if [ -L "$p" ]; then echo "  $u -> $(readlink "$p") (masked=$([ "$(readlink "$p")" = "/dev/null" ] && echo yes || echo no))";
  elif [ -e "$p" ]; then echo "  $u = real file"; else echo "  $u absent from /etc/systemd/system"; fi
done

rm -f "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service" \
      "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service" \
      "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant-nl80211@wlan0.service"
echo "  after cleanup, wants: $(ls "$R/etc/systemd/system/multi-user.target.wants/" | tr '\n' ' ')"

echo
echo "=== logind drop-in actually installed with the systemd-known key names? ==="
grep -nE "^Handle|^Idle|^RemoveIPC" "$R/etc/systemd/logind.conf.d/99-r36-power.conf" | sed 's/^/  /'
echo "  keys systemd knows (from the rootfs binary):"
strings -a "$R/lib/systemd/systemd-logind" 2>/dev/null | grep -E "^Handle[A-Za-z]+$" | sort -u | tr '\n' ' ' | sed 's/^/    /'
echo
echo "=== r36-wpa unit + wifi-setup present, credentials absent ==="
ls "$R/etc/systemd/system/" | grep -E "r36-" | sed 's/^/  /'
echo "  wpa conf files: $(ls -l "$R/etc/wpa_supplicant/" 2>/dev/null | awk '{print $1, $5, $9}' | tr '\n' '|')"
echo "  machine-id: $([ -s "$R/etc/machine-id" ] && echo NON-EMPTY || echo empty)"
echo "  resolv.conf: $(grep -c '^nameserver' "$R/etc/resolv.conf") servers: $(grep '^nameserver' "$R/etc/resolv.conf" | tr '\n' ' ')"
echo "  policy-rc.d left behind: $([ -e "$R/usr/sbin/policy-rc.d" ] && echo YES || echo no)"
