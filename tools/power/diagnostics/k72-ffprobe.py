#!/usr/bin/env python3
"""k72-ffprobe.py - runs ON the r36max2.  Find out why EVIOCSFF says EFAULT:
read the FF capability bitmap and the effect-slot count, then try uploading an
FF_RUMBLE effect with every plausible command encoding / struct size so we can
see which one the kernel actually wants (struct ff_effect carries pointers in
its union, so its size is arch-dependent).
"""
import ctypes
import glob
import os
import struct
import subprocess
import sys

NODE = sys.argv[1] if len(sys.argv) > 1 else \
    "/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick"
FF_RUMBLE = 0x50
EV_FF = 0x15
libc = ctypes.CDLL("libc.so.6", use_errno=True)


def ff_cap_path(node):
    real = os.path.realpath(node)            # /sys/class/input/eventN
    for p in ("/sys/class/input/%s/device/capabilities/ff",
              "/sys/class/input/%s/input/input*/capabilities/ff"):
        ev = os.path.basename(real)
        g = glob.glob(p % ev)
        if g:
            return g[0]
    d = glob.glob("/sys/class/input/%s/input*/capabilities/ff" % os.path.basename(real))
    return d[0] if d else None


def eviocgffects(fd):
    # _IOR('E', 0x84, int) -> dir=2(size 4) type 'E' nr 0x84
    cmd = (2 << 30) | (4 << 16) | (ord("E") << 8) | 0x84
    out = ctypes.c_int(0)
    rc = libc.ioctl(fd, ctypes.c_ulong(cmd), ctypes.byref(out))
    return (rc, out.value, os.strerror(ctypes.get_errno()))


def try_upload(fd, size):
    # _IOW('E', 0x80, struct ff_effect) with the size we want to advertise
    cmd = (1 << 30) | (size << 16) | (ord("E") << 8) | 0x80
    raw = bytearray(size)
    struct.pack_into("<HhH", raw, 0, FF_RUMBLE, -1, 0)
    struct.pack_into("<HH", raw, 6, 0, 0)      # trigger
    struct.pack_into("<HH", raw, 10, 300, 0)   # replay length/delay
    struct.pack_into("<HH", raw, 16, 0xa000, 0xffff)  # u.rumble weak/strong
    buf = ctypes.create_string_buffer(bytes(raw), size)
    rc = libc.ioctl(fd, ctypes.c_ulong(cmd), buf)
    if rc == 0:
        return rc, struct.unpack_from("h", buf.raw, 2)[0], ""
    return rc, -1, os.strerror(ctypes.get_errno())


def main():
    p = ff_cap_path(NODE)
    try:
        print("  ff capability : %s  (%s)" % (open(p).read().strip(), p))
    except OSError as e:
        print("  ff capability : unreadable (%s)" % e)

    fd = os.open(NODE, os.O_RDWR)
    print("  EVIOCGEFFECTS : rc=%d slots=%d %s" % eviocgffects(fd))
    for size in (40, 48, 56, 64, 72, 80):
        rc, eid, err = try_upload(fd, size)
        print("  EVIOCSFF size=%d -> rc=%d id=%d %s" % (size, rc, eid, err))
        if rc == 0:
            # only find the accepted encoding this round - remove it right away
            rm = (1 << 30) | (4 << 16) | (ord("E") << 8) | 0x81
            libc.ioctl(fd, ctypes.c_ulong(rm), ctypes.c_int(eid))
            print("  => accepted: size %d (effect id %d), removed again" % (size, eid))
    os.close(fd)


main()
