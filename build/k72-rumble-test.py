#!/usr/bin/env python3
"""k72-rumble-test.py - runs ON the r36max2.  Plays an FF_RUMBLE effect through
the joypad input device while sampling the rumble GPIO out of debugfs, so the
whole chain is proven in both directions with the corrected polarity:

    logical 1  ->  pad HIGH  ->  motor spins     (measured on hardware)
    logical 0  ->  pad LOW   ->  motor silent

Usage on the device:  python3 k72-rumble-test.py [ms] [device-node]
Exit code 0 means the effect was accepted; the pin trace is printed so a human
can confirm it matches what they felt.
"""
import ctypes
import os
import struct
import subprocess
import sys
import threading
import time

DUR_MS = int(sys.argv[1]) if len(sys.argv) > 1 else 700
NODE = (sys.argv[2] if len(sys.argv) > 2 else
        "/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick")

FF_RUMBLE = 0x50
EV_FF = 0x15
EVIOCSFF = 0x40284580            # _IOW('E', 0x80, struct ff_effect)  size 0x28
EVIOCRMFF = 0x40044581           # _IOW('E', 0x81, int)


class TimeVal(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


def build_effect(effect_id, strong, weak, length_ms):
    """Lay out struct ff_effect by hand: the union contains pointers, so a
    ctypes mirror gets the size wrong (EVIOCSFF encodes sizeof==40 and answers
    EFAULT for anything shorter).  Offsets from uapi/linux/input.h:

        0  __u16 type          6  trigger.button     10 replay.length
        2  __s16 id            8  trigger.interval   12 replay.delay
        4  __u16 direction    16+ union u (8-byte aligned)
                             16  rumble.weak  18  rumble.strong
    """
    buf = bytearray(40)
    struct.pack_into("<HhH", buf, 0, FF_RUMBLE, effect_id, 0)
    struct.pack_into("<HH", buf, 6, 0, 0)            # ff_trigger
    struct.pack_into("<HH", buf, 10, length_ms, 0)   # ff_replay {length, delay}
    struct.pack_into("<HH", buf, 16, weak, strong)   # struct ff_rumble_effect
    return buf


def rumble_pin():
    try:
        for line in open("/sys/kernel/debug/gpio", errors="replace"):
            if "|rumble" in line:
                parts = line.split()
                try:
                    i = parts.index("out")
                    return parts[i + 1]
                except ValueError:
                    return "?"
    except OSError:
        pass
    return "n/a"


def write_event(fd, etype, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, etype, code, value))


def main():
    if not os.path.exists(NODE):
        print("  no such node: %s" % NODE)
        return 1
    subprocess.run(["mount", "-t", "debugfs", "none", "/sys/kernel/debug"],
                   capture_output=True)
    print("  node      : %s" % NODE)
    print("  pin before: rumble=%s" % rumble_pin())

    fd = os.open(NODE, os.O_RDWR)

    trace = []
    stop_at = time.monotonic() + DUR_MS / 1000.0 + 0.6
    sampling = [True]

    def sampler():
        while sampling[0] and time.monotonic() < stop_at:
            trace.append((round(time.monotonic() - t0, 3), rumble_pin()))
            time.sleep(0.04)

    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    raw = build_effect(-1, 0xffff, 0xa000, DUR_MS)
    buf = ctypes.create_string_buffer(bytes(raw), len(raw))
    if libc.ioctl(fd, EVIOCSFF, buf) != 0:
        print("  !! EVIOCSFF failed: %s" % os.strerror(ctypes.get_errno()))
        os.close(fd)
        return 1
    eff_id = struct.unpack_from("h", buf.raw, 2)[0]
    print("  effect id : %d (strong=0xffff weak=0xa000, %d ms)" % (eff_id, DUR_MS))

    t0 = time.monotonic()
    th = threading.Thread(target=sampler)
    th.start()
    write_event(fd, EV_FF, eff_id, 1)
    print("  playing...  (you should feel it vibrate)")
    time.sleep(DUR_MS / 1000.0)
    write_event(fd, EV_FF, eff_id, 0)
    print("  stopped")
    th.join()
    sampling[0] = False
    libc.ioctl(fd, EVIOCRMFF, ctypes.c_int(eff_id))
    os.close(fd)

    hi = [s for _, s in trace if s == "hi"]
    print("  pin trace : %d samples, %d hi, %d lo" % (len(trace), len(hi), len(trace) - len(hi)))
    edges = []
    prev = None
    for stamp, state in trace:
        if state != prev:
            edges.append((stamp, state))
            prev = state
    print("  edges     : " + ", ".join("%.2fs=%s" % e for e in edges))
    print("  pin after : rumble=%s" % rumble_pin())
    print("  VERDICT   : " + ("motor was driven high then released low -> polarity correct"
                              if hi and rumble_pin() == "lo" else
                              "INCONCLUSIVE - check the trace above"))
    return 0


sys.exit(main())
