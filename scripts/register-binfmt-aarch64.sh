#!/bin/bash
# register-binfmt-aarch64.sh - turn on arm64 binfmt from the rule the qemu-user-static
# package ships, instead of typing one by hand.  The hand-typed version matched x86_64
# ELF too (bash's printf swallowed a hex digit out of "\x7fELF"), which made every host
# binary unrunnable until WSL was restarted; this version decodes with python3, prints
# what it is about to write, refuses if the machine field is not aarch64 (0xb7), and
# unregisters again immediately if a host binary stops working.
exec > /mnt/f/r36-build/binfmt4.log 2>&1
CONF=/usr/lib/binfmt.d/qemu-aarch64.conf
REG=/proc/sys/fs/binfmt_misc/register

if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] &&
   grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
  echo "  handler already registered and enabled - nothing to do"
  exit 0
fi

python3 - "$CONF" "$REG" <<'PY'
import sys, binascii, os
conf, reg = sys.argv[1], sys.argv[2]
line = open(conf).read().strip()
# :name:type:offset:magic:mask:interpreter:flags
parts = line.split(':')
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
print(f"  name={name} type={typ} offset={off!r} interp={interp} flags={flags}")
print(f"  magic={m.hex()} ({len(m)} B)  mask={k.hex()} ({len(k)} B)")
assert len(m) == len(k), "magic and mask must be the same length"
assert m[:4] == b'\x7fELF', "magic does not start with the ELF header"
assert m[18:20] == b'\xb7\x00', f"e_machine is {m[18:20].hex()}, not aarch64 (b7 00)"
assert os.path.exists(interp), f"interpreter {interp} is not installed"
# the mask must actually ignore nothing at e_machine, or an x86_64 binary can match
assert k[18:20] == b'\xff\xff', "mask does not pin e_machine - this would hijack host binaries"
rule = f':{name}:{typ}:{off}:{binascii.hexlify(m).decode()}:{binascii.hexlify(k).decode()}:{interp}:{flags}\n'
# the kernel wants the magic/mask as \x-escapes, not hex text
rule = rule.replace(f':{binascii.hexlify(m).decode()}:', ':' + ''.join(f'\\x{b:02x}' for b in m) + ':')
rule = rule.replace(f':{binascii.hexlify(k).decode()}:', ':' + ''.join(f'\\x{b:02x}' for b in k) + ':')
with open(reg, 'w') as f:
    f.write(rule)
print("  written to register")
PY
echo "  python rc=$?"

echo "=== did we just break the host?  if so, undo it now ==="
if ! /usr/bin/true; then
  echo "  !! host binaries are broken - unregistering"
  echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64
  echo "  unregistered; host check: $(/usr/bin/true && echo ok)"
  exit 1
fi
echo "  host binaries still fine"

echo "=== the test that matters ==="
ls /proc/sys/fs/binfmt_misc/ | sed 's/^/  handler: /'
grep -E '^(enabled|interpreter|flags|offset|magic|mask)' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null | sed 's/^/  /'
chroot /root/r36/rootfs /bin/sh -c 'uname -m; echo "arm64 chroot works"' 2>&1 | sed 's/^/  /'
echo "  rc=${PIPESTATUS[0]}"
