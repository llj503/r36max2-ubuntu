#!/usr/bin/env python3
"""r36-keymapper - turn the R36 Max 2 joypad into a pointer and a keyboard.

Why this exists: the handheld has no keyboard, no USB host role and no working
Bluetooth, so once a Wayland session is running there is nothing to drive it
with.  /dev/uinput is built into the kernel (proven: weston picks up a virtual
keyboard instantly), so we read the joypad's evdev node and re-emit it as an
ordinary mouse + keyboard.  No kernel module, no dependencies beyond stdlib.

    r36-keymapper                 # run with defaults
    r36-keymapper --selftest      # print the mapping, touch no devices
    r36-keymapper --dry-run -v    # read the joypad, log what it WOULD send
    r36-keymapper --list          # resolved key/mouse codes per button

Grab model: by default the source node is grabbed (EVIOCGRAB) so js0 stops
reporting the same presses as a joystick while this runs; --no-grab leaves both
alive.  Stop the mapper (SIGTERM) and the joypad goes back to normal.

Map (chosen for a 1024x768 panel driven from the thumb, not for a game):

    left stick            pointer X/Y (deadzone + curve, see POINTER_*)
    right stick           scroll wheel (REL_WHEEL / REL_HWHEEL, rate-limited)
    A / B                 left click / right click
    X / Y                 Backspace / Space
    D-pad                 arrow keys
    SELECT / START / MODE Esc / Enter / Super
    L / R                 Ctrl / Alt            (held, combinable)
    L2 / R2               Shift / Tab
    L3 / R3               middle click / End

    Typing letters still needs SSH or an on-screen keyboard - 17 buttons cannot
    cover an alphabet, and inventing a chord layout here would be a different
    project.  This mapper's job is pointer + the keys you actually press to
    navigate.
"""
import argparse
import ctypes
import errno
import os
import signal
import struct
import subprocess
import sys
import time

SRC_DEFAULT = "/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick"

EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
ABS_X, ABS_Y, ABS_RX, ABS_RY = 0, 1, 3, 4

K = {  # linux/input-event-codes.h, only what the default map uses
    "ESC": 1, "TAB": 15, "ENTER": 28, "BACKSPACE": 14, "SPACE": 57,
    "LEFTCTRL": 29, "LEFTALT": 56, "LEFTSHIFT": 42, "LEFTMETA": 125,
    "UP": 103, "DOWN": 108, "LEFT": 105, "RIGHT": 106,
    "HOME": 102, "END": 107, "DELETE": 111, "PAGEDOWN": 109, "PAGEUP": 104,
    "PRINT": 210, "F1": 59, "F2": 60, "F5": 63, "F11": 67,
}
BTN = {  # mouse buttons emitted on the uinput pointer
    "LEFT": 272, "RIGHT": 273, "MIDDLE": 274, "SIDE": 275, "EXTRA": 276,
}
# REL_* are small integers, NOT the 0x1b values I first guessed: REL_MAX is
# 0x0f in <linux/input-event-codes.h>, so setting 27/28 makes UI_SET_RELBIT fail
# with EINVAL and the pointer device never gets created.
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0, 1, 6, 8
REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES = 11, 12

# joypad codes we map by name so the table below stays readable
JOY = {
    "BTN_SOUTH": 304, "BTN_EAST": 305, "BTN_NORTH": 307, "BTN_WEST": 308,
    "BTN_TL": 310, "BTN_TR": 311, "BTN_TL2": 312, "BTN_TR2": 313,
    "BTN_SELECT": 314, "BTN_START": 315, "BTN_MODE": 316,
    "BTN_THUMBL": 317, "BTN_THUMBR": 318,
    "BTN_DPAD_UP": 544, "BTN_DPAD_DOWN": 545, "BTN_DPAD_LEFT": 546,
    "BTN_DPAD_RIGHT": 547,
}

# kind, argument
KEYMAP = {
    "BTN_EAST":     ("btn",   "LEFT"),
    "BTN_SOUTH":    ("btn",   "RIGHT"),
    "BTN_NORTH":    ("key",   "BACKSPACE"),
    "BTN_WEST":     ("key",   "SPACE"),
    "BTN_DPAD_UP":    ("key", "UP"),
    "BTN_DPAD_DOWN":  ("key", "DOWN"),
    "BTN_DPAD_LEFT":  ("key", "LEFT"),
    "BTN_DPAD_RIGHT": ("key", "RIGHT"),
    "BTN_SELECT":   ("key",   "ESC"),
    "BTN_START":    ("key",   "ENTER"),
    "BTN_MODE":     ("key",   "LEFTMETA"),
    "BTN_TL":       ("key",   "LEFTCTRL"),
    "BTN_TR":       ("key",   "LEFTALT"),
    "BTN_TL2":      ("key",   "LEFTSHIFT"),
    "BTN_TR2":      ("key",   "TAB"),
    "BTN_THUMBL":   ("btn",   "MIDDLE"),
    "BTN_THUMBR":   ("key",   "END"),
}

