#!/usr/bin/env python3
"""r36-capdump - print an evdev device's BTN_* codes in the order the Linux joystick
interface will number them, read straight from the kernel via EVIOCGBIT(EV_KEY).

Why not /sys/class/input/eventN/device/capabilities/key: on arm64 that file prints
64-bit words and drops leading zeros, so parsing it as 32-bit words silently yields
an empty set - which once produced a bogus "15 buttons would be mislabelled" report.
The ioctl returns a little-endian byte bitmap with no such ambiguity.

    r36-capdump /dev/input/event2
"""
import fcntl
import os
import sys

# values taken from this tree's uapi/linux/input-event-codes.h, not from memory
BTNS = {
    0x120: "BTN_MISC", 0x130: "BTN_SOUTH", 0x131: "BTN_EAST", 0x133: "BTN_NORTH",
    0x134: "BTN_WEST", 0x135: "BTN_Z", 0x136: "BTN_TL", 0x137: "BTN_TR",
    0x138: "BTN_TL2", 0x139: "BTN_TR2", 0x13A: "BTN_SELECT", 0x13B: "BTN_START",
    0x13C: "BTN_MODE", 0x13D: "BTN_THUMBL", 0x13E: "BTN_THUMBR",
    0x220: "BTN_DPAD_UP", 0x221: "BTN_DPAD_DOWN", 0x222: "BTN_DPAD_LEFT",
    0x223: "BTN_DPAD_RIGHT",
}
ABS = {0x00: "ABS_X", 0x01: "ABS_Y", 0x02: "ABS_Z", 0x03: "ABS_RX", 0x04: "ABS_RY",
       0x05: "ABS_RZ", 0x06: "ABS_THROTTLE", 0x07: "ABS_RUDDER", 0x09: "ABS_HAT0X",
       0x10: "ABS_HAT0Y"}


def bits(fd, req):
    size = 1024
    buf = bytearray(size)
    fcntl.ioctl(fd, (1 << 31) | (size << 16) | (ord('E') << 8) | req, buf)
    return [i for i in range(size * 8) if buf[i >> 3] >> (i & 7) & 1]


def main():
    node = sys.argv[1] if len(sys.argv) > 1 else "/dev/input/event2"
    if not os.path.exists(node):
        print("!! %s missing" % node, file=sys.stderr)
        return 2
    name = ""
    try:
        name = open(node.replace("/dev/input/", "/sys/class/input/") + "/device/name").read().strip()
    except OSError:
        pass
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    try:
        key = bits(fd, 0x20 + 1)          # EVIOCGBIT(EV_KEY)
        absn = bits(fd, 0x20 + 3)         # EVIOCGBIT(EV_ABS)
    finally:
        os.close(fd)
    print("# node=%s name=%s" % (node, name))
    print("# all key codes: %s" % " ".join("0x%x" % c for c in key))
    for i, c in enumerate(sorted(x for x in key if x in BTNS)):
        print("BUTTON %d 0x%03x %s" % (i, c, BTNS[c]))
    for i, c in enumerate(sorted(absn)):
        print("AXIS %d 0x%02x %s" % (i, c, ABS.get(c, "?")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
