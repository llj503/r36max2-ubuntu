#!/usr/bin/env python3
"""r36-osk - on-screen keyboard for the r36max2, built only from what is actually
available on this image.

Why not a packaged one: Ubuntu 26.04 ships no wvkbd/fsvkbd/svkbd; the two that do
exist (onboard, matchbox-keyboard) are X11 programs and there is no Xwayland in
this session; and weston 14 does *not* implement text-input-v3 (foot says so at
startup: "text input interface not implemented by compositor; IME will be
disabled"), so an input-method based keyboard has nothing to talk to.

Instead this composes two mechanisms already proven on this board:
  * /dev/uinput - weston accepts a virtual keyboard instantly (r36-keymapper uses
    it), and the keys arrive as real input events, so every client sees them
  * wofi --show dmenu --columns N - the only clickable grid weston will map

Two wofi facts measured on the device (v1.5.1), because each cost a debugging
round: it has no `grid`/`dgrid` mode at all ("I would love to show grid but Idk
what it is" - the grid layout comes from --columns in dmenu mode), and weston has
no wlr-layer-shell, so wofi falls back to a normal window ("switching to normal
window mode") - which is exactly what we want here.

The trick that gets a character into the right window: wofi holds keyboard focus
only while it is mapped, and weston returns focus to the previously focused
surface when it closes.  So each keystroke is: click a key -> wofi exits -> type
into whatever now has focus -> reopen.  One character per round trip, which
matches the speed a thumb on a joystick pointer can manage anyway.

    r36-osk                      # letters page, click away
    r36-osk --start symbols
    r36-osk --type 'Hello, 36!'   # no wofi, just type a string (test / scripted)
    r36-osk --list                # show the pages
SHFT latches Shift for the next key only, CAPS toggles it; both are shown in the
prompt so you can see the state without reading the panel closely.
"""
import argparse
import ctypes
import os
import struct
import subprocess
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY = 0, 1
RECORD_SIZE = 80 + 8 + 4 + 4 * 4 * 64            # exactly 1116 bytes
NAME = b"r36 on-screen keyboard"
CSS_PATH = "/run/r36-osk.css"
RETRY = "<retry>"                          # internal: grid timed out, show it again

K = {
    "ESC": 1, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9,
    "9": 10, "0": 11, "-": 12, "=": 13, "BACKSPACE": 14, "TAB": 15,
    "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23,
    "o": 24, "p": 25, "[": 26, "]": 27, "ENTER": 28, "CTRL": 29,
    "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37,
    "l": 38, ";": 39, "'": 40, "`": 41, "\\": 43,
    "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50,
    ",": 51, ".": 52, "/": 53, "SHIFT": 42, "SPACE": 57, "CAPS": 58,
    "UP": 103, "DOWN": 108, "LEFT": 105, "RIGHT": 106,
    "HOME": 102, "END": 107, "DEL": 111, "ALT": 56, "META": 125,
}

# Synonyms for the same physical key.  'RETURN' cost an evening: the phase-B rig asked for
# RETURN, only ENTER was in the table, r36-osk printed "injected 0/1 key presses" and the
# harness read that as "EmulationStation ignored my keys" instead of "my key name was wrong".
ALIAS = {
    "RETURN": "ENTER", "KEYPADENTER": "ENTER", "CR": "ENTER",
    "ESCAPE": "ESC", "BS": "BACKSPACE", "SPC": "SPACE",
    "PGUP": "PAGEUP", "PGDN": "PAGEDOWN", "ARROWUP": "UP", "ARROWDOWN": "DOWN",
    "ARROWLEFT": "LEFT", "ARROWRIGHT": "RIGHT",
}

# characters that need Shift+base key
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]",
    "|": "\\", ":": ";", '"': "'", "~": "`", "<": ",", ">": ".", "?": "/",
}

