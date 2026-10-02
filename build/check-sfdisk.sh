#!/bin/bash
# Compare sfdisk/partx option support between the host and the rootfs copy.
echo "=== host sfdisk ==="
sfdisk --version
sfdisk --help 2>&1 | grep -E -- '--(no-reread|no-telling|nopt|force|lock)' || echo "  none of those options"
echo "=== rootfs sfdisk ==="
chroot /root/r36/rootfs /usr/sbin/sfdisk --version
chroot /root/r36/rootfs /usr/sbin/sfdisk --help 2>&1 | grep -E -- '--(no-reread|no-telling|nopt|force|lock)' || echo "  none"
echo "=== rootfs partx ==="
chroot /root/r36/rootfs /usr/bin/partx --help 2>&1 | grep -E -- '--(nr|output|noheadings)' | head -5
echo "=== rootfs has parted? ==="
chroot /root/r36/rootfs /bin/sh -c "command -v parted || echo 'no parted'"
