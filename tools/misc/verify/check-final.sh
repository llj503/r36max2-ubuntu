#!/bin/bash
R=/root/r36/rootfs
ls -lL "$R/lib/systemd/systemd"
stat -c '%s bytes  %n' "$R/usr/lib/systemd/systemd"
head -c 4 "$R/usr/lib/systemd/systemd" | od -An -c
echo "--- account lines (hashes redacted) ---"
awk -F: '$1=="root"||$1=="ubuntu" {print $1": pwdlen="length($2)" shell="$7}' "$R/etc/shadow"
getent shadow ubuntu >/dev/null 2>&1 || true
grep -E '^(root|ubuntu)' "$R/etc/passwd"
echo "--- sshd config essentials ---"
grep -E '^(PermitRootLogin|PasswordAuthentication|UsePAM|Port)' "$R/etc/ssh/sshd_config" "$R/etc/ssh/sshd_config.d/"*.conf 2>/dev/null
echo "--- wpa network block (secret redacted) ---"
sed -E 's/(passphrase=).*/\1<redacted>/' "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" | grep -vE '^\s*#' | head -20
echo "--- modules-load.d ---"
cat "$R"/etc/modules-load.d/*.conf 2>/dev/null
echo "--- hostname / tz ---"
cat "$R/etc/hostname"; ls -l "$R/etc/localtime" 2>/dev/null | sed 's#.*-> ##'
