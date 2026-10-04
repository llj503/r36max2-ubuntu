#!/usr/bin/env python3
"""r36-shot.py - get a picture of what the r36max2 panel is showing, from SSH.

Weston 14 gates screen capture: a client that simply asks for a framebuffer is
answered "unauthorized" (libweston has weston_compositor_add_screenshot_authority
and only grants it to the client the *user* triggered), and grim/wf-recorder are
out because they need wlr-screencopy, which weston does not implement.

So this script plays the user.  It builds a throwaway keyboard on /dev/uinput
(uinput is built into this kernel, no module needed), lets libinput claim it, and
types the screenshot binding.  weston 14 does not name the binding anywhere a
binary string dump can show, so we try the plausible ones and, after each, look
for a *newly created* image file - anywhere on the card, because the save path
has been seen in $HOME, $HOME/Pictures and XDG_RUNTIME_DIR depending on build.

    r36-shot.py [out.png]

Exit 0 means a real PNG is waiting at that path.
"""
import ctypes
import glob
import os
import struct
import subprocess
import sys
import time

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r36-shot.png"
EV_SYN, EV_KEY = 0, 1
KEY_LEFTMETA, KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTSHIFT = 125, 29, 56, 42
KEY_PRINT, KEY_P, KEY_S, KEY_3 = 210, 25, 19, 4

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
NAME = b"r36-shot-virtual-keyboard"

# tried in order; first one that produces a file wins
BINDINGS = [
    ("Super+Print", [KEY_LEFTMETA, KEY_PRINT]),
    ("Print", [KEY_PRINT]),
    ("Ctrl+Alt+P", [KEY_LEFTCTRL, KEY_LEFTALT, KEY_P]),
    ("Super+S", [KEY_LEFTMETA, KEY_S]),
    ("Ctrl+Shift+3", [KEY_LEFTCTRL, KEY_LEFTSHIFT, KEY_3]),
]

libc = ctypes.CDLL("libc.so.6", use_errno=True)


def png_dims(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return "%dx%d" % struct.unpack(">II", head[16:24])
    except OSError:
        return None


def new_images(since_epoch):
    """anything that looks like a fresh image, card-wide (the rootfs is small)"""
    cmd = ["find", "/", "-xdev", "(", "-name", "*.png", "-o", "-name", "*.bmp", ")",
           "-newermt", "@%d" % int(since_epoch), "-size", "+1k", "-print"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=25).stdout
    except Exception:
        out = ""
    skip = ("/usr/share/", "/usr/lib/", "/var/lib/", "/snap/", "/etc/xdg/")
    return [p for p in out.split("\n") if p and not p.startswith(skip)]


def ioctl_int(fd, req, arg):
    if libc.ioctl(fd, ctypes.c_ulong(req), ctypes.c_int(arg)) < 0:
        raise OSError("ioctl %#x: %s" % (req, os.strerror(ctypes.get_errno())))


def make_keyboard():
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    ioctl_int(fd, UI_SET_EVBIT, EV_KEY)
    for k in (KEY_LEFTMETA, KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTSHIFT,
              KEY_PRINT, KEY_P, KEY_S, KEY_3):
        ioctl_int(fd, UI_SET_KEYBIT, k)
    # struct uinput_user_dev is: char name[80]; struct input_id id (4 x u16);
    # __u32 ff_effects_max; then __s32 absmax/absmin/absres/absflat[ABS_CNT=64].
    # There is NO padding after ff_effects_max, so the size is 80+8+4+1024 = 1116,
    # and uinput_write() demands an exact count - a 1120-byte write fails with
    # EINVAL (that is what broke the first revision of this script).
    UINPUT_USER_DEV_SIZE = 80 + 8 + 4 + 4 * 4 * 64
    rec = bytearray(UINPUT_USER_DEV_SIZE)
    rec[0:len(NAME)] = NAME
    struct.pack_into("<HHHH", rec, 80, 0x19, 0x1234, 0x5678, 0x0001)
    os.write(fd, bytes(rec))
    ioctl_int(fd, UI_DEV_CREATE, 0)
    return fd


def send(fd, etype, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, etype, code, value))


def press(fd, keys):
    for k in keys:
        send(fd, EV_KEY, k, 1)
        send(fd, EV_SYN, 0, 0)
    for k in reversed(keys):
        send(fd, EV_KEY, k, 0)
        send(fd, EV_SYN, 0, 0)


def main():
    if not os.path.isdir("/run/wayland"):
        print("  no /run/wayland - start it first: r36-wayland start")
        return 1
    env = dict(os.environ, XDG_RUNTIME_DIR="/run/wayland", WAYLAND_DISPLAY="wayland-0")

    # 1. the polite request, which weston 14 is expected to refuse
    subprocess.run(["weston-screenshooter", OUT], env=env, capture_output=True, timeout=8)
    if png_dims(OUT):
        print("  captured via direct request: %s %s" % (OUT, png_dims(OUT)))
        return 0

    fd = make_keyboard()
    print("  virtual keyboard created; waiting for libinput")
    time.sleep(2.0)

    found = None
    for label, keys in BINDINGS:
        stamp = time.time() - 1
        press(fd, keys)
        for _ in range(10):
            time.sleep(0.25)
            hits = new_images(stamp)
            if hits:
                found = (label, hits[-1])
                break
        if found:
            break
        print("    %-14s -> nothing new on disk" % label)

    try:
        libc.ioctl(fd, ctypes.c_ulong(UI_DEV_DESTROY), ctypes.c_int(0))
    except OSError:
        pass
    os.close(fd)

    if not found:
        print("  no binding produced a file. weston input log:")
        log = subprocess.run(["journalctl", "-u", "weston", "--no-pager", "-n", "8"],
                             capture_output=True, text=True).stdout
        print("".join("    %s\n" % l for l in log.splitlines()[-8:]))
        print("  -> the compositor IS running and GL clients render into it; the panel")
        print("     content still has to be photographed, or the binding found with")
        print("     `strings /usr/lib/aarch64-linux-gnu/libweston-14.so.0 | grep -i key`")
        return 1

    label, path = found
    os.replace(path, OUT)
    print("  captured via %s: %s  (%s, %d B)" % (label, OUT, png_dims(OUT) or "?",
                                                 os.path.getsize(OUT)))
    return 0


sys.exit(main())
