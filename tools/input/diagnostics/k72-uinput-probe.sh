#!/bin/bash
# k72-uinput-probe.sh - the keyboard device came up (weston tagged it), but the
# mouse died on UI_SET_RELBIT with EINVAL.  Stop the crash-looping service, then
# find out exactly which call order this kernel accepts.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
systemctl stop r36-keymapper 2>/dev/null
echo "  keymapper stopped: $(systemctl is-active r36-keymapper)"
echo "=== the real ioctl numbers from the installed header ==="
grep -nE "define UI_(SET_EVBIT|SET_KEYBIT|SET_RELBIT|SET_ABSBIT|DEV_CREATE|DEV_DESTROY|DEV_SETUP)" \
  /usr/include/linux/uinput.h | sed 's/^/  /'
grep -nE "define REL_MAX|define KEY_MAX|define EV_MAX" /usr/include/linux/input-event-codes.h | sed "s/^/  /"

echo
echo "=== minimal experiment: which order works? ==="
python3 - <<'PY'
import ctypes, os, struct, time
libc = ctypes.CDLL("libc.so.6", use_errno=True)
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
RECORD = 80 + 8 + 4 + 4 * 4 * 64

def attempt(label, seq):
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    for req, arg in seq:
        if libc.ioctl(fd, ctypes.c_ulong(req), ctypes.c_int(arg)) < 0:
            print("  %-28s FAILED ioctl %#x arg %d: %s" % (label, req, arg, os.strerror(ctypes.get_errno())))
            os.close(fd)
            return False
    rec = bytearray(RECORD)
    name = label.encode()[:80]
    rec[0:len(name)] = name
    struct.pack_into("<HHHH", rec, 80, 0x19, 1, 1, 1)
    try:
        n = os.write(fd, bytes(rec))
    except OSError as e:
        print("  %-28s write failed: %s" % (label, e))
        os.close(fd)
        return False
    if libc.ioctl(fd, ctypes.c_ulong(UI_DEV_CREATE), ctypes.c_int(0)) < 0:
        print("  %-28s CREATE failed: %s" % (label, os.strerror(ctypes.get_errno())))
        os.close(fd)
        return False
    print("  %-28s OK (wrote %d bytes)" % (label, n))
    time.sleep(0.3)
    libc.ioctl(fd, ctypes.c_ulong(UI_DEV_DESTROY), ctypes.c_int(0))
    os.close(fd)
    return True

attempt("ev_key+keys then ev_rel", [(UI_SET_EVBIT, 1), (UI_SET_KEYBIT, 272), (UI_SET_KEYBIT, 273),
                                    (UI_SET_EVBIT, 2), (UI_SET_RELBIT, 0), (UI_SET_RELBIT, 1)])
attempt("both ev bits first",      [(UI_SET_EVBIT, 1), (UI_SET_EVBIT, 2), (UI_SET_KEYBIT, 272),
                                    (UI_SET_RELBIT, 0), (UI_SET_RELBIT, 1)])
attempt("rel only",                [(UI_SET_EVBIT, 2), (UI_SET_RELBIT, 0), (UI_SET_RELBIT, 1),
                                    (UI_SET_RELBIT, 8), (UI_SET_RELBIT, 27), (UI_SET_RELBIT, 28)])
attempt("rel wheel only",          [(UI_SET_EVBIT, 2), (UI_SET_RELBIT, 27)])
PY
echo
echo "=== does a pointer device show up as a mouse to udev? ==="
ls /sys/class/input/ | grep event | sed 's/^/  /' | tr '\n' ' '; echo
EOS
echo "=== probe done ==="
