#!/bin/bash
K=/root/r36/linux-6.12.79
echo "=== systemd-25x critical kernel options in our build ==="
for o in MEMCG CGROUP_PIDS CGROUP_BPF BPF_SYSCALL PSI CGROUP_DEVICE FHANDLE EPOLL \
         INOTIFY_USER SIGNALFD TIMERFD EVENTFD SECCOMP SECCOMP_FILTER POSIX_MQUEUE \
         TMPFS_POSIX_ACL TMPFS_XATTR IPV6 NET_INET NETFILTER_ETHERTYPES AUTOFS4_FS \
         AUTOFS_FS PERSISTENT_KEYRINGS KEYS TMPFS_QUOTA_XATTR USER_NS CFS_BANDWIDTH \
         FAIR_GROUP_SCHED CGROUP_SCHED BLK_CGROUP_IOLATENCY LIBFDEVT; do
  line=$(grep -E "^CONFIG_$o=|^# CONFIG_$o is" "$K/.config" | head -1)
  printf "  %-26s %s\n" "$o" "${line:-<absent>}"
done
echo
echo "=== module names as installed (for /etc/modules-load.d) ==="
for m in /root/r36/rootfs/lib/modules/6.12.79/extra/*.ko; do
  printf "  %-34s name=" "$(basename $m)"
  modinfo -F filename "$m" >/dev/null 2>&1 && basename "$m" .ko | tr '-' '_'
done
echo
echo "=== what modules.dep expects for our extras ==="
grep -o "extra/[a-z_-]*\.ko" /root/r36/rootfs/lib/modules/6.12.79/modules.dep | sort -u
echo
echo "=== current modules-load.d content ==="
cat /root/r36/rootfs/etc/modules-load.d/r36max2.conf
