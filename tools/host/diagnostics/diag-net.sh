#!/bin/bash
# Diagnose DNS/proxy situation for the chroot and pick a working resolver + mirror.
set -u
echo "=== WSL host resolv.conf ==="
cat /etc/resolv.conf
echo "=== host DNS test (systemd-resolved stub vs public) ==="
getent hosts mirrors.aliyun.com >/dev/null 2>&1 && echo "host getent: OK" || echo "host getent: FAIL"
for ns in 127.0.0.53 223.5.5.5 192.168.31.1 8.8.8.8; do
  printf "%-14s " "$ns"
  timeout 6 python3 - "$ns" <<'PY' 2>/dev/null || echo "unreachable"
import socket,struct,sys,random
ns=sys.argv[1]
qid=random.randint(0,65535)
name=b"mirrors.aliyun.com"
pkt=struct.pack(">HHHHHH",qid,0x0100,1,0,0,0)+b"".join(bytes([len(l)])+l.encode() for l in name.split(b"."))+b"\x00"+struct.pack(">HH",1,1)
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(4)
s.sendto(pkt,(ns,53))
d,_=s.recvfrom(512)
print("resolves")
PY
done
echo "=== direct http fetch from host ==="
curl -sS -m 20 -o /dev/null -w "aliyun http=%{http_code}\n" http://mirrors.aliyun.com/ubuntu-ports/dists/resolute/InRelease
curl -sS -m 20 -o /dev/null -w "ports.ubuntu.com http=%{http_code}\n" http://ports.ubuntu.com/ubuntu-ports/dists/resolute/InRelease
echo "=== env proxies ==="
env | grep -i proxy || echo "(none)"
echo "=== chroot DNS test ==="
printf 'nameserver 223.5.5.5\n' > /root/r36/rootfs/etc/resolv.conf
chroot /root/r36/rootfs /bin/sh -c 'getent hosts mirrors.aliyun.com || echo "chroot getent FAIL"' 2>&1 | tail -2
