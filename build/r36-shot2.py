#!/usr/bin/env python3
"""r36-shot2.py - the pending-request variant of the screenshot trick.

r36-shot.py pressed its keys while no capture was outstanding, and weston 14's
screenshooter client got "unauthorized" because the compositor only grants
capture authority to the client that the *user action* is for.  So flip the
order: arm a weston-screenshooter request first, then inject the key, and see
whether the binding releases the pending capture.

Reports every new file anywhere on the card, not just PNGs - the flight recorder
proved that weston writes where its cwd is (/), and that is how capture.wcap was
found in the first place.
"""
import ctypes
import os
import struct
import subprocess
import sys
import threading
import time

EV_SYN, EV_KEY = 0, 1
KEYS = {
    "meta": 125, "ctrl": 29, "alt": 56, "shift": 42,
    "print": 210, "p": 25, "s": 19, "3": 4, "k": 37, "f": 33, "b": 48,
}
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
NAME = b"r36-shot2-virtual-keyboard"

COMBOS = [
    ("Super+Print", ["meta", "print"]),
    ("Print", ["print"]),
    ("Super+Shift+S", ["meta", "shift", "s"]),
    ("Ctrl+Shift+S", ["ctrl", "shift", "s"]),
    ("Alt+Print", ["alt", "print"]),
    ("Super+S", ["meta", "s"]),
]

libc = ctypes.CDLL("libc.so.6", use_errno=True)
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/wayland", WAYLAND_DISPLAY="wayland-0")


def ioctl_int(fd, req, arg):
    if libc.ioctl(fd, ctypes.c_ulong(req), ctypes.c_int(arg)) < 0:
        raise OSError("ioctl %#x: %s" % (req, os.strerror(ctypes.get_errno())))


def make_keyboard():
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    ioctl_int(fd, UI_SET_EVBIT, EV_KEY)
    for k in KEYS.values():
        ioctl_int(fd, UI_SET_KEYBIT, k)
    rec = bytearray(80 + 8 + 4 + 4 * 4 * 64)
    rec[0:len(NAME)] = NAME
    struct.pack_into("<HHHH", rec, 80, 0x19, 0x1234, 0x5678, 1)
    os.write(fd, bytes(rec))
    ioctl_int(fd, UI_DEV_CREATE, 0)
    return fd


def send(fd, etype, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, etype, code, value))


def press(fd, names):
    for n in names:
        send(fd, EV_KEY, KEYS[n], 1)
        send(fd, EV_SYN, 0, 0)
    for n in reversed(names):
        send(fd, EV_KEY, KEYS[n], 0)
        send(fd, EV_SYN, 0, 0)
    send(fd, EV_SYN, 0, 0)


def new_since(stamp):
    """files created/modified after the epoch `stamp` - one find instead of two
    full snapshots (the rootfs has ~100k files and a full walk costs seconds)"""
    out = subprocess.run(["find", "/", "-xdev", "-type", "f", "-newermt",
                          "@%d" % int(stamp)],
                         capture_output=True, text=True, timeout=60).stdout
    skip = ("/proc/", "/sys/", "/run/", "/var/log/", "/var/lib/systemd/", "/tmp/r36-shot2")
    return [p for p in out.split("\n") if p and not p.startswith(skip)]


def main():
    fd = make_keyboard()
    time.sleep(2.0)
    print("  keyboard up; weston procs: %s" % subprocess.run(
        ["pgrep", "-c", "weston"], capture_output=True, text=True).stdout.strip())

    for label, combo in COMBOS:
        stamp = time.time()
        target = "/tmp/shot-%s.png" % label.replace("+", "_")
        try:
            os.unlink(target)
        except OSError:
            pass
        # arm the request in the background so it is pending when the key lands
        proc = subprocess.Popen(["weston-screenshooter", target], env=ENV,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.4)
        press(fd, combo)
        time.sleep(1.2)
        if proc.poll() is None:
            proc.kill()
        real = new_since(stamp)
        png = [n for n in real if n.endswith(".png") or n.endswith(".bmp")]
        print("  %-15s new: %-44s png: %s" %
              (label, ", ".join(real[:2]) if real else "-", png or "-"))
        if png:
            data = open(png[0], "rb").read()
            dest = "/tmp/r36-shot.png"
            with open(dest, "wb") as f:
                f.write(data)
            print("  ==> saved %s (%d bytes) from %s" % (dest, len(data), png[0]))
            libc.ioctl(fd, ctypes.c_ulong(UI_DEV_DESTROY), ctypes.c_int(0))
            os.close(fd)
            return 0

    libc.ioctl(fd, ctypes.c_ulong(UI_DEV_DESTROY), ctypes.c_int(0))
    os.close(fd)
    print("  no combo produced an image - weston 14 needs its own screenshooter")
    print("  helper for capture authority; use r36-wayland smoke + a photo, or the")
    print("  flight recorder (/capture.wcap) for compositor-side debugging.")
    return 1


sys.exit(main())