# Pages as ROWS, not a flat list: wofi fills a grid row by row, so a flat list
# put SHFT in the middle of a letter row.  Short rows are padded with <padN>.
PAGES = {
    "letters": [
        list("1234567890"),
        list("qwertyuiop"),
        list("asdfghjkl;"),
        ["<shift>"] + list("zxcvbnm") + [",", "."],
        ["<symbols>", "<nav>", "<caps>", "<space>", "<backspace>", "<del>",
         "<enter>", "<quit>"],
    ],
    "symbols": [
        ["~", "!", "@", "#", "$", "%", "^", "&", "*", "("],
        [")", "_", "+", "`", "{", "}", "[", "]", "|", ":"],
        ['"', "'", "<", ">", "?", "/", ".", ",", "\\", "-"],
        ["=", "<letters>", "<nav>", "<space>", "<backspace>", "<del>", "<quit>"],
    ],
    "nav": [
        ["<letters>", "<symbols>", "<up>", "<home>", "<pgup>", "<tab>"],
        ["<space>", "<backspace>", "<left>", "<down>", "<right>", "<end>"],
        ["<enter>", "<del>", "<esc>", "<ctrl>", "<alt>", "<meta>"],
        ["<shift>", "<caps>", "<quit>", "<pgdn>"],
    ],
}
LABEL = {
    "<space>": "SPC", "<enter>": "RET", "<backspace>": "DEL<", "<del>": ">DEL",
    "<shift>": "SHFT", "<caps>": "CAPS", "<quit>": "X", "<letters>": "ABC",
    "<symbols>": "#!?", "<nav>": "nav", "<up>": "/\\", "<down>": "\\/",
    "<left>": "<", "<right>": ">", "<home>": "HOME", "<end>": "END",
    "<tab>": "TAB", "<esc>": "ESC", "<ctrl>": "CTRL", "<alt>": "ALT",
    "<meta>": "META", "<pgup>": "PGUP", "<pgdn>": "PGDN", "<pad>": ".",
}
# wofi surface geometry per page: columns, width, height (panel is 1024x768)
LAYOUT = {"letters": (10, 940, 460), "symbols": (10, 940, 380), "nav": (6, 620, 340)}

CSS = """* { font: Monospace 15; }
#window { background-color: #14202c; }
#entry { color: #e6edf3; padding: 8px; min-height: 28px; }
#input { color: #7fd1ff; }
"""

ACTIONS = ("up", "down", "left", "right", "enter", "space", "backspace", "del",
           "tab", "esc", "ctrl", "alt", "meta", "home", "end", "pgup", "pgdn")
ACTION_KEY = {"backspace": "BACKSPACE", "del": "DEL", "esc": "ESC",
              "space": "SPACE", "enter": "ENTER", "ctrl": "CTRL", "alt": "ALT",
              "meta": "META", "tab": "TAB", "home": "HOME", "end": "END",
              "up": "UP", "down": "DOWN", "left": "LEFT", "right": "RIGHT",
              "pgup": "PAGEUP", "pgdn": "PAGEDOWN"}
# keycodes weston/xkb know but K did not list yet
K.update({"PAGEUP": 104, "PAGEDOWN": 109})

libc = ctypes.CDLL("libc.so.6", use_errno=True)


def rows(page):
    return PAGES[page]


def flat(page):
    """page rows -> one list padded so every row is the same width"""
    cols = max(len(r) for r in rows(page))
    out, n = [], 0
    for row in rows(page):
        row = list(row)
        while len(row) < cols:
            row.append("<pad>")
            n += 1
        out += row
    return out, cols


def resolve(sel):
    """what does a clicked grid entry mean?  Returns (kind, payload).

    A naive `sel.startswith("<")` test is wrong here: "<" is itself a key on the
    symbols page and would be read as an empty name.  Only a complete <word>
    counts as an action."""
    if sel == "<pad>":
        return "pad", sel
    if sel.startswith("<") and sel.endswith(">") and len(sel) > 2:
        name = sel[1:-1]
        if name in PAGES:
            return "page", name
        if name in ("shift", "caps"):
            return "mod", name
        if name == "quit":
            return "quit", name
        if name in ACTIONS:
            return "action", name
    return "char", sel