# pointer feel: full tilt gives POINTER_MAX px per tick, with an exponent so the
# first third of the throw is fine control and the end is a fast sweep.
POINTER_DZ = 220
POINTER_MAX = 24
POINTER_EXP = 1.7
SCROLL_DZ = 900
SCROLL_PERIOD = 0.16          # seconds between wheel clicks while held


def resolve(name):
    if name in K:
        return EV_KEY, K[name]
    if name in BTN:
        return EV_KEY, BTN[name]
    raise KeyError("unknown key/button name: %s" % name)


class Uinput:
    """one /dev/uinput device; caps is {ev_bit: [codes]}"""

    UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
    UI_SET_RELBIT = 0x40045566
    UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
    RECORD_SIZE = 80 + 8 + 4 + 4 * 4 * 64        # 1116, exact or EINVAL

    def __init__(self, name, ev_bits, libc):
        self.libc = libc
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for bit, codes in ev_bits.items():
            self._ioctl(self.UI_SET_EVBIT, bit)
            setter = {EV_KEY: self.UI_SET_KEYBIT, EV_REL: self.UI_SET_RELBIT}.get(bit)
            for c in codes:
                if setter is None:
                    continue
                self._ioctl(setter, c)
        rec = bytearray(self.RECORD_SIZE)
        raw = name.encode()[:80]
        rec[0:len(raw)] = raw
        # struct input_id {bustype, vendor, product, version}
        struct.pack_into("<HHHH", rec, 80, 0x19, 0x484B, 0x1101, 0x0100)
        os.write(self.fd, bytes(rec))
        self._ioctl(self.UI_DEV_CREATE, 0)

    def _ioctl(self, req, arg):
        if self.libc.ioctl(self.fd, ctypes.c_ulong(req), ctypes.c_int(arg)) < 0:
            raise OSError("uinput ioctl %#x: %s" % (req, os.strerror(ctypes.get_errno())))

    def event(self, etype, code, value):
        os.write(self.fd, struct.pack("llHHi", 0, 0, etype, code, value))

    def syn(self):
        self.event(EV_SYN, 0, 0)

    def close(self):
        try:
            self._ioctl(self.UI_DEV_DESTROY, 0)
        except OSError:
            pass
        os.close(self.fd)


def pointer_step(value, side_dz=None):
    """axis reading -> pixels per tick"""
    dz = POINTER_DZ if side_dz is None else side_dz
    if abs(value) <= dz:
        return 0
    mag = (abs(value) - dz) / float(32768 - dz) if abs(value) > 1800 else \
          (abs(value) - dz) / float(1800 - dz)
    mag = max(0.0, min(1.0, mag))
    return int(round((mag ** POINTER_EXP) * POINTER_MAX)) * (1 if value > 0 else -1)


