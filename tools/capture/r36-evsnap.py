#!/usr/bin/env python3
"""r36-evsnap - capture EV_KEY events from a uinput device by name.

Used to verify a keyboard without looking at the panel: open the event node that
the tool created, dump every key down/up, and write the sequence to a file so a
shell script can diff it against the expected stream.

    r36-evsnap "r36 on-screen keyboard" 20
"""
import glob
import os
import select
import struct
import sys
import time


def find_node(sub, timeout=15.0):
    end = time.time() + timeout
    while time.time() < end:
        for path in glob.glob("/sys/class/input/event*/device/name"):
            try:
                name = open(path, errors="replace").read().strip()
            except OSError:
                continue
            if sub in name:
                ev = path.split("/")[4]
                return "/dev/input/" + ev, name
        time.sleep(0.1)
    return None, None


def main():
    if len(sys.argv) < 3:
        print("usage: r36-evsnap <device-name-substring> <seconds> [outfile]", file=sys.stderr)
        return 2
    sub, secs = sys.argv[1], float(sys.argv[2])
    out_path = sys.argv[3] if len(sys.argv) > 3 else "/tmp/evsnap.seq"
    node, name = find_node(sub)
    if not node:
        print("  !! no event device whose name contains %r (created within 15s)" % sub,
              file=sys.stderr)
        return 2
    print("  capturing %s (%s) for %.0fs" % (node, name, secs))
    fd = os.open(node, os.O_RDONLY)
    events, t0 = [], time.time()
    try:
        while time.time() - t0 < secs:
            r, _, _ = select.select([fd], [], [], 0.25)
            if not r:
                continue
            try:
                data = os.read(fd, 24 * 128)
            except OSError:
                break
            for i in range(0, len(data) - 23, 24):
                _, _, etype, code, value = struct.unpack("llHHi", data[i:i + 24])
                if etype == 1:                       # EV_KEY
                    events.append((code, value))
    finally:
        os.close(fd)
    seq = " ".join("%d,%d" % cv for cv in events)
    with open(out_path, "w") as fh:
        fh.write(seq + "\n")
    print("  %d EV_KEY events -> %s" % (len(events), out_path))
    print("  " + seq)
    return 0


if __name__ == "__main__":
    sys.exit(main())
