#!/bin/bash
# register-binfmt-aarch64.sh - turn on the kernel's arm64 binfmt rule using the rule
# the qemu-user-static package ships, instead of typing one by hand.
#
#   bash scripts/register-binfmt-aarch64.sh [rootfs-dir-to-test]
#
# Why this exists: the staging rootfs is arm64 and the build host is x86_64, so every
# chroot in the pipeline (apt/dpkg in rootfs-apt above all) needs binfmt_misc to run
# those binaries.  The rule lives in /proc, which means it disappears whenever the VM
# restarts - an idle WSL instance does exactly that, mid-pipeline.
#
# Do NOT hand-write the rule.  Someone did here and typed the magic as "\x7fELF...";
# bash's printf ate the E as part of the hex escape, the resulting mask matched x86_64
# ELF too, and every host binary (ls, sed, even bash's own execve) got handed to
# qemu-aarch64 and died with "Exec format error" until the VM was rebooted.  So this
# script decodes the packaged rule, prints what it found, refuses unless e_machine is
# 0xb7 AND the mask pins those two bytes, and unregisters again if a host binary stops
# working after the write.
set -u
CONF=/usr/lib/binfmt.d/qemu-aarch64.conf
REG=/proc/sys/fs/binfmt_misc/register
TESTROOT=${1:-}

if [ ! -f "$CONF" ]; then
  echo "!! $CONF not found - install the static emulator handlers:"
  echo "   apt-get install qemu-user-static binfmt-support"
  exit 1
fi

if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] &&
   grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
  echo "  handler already registered and enabled"
else
python3 - "$CONF" "$REG" <<'PY'
import sys, binascii, os
conf, reg = sys.argv[1], sys.argv[2]
parts = [p for p in open(conf).read().strip().split(':')]
if parts and parts[0] == '':
    parts = parts[1:]
name, typ, off, magic, mask, interp, flags = parts[:7]

def unhex(s):
    out, i = bytearray(), 0
    while i < len(s):
        if s[i:i+2] == '\\x':
            out.append(int(s[i+2:i+4], 16)); i += 4
        else:
            out.append(ord(s[i])); i += 1
    return bytes(out)

m, k = unhex(magic), unhex(mask)
print(f"  {name}: interp={interp} flags={flags}")
print(f"  magic={m.hex()} ({len(m)} B)  mask={k.hex()} ({len(k)} B)")
assert len(m) == len(k), "magic and mask must be the same length"
assert m[:4] == b'\x7fELF', "magic does not start with the ELF header"
assert m[18:20] == b'\xb7\x00', f"e_machine is {m[18:20].hex()}, want b700 (aarch64)"
assert k[18:20] == b'\xff\xff', "mask leaves e_machine free - it would hijack host binaries"
assert os.path.exists(interp), f"interpreter {interp} is not installed"
rule = ':{}:{}:{}:{}:{}:{}:{}\n'.format(
    name, typ, off,
    ''.join(f'\\x{b:02x}' for b in m),
    ''.join(f'\\x{b:02x}' for b in k),
    interp, flags)
with open(reg, 'w') as f:
    f.write(rule)
print("  rule written from the packaged definition")
PY
fi

echo "  handler present: $([ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] && echo yes || echo no)"

# the guard that makes a wrong mask survivable: if a host binary stops running, undo
# immediately - otherwise the build box is unusable until the VM restarts.
if ! /usr/bin/true; then
  echo "!! host binaries stopped working - unregistering"
  echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64
  exit 1
fi
echo "  host binaries still fine"

if [ -n "$TESTROOT" ]; then
  echo "  chroot test: $(chroot "$TESTROOT" /bin/sh -c 'uname -m' 2>&1)"
fi