def main():
    ap = argparse.ArgumentParser(description="map the r36max2 joypad to mouse+keyboard")
    ap.add_argument("--source", default=SRC_DEFAULT)
    ap.add_argument("--selftest", action="store_true", help="print the mapping and exit")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="read the pad, send nothing")
    ap.add_argument("--no-grab", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if args.list or args.selftest:
        print("joypad -> uinput map (%d buttons, %d axes):" % (len(KEYMAP), 4))
        for name in sorted(JOY):
            kind, arg = KEYMAP.get(name, ("-", "-"))
            if kind == "key":
                shown = "key %-10s = %d" % (arg, K[arg])
            elif kind == "btn":
                shown = "btn %-10s = %d" % (arg, BTN[arg])
            else:
                shown = "-"
            print("    %-15s -> %s" % (name, shown))
        print("    ABS_X/ABS_Y   -> pointer  (dz=%d, max=%d px/tick, exp=%.1f)"
              % (POINTER_DZ, POINTER_MAX, POINTER_EXP))
        print("    ABS_RX/ABS_RY -> wheel    (dz=%d, every %.2fs)"
              % (SCROLL_DZ, SCROLL_PERIOD))
        print("    sample curves: axis 800->%d  1800->%d  24000->%d px/tick"
              % (pointer_step(800), pointer_step(1800), pointer_step(24000)))
        return 0

    if not os.path.exists(args.source):
        print("no such input node: %s" % args.source, file=sys.stderr)
        return 1
    if not os.path.exists("/dev/uinput"):
        print("/dev/uinput missing - CONFIG_UINPUT has to be built in", file=sys.stderr)
        return 1

    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    src = os.open(args.source, os.O_RDWR)
    if not args.no_grab and not args.dry_run:
        EVIOCGRAB = 0x40044590                      # _IOW('E', 0x90, int)
        if libc.ioctl(src, ctypes.c_ulong(EVIOCGRAB), ctypes.c_int(1)) < 0:
            print("  grab failed (%s); continuing un-grabbed"
                  % os.strerror(ctypes.get_errno()), file=sys.stderr)

    kb = mouse = None
    if not args.dry_run:
        kb = Uinput("r36 joypad keyboard", {EV_KEY: sorted(K.values())}, libc)
        mouse = Uinput("r36 joypad mouse",
                       {EV_KEY: sorted(BTN.values()),
                        EV_REL: [REL_X, REL_Y, REL_WHEEL, REL_HWHEEL,
                                 REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES]}, libc)
        # libinput only classifies the pointer as a mouse once it sees a move,
        # which is fine, but it needs the device to exist before weston maps it
        print("  created /dev/uinput devices (keyboard + mouse)")

    axes = {ABS_X: 0, ABS_Y: 0, ABS_RX: 0, ABS_RY: 0}
    held = set()
    last_scroll = 0.0
    EVENT_SIZE = struct.calcsize("llHHi")
    stop = [False]

    def bye(signum, frame):
        stop[0] = True
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGINT, bye)

    def send(etype, code, value, why=""):
        if args.dry_run:
            if args.verbose:
                print("  would send %s %d %d %s" % (etype, code, value, why))
            return
        dev = mouse if (etype == EV_REL or code in BTN.values()) else kb
        dev.event(etype, code, value)

    print("  reading %s (Ctrl-C to stop)" % args.source)
    while not stop[0]:
        try:
            buf = os.read(src, EVENT_SIZE * 32)
        except OSError as e:
            if e.errno == errno.EAGAIN:
                time.sleep(0.01)
                continue
            print("  device gone: %s" % e, file=sys.stderr)
            break
        if len(buf) < EVENT_SIZE:
            time.sleep(0.005)
            continue
        for i in range(len(buf) // EVENT_SIZE):
            _sec, _usec, etype, code, value = struct.unpack_from("llHHi", buf, i * EVENT_SIZE)
            if etype == EV_ABS and code in axes:
                axes[code] = value
                if code in (ABS_X, ABS_Y):
                    dx = pointer_step(axes[ABS_X])
                    dy = pointer_step(axes[ABS_Y])
                    if dx or dy:
                        send(EV_REL, REL_X, dx)
                        send(EV_REL, REL_Y, dy)
                        if not args.dry_run:
                            mouse.syn()
                else:
                    now = time.monotonic()
                    if now - last_scroll < SCROLL_PERIOD:
                        continue
                    step = pointer_step(axes[ABS_RY], side_dz=SCROLL_DZ)   # stick up = scroll down
                    hstep = pointer_step(axes[ABS_RX], side_dz=SCROLL_DZ)
                    if step or hstep:
                        # a wheel value is a NUMBER OF NOTCHES, not a pixel
                        # distance: the first version reused pointer_step()'s
                        # 0..24 curve and emitted 23 notches per click, which
                        # libinput faithfully turned into "scroll a whole page".
                        # Emit one notch (and its hi-res equivalent, 120 units),
                        # and let SCROLL_PERIOD control the rate.
                        send(EV_REL, REL_WHEEL, -1 if step > 0 else (1 if step < 0 else 0))
                        send(EV_REL, REL_WHEEL_HI_RES, -120 if step > 0 else (120 if step < 0 else 0))
                        send(EV_REL, REL_HWHEEL, 1 if hstep > 0 else (-1 if hstep < 0 else 0))
                        send(EV_REL, REL_HWHEEL_HI_RES, 120 if hstep > 0 else (-120 if hstep < 0 else 0))
                        if not args.dry_run:
                            mouse.syn()
                        last_scroll = now
            elif etype == EV_KEY and code in JOY.values():
                name = next(n for n, c in JOY.items() if c == code)
                if name not in KEYMAP:
                    continue
                kind, arg = KEYMAP[name]
                code_out = K[arg] if kind == "key" else BTN[arg]
                if value and name not in held:
                    held.add(name)
                    send(EV_KEY, code_out, 1, name)
                elif not value and name in held:
                    held.discard(name)
                    send(EV_KEY, code_out, 0, name)
                if not args.dry_run:
                    (mouse if kind == "btn" else kb).syn()
                if args.verbose:
                    print("  %-15s %s -> %s %s" % (name, "press" if value else "release",
                                                   kind, arg))

    for name in sorted(held):                     # never leave a key stuck down
        kind, arg = KEYMAP.get(name, (None, None))
        if kind == "key":
            send(EV_KEY, K[arg], 0)
        elif kind == "btn":
            send(EV_KEY, BTN[arg], 0)
    for dev in (kb, mouse):
        if dev:
            dev.close()
    os.close(src)
    return 0


sys.exit(main())
