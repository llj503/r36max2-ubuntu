#!/bin/bash
K=/root/r36/linux-6.12.79
cd "$K"
echo "=== does the kernel resolve root=UUID= / PARTUUID= at all? ==="
grep -rIn "PARTUUID" init/ block/ 2>/dev/null | head -6
echo "--- name_to_dev_t definition site ---"
grep -rIn "dev_t name_to_dev_t\|name_to_dev_t(const char" init/ block/ fs/ 2>/dev/null | head -4
echo "--- early_lookup_bdev definition site ---"
grep -rIn "early_lookup_bdev" init/ fs/ block/ 2>/dev/null | grep -v "\.o:" | head -6

echo
echo "=== arm64 busybox-static for the initramfs ==="
set -e
if [ ! -f /root/r36/bs/busybox ]; then
  mkdir -p /root/r36/bs && cd /root/r36/bs
  dpkg --add-architecture arm64
  printf 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports resolute main\n' \
    > /etc/apt/sources.list.d/arm64-ports.list
  apt-get update -qq >/dev/null 2>&1 || apt-get update 2>&1 | tail -3
  apt-get download busybox-static:arm64 >/dev/null 2>&1
  ls -la *.deb
  dpkg -x busybox-static_*.deb x
  find x -name busybox -type f -exec cp {} /root/r36/bs/busybox \;
fi
ls -la /root/r36/bs/busybox && file /root/r36/bs/busybox