def display(sel):
    return LABEL.get(sel, sel)


def pipeline_stalled():
    """count kernel flip/vblank stall warnings since boot.

    On this board a nonzero count means commits stopped completing: the panel keeps
    showing a stale frame, so a brand new window is *invisible* while the compositor
    still looks healthy.  Worth saying out loud before asking anyone to click at a
    screen they cannot see."""
    try:
        out = subprocess.run(
            ["sh", "-c", "journalctl -b -k --no-pager 2>/dev/null | "
                         "grep -cE 'wait_for_vblanks|flip_done timed out|commit wait timed out'"],
            capture_output=True, text=True, timeout=40)
        return int((out.stdout or "0").strip().splitlines()[-1])
    except (ValueError, IndexError, OSError, subprocess.SubprocessError):
        return -1


class UinputError(Exception):
    pass


def ioctl_int(fd, req, arg):
    if libc.ioctl(fd, ctypes.c_ulong(req), ctypes.c_int(arg)) < 0:
        raise UinputError("ioctl %#x: %s" % (req, os.strerror(ctypes.get_errno())))


class Keyboard:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        try:
            ioctl_int(self.fd, UI_SET_EVBIT, EV_KEY)
            for code in K.values():
                ioctl_int(self.fd, UI_SET_KEYBIT, code)
        except UinputError as exc:
            os.close(self.fd)
            raise UinputError("UI_SET_*BIT: %s" % exc)
        rec = bytearray(RECORD_SIZE)
        rec[0:len(NAME)] = NAME
        struct.pack_into("<HHHH", rec, 80, 0x19, 0x484B, 0x1102, 0x0100)
        os.write(self.fd, bytes(rec))
        ioctl_int(self.fd, UI_DEV_CREATE, 0)
        time.sleep(0.15)                   # let weston add the device before typing

    def _ev(self, etype, code, value):
        os.write(self.fd, struct.pack("llHHi", 0, 0, etype, code, value))

    def hold(self, code, down):
        self._ev(EV_KEY, code, 1 if down else 0)
        self._ev(EV_SYN, 0, 0)

    def tap(self, code):
        self.hold(code, True)
        self.hold(code, False)

    def close(self):
        try:
            ioctl_int(self.fd, UI_DEV_DESTROY, 0)
        except Exception:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass


def send_char(kb, ch, latch=False, caps=False):
    """type one character; latch = SHFT was picked for the next key only"""
    if ch in K and len(ch) > 1:                # caller passed a key name, not text
        kb.tap(K[ch])
        return ch
    if ch == " ":
        kb.tap(K["SPACE"])
        return "SPC"
    if ch == "\n":
        kb.tap(K["ENTER"])
        return "RET"
    if ch == "\t":
        kb.tap(K["TAB"])
        return "TAB"
    base, shift = ch, bool(latch)
    if ch in SHIFTED:                      # '!' is Shift+1 whatever the latch says
        base, shift = SHIFTED[ch], True
    elif ch.isalpha() and (caps or ch.isupper()):
        shift = True
    code = K.get(base if base in K else base.lower())
    if code is None:
        return "skipped(%s)" % repr(ch)
    if shift:
        kb.hold(K["SHIFT"], True)
    kb.tap(code)
    if shift:
        kb.hold(K["SHIFT"], False)
    return ch


def wofi_cmd(page, prompt):
    entries, cols = flat(page)
    _, w, h = LAYOUT[page]
    return ["wofi", "--show", "dmenu", "--normal-window", "--columns", str(cols),
            "--width", str(w), "--height", str(h), "--hide-search", "--no-actions",
            "--style", CSS_PATH, "--prompt", prompt]


