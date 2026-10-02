#!/bin/bash
# Why does DNS fail inside the arm64 chroot? Test variants.
set -u
ROOT=/root/r36/rootfs
echo "=== host resolv.conf ==="; cat /etc/resolv.conf
mkdir -p "$ROOT/etc"
echo "=== variant A: plain file with WSL resolver ==="
printf 'nameserver 10.255.255.254\n' > "$ROOT/etc/resolv.conf"
chroot "$ROOT" /bin/sh -c 'cat /etc/resolv.conf; getent hosts mirrors.aliyun.com || echo FAIL'
echo "=== variant B: bind-mount host resolv.conf ==="
umount "$ROOT/etc/resolv.conf" 2>/dev/null
touch "$ROOT/etc/resolv.conf"
mount --bind /etc/resolv.conf "$ROOT/etc/resolv.conf" && \
  chroot "$ROOT" /bin/sh -c 'getent hosts mirrors.aliyun.com || echo FAIL'
echo "=== rootfs resolver config files ==="
ls -la "$ROOT/etc/nsswitch.conf" "$ROOT/etc/hosts" 2>&1 | tail -2
echo "=== variant C: force IPv4 UDP via python-less test (apt with proxy-free http by IP) ==="
umount "$ROOT/etc/resolv.conf" 2>/dev/null
printf 'nameserver 10.255.255.254\noptions timeout:2 attempts:1\n' > "$ROOT/etc/resolv.conf"
chroot "$ROOT" /bin/sh -c 'timeout 25 apt-get update -o Acquire::Retries=0 2>&1 | tail -4'
echo "=== host-side apt-get download test (does host dns work for same url) ==="
timeout 20 curl -sS -o /dev/null -w "host http=%{http_code}\n" http://mirrors.aliyun.com/ubuntu-ports/dists/resolute/InRelease
