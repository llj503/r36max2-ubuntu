#!/bin/bash
R=/root/r36/rootfs
echo "### enabled in multi-user.target.wants"
ls "$R/etc/systemd/system/multi-user.target.wants/"
echo "### wpa units shipped by the package"
ls "$R/lib/systemd/system/" | grep -i wpa
for u in wpa_supplicant@.service wpa_supplicant-nl80211@.service wpa_supplicant.service; do
  echo "### $u"
  cat "$R/lib/systemd/system/$u" 2>/dev/null || echo "(absent)"
done
echo "### network units"
ls "$R/lib/systemd/system/" | grep -E 'networkd|systemd-network'
echo "### sshd enabled?"
ls -l "$R/etc/systemd/system/"multi-user.target.wants/ssh.service 2>/dev/null || echo "ssh.service NOT in multi-user.wants"
echo "### resolved / dns"
ls -l "$R/etc/resolv.conf"
echo "### machine-id"
cat "$R/etc/machine-id"