def wofi_grid(page, prompt, quiet=False, timeout=1800):
    """show one page, return the raw entry that was clicked.

    Returns None only when wofi really produced nothing (dismissed, or failed to
    start).  A timeout is *not* an exit - the old code treated 600 s of nobody
    clicking as "user quit", which silently killed the keyboard ten minutes into
    a test.  RETRY means: re-open the same page.
    """
    entries, _ = flat(page)
    try:
        out = subprocess.run(wofi_cmd(page, prompt),
                             input="\n".join(display(e) for e in entries) + "\n",
                             capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return RETRY
    except FileNotFoundError:
        print("  wofi is not installed", file=sys.stderr)
        return None
    sel = out.stdout.strip()
    if sel:
        labels = [display(e) for e in entries]
        try:
            return entries[labels.index(sel)]
        except ValueError:
            return sel                     # wofi echoed something unexpected
    if out.returncode and not quiet:
        # swallowing this is what made the first attempt look like "the user
        # dismissed the menu" when wofi had actually refused to start
        err = out.stderr.strip().splitlines()
        print("  wofi rc=%d: %s" % (out.returncode, err[-1] if err else "-"),
              file=sys.stderr)
    return None


def main():
    ap = argparse.ArgumentParser(description="joystick-driven on-screen keyboard")
    ap.add_argument("--start", choices=sorted(PAGES), default="letters")
    ap.add_argument("--type", metavar="TEXT", help="type TEXT and exit (no wofi)")
    ap.add_argument("--keys", metavar="NAMES",
                    help="inject named keys from /dev/uinput, comma separated, e.g. "
                         "DOWN,DOWN,ENTER - lets you drive a GUI from SSH and prove "
                         "which window really has keyboard focus")
    ap.add_argument("--hold", type=float, default=0.06, metavar="SEC",
                    help="how long --keys holds each key down (default 0.06)")
    ap.add_argument("--settle", type=float, default=0.15,
                    help="seconds to wait for weston to restore focus (default .15)")
    ap.add_argument("--pick-timeout", type=int, default=1800,
                    help="re-open the grid after this many idle seconds (default 1800)")
    ap.add_argument("--list", action="store_true", help="print the pages and exit")
    ap.add_argument("--dry-run", action="store_true",
                    help="show the wofi command line, do not touch uinput")
    ap.add_argument("--probe-grid", type=float, metavar="SECS",
                    help="show one page for SECS and report whether wofi stayed up "
                         "(no uinput): rc=124-equivalent means the grid really maps")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    if args.list:
        for name in sorted(PAGES):
            entries, cols = flat(name)
            print("%-8s %d keys, %d columns" % (name, len(entries), cols))
            row = []
            for i, e in enumerate(entries):
                row.append("%4s" % display(e))
                if (i + 1) % cols == 0:
                    print("   " + " ".join(row))
                    row = []
            if row:
                print("   " + " ".join(row))
        return 0
    if args.dry_run:
        for name in sorted(PAGES):
            print("  " + " ".join(repr(a) for a in wofi_cmd(name, "prompt")))
        return 0

    os.environ.setdefault("XDG_RUNTIME_DIR", "/run/wayland")
    os.environ.setdefault("WAYLAND_DISPLAY", "wayland-0")
    if not os.path.exists("/dev/uinput"):
        print("  /dev/uinput is not available", file=sys.stderr)
        return 2
    try:
        with open(CSS_PATH, "w") as fh:
            fh.write(CSS)
    except OSError as exc:
        print("  !! cannot write %s: %s" % (CSS_PATH, exc), file=sys.stderr)

    if args.probe_grid:
        entries, cols = flat(args.start)
        cmd = wofi_cmd(args.start, "probe %s" % args.start)
        try:
            out = subprocess.run(cmd,
                                 input="\n".join(display(e) for e in entries) + "\n",
                                 capture_output=True, text=True, timeout=args.probe_grid)
        except subprocess.TimeoutExpired:
            print("  ok: %s grid mapped and waited %ds for a click (%d cells, %d cols)"
                  % (args.start, int(args.probe_grid), len(entries), cols))
            return 0
        print("  !! %s grid exited after one key with rc=%d stdout=%r"
              % (args.start, out.returncode, out.stdout[:40]))
        for line in (out.stderr or "").strip().splitlines():
            if "AT-SPI" not in line:
                print("     stderr: %s" % line[-120:])
        return 1

    try:
        kb = Keyboard()
    except (UinputError, OSError) as exc:
        print("  !! uinput: %s" % exc, file=sys.stderr)
        return 2
    try:
        if args.type is not None:
            for ch in args.type:
                shown = send_char(kb, ch)
                if args.verbose:
                    print("  sent %s" % shown)
            print("  typed %d characters through /dev/uinput" % len(args.type))
            return 0
        if args.keys is not None:
            names = [n.strip().upper() for n in args.keys.split(",") if n.strip()]
            done = 0
            bad = []
            for nm in names:
                nm2 = ALIAS.get(nm, nm)
                if nm2 not in K:
                    bad.append(nm)
                    continue
                kb.hold(K[nm2], True)
                time.sleep(0.06)               # hold it a moment: some clients poll
                kb.hold(K[nm2], False)
                done += 1
                if args.verbose:
                    print("  tapped %s%s" % (nm2, "" if nm2 == nm else " (as %s)" % nm))
                time.sleep(0.09)
            print("  injected %d/%d key presses through /dev/uinput" % (done, len(names)))
            if bad:
                # Exit non-zero.  A harness that only looks at "did the command run" would
                # otherwise record a mistyped key name as "the application ignored input".
                print("  !! unknown key name(s): %s   (known: %s)"
                      % (" ".join(bad), " ".join(sorted(K))), file=sys.stderr)
                return 2
            return 0
        page, latch, caps, n = args.start, False, False, 0
        stall = pipeline_stalled()
        if stall > 0:
            print("  !! %d flip/vblank stall messages in the kernel since boot: the panel is" % stall)
            print("     probably frozen on an old frame, so this grid may not be visible.")
            print("     `systemctl restart weston` first; if that does not help only a reboot")
            print("     recovers it (measured on this board).")
        elif stall < 0:
            print("  (kernel log unreadable - cannot tell whether the panel is live)")
        print("  r36-osk up.  The grid holds keyboard focus, so the joystick keys work")
        print("  directly:  D-pad = move highlight,  START = pick that key,")
        print("             SELECT = cancel,  A/left-click also picks what is under")
        print("  the pointer.  Page keys ABC / #!? / nav switch pages, X quits.")
        sys.stdout.flush()
        while True:
            state = " ".join(x for x in ("SHFT" if latch else "", "CAPS" if caps else "") if x)
            sel = wofi_grid(page, "r36-osk %s %s #%d | dpad=move START=pick" % (page, state, n),
                            timeout=args.pick_timeout)
            if sel is None:
                break
            if sel == RETRY:
                print("  nobody clicked for %ds - reopening the grid (not an exit)"
                      % args.pick_timeout)
                sys.stdout.flush()
                continue
            kind, payload = resolve(sel)
            if kind in ("quit", "pad"):
                if kind == "quit":
                    break
                continue
            if kind == "page":
                page = payload
                continue
            if kind == "mod":
                if payload == "shift":
                    latch, caps = not latch, False
                else:
                    caps, latch = not caps, False
                on = latch if payload == "shift" else caps
                print("  %s %s" % (payload, "on" if on else "off"))
                sys.stdout.flush()
                continue
            time.sleep(args.settle)          # let weston hand focus back to foot
            if kind == "action":
                kb.tap(K[ACTION_KEY[payload]])
                shown = LABEL.get(sel, payload)
            else:
                shown = send_char(kb, payload, latch=latch, caps=caps)
                latch = False
            n += 1
            print("  [%3d] %s" % (n, shown))
            sys.stdout.flush()
        print("  r36-osk closed after %d keystrokes" % n)
        return 0
    finally:
        kb.close()


if __name__ == "__main__":
    sys.exit(main())
