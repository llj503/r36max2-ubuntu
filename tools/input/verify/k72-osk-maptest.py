#!/usr/bin/env python3
"""k72-osk-maptest.py - offline check of r36-osk's key mapping: no uinput, no wofi.
Feeds every grid entry through resolve()/send_char()/the action table and records
the raw event stream, so a mapping bug shows up here instead of on the panel."""
import importlib.util
import sys

for path in ("/mnt/e/ubuntu/packages/r36-osk/r36-osk.py", "E:\\ubuntu\\build\\r36-osk.py",
             r"E:/ubuntu/build/r36-osk.py"):
    try:
        spec = importlib.util.spec_from_file_location("osk", path)
        osk = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(osk)
        break
    except (FileNotFoundError, OSError, ImportError) as exc:
        last = exc
else:
    print("  !! cannot import r36-osk.py: %s" % last)
    sys.exit(2)

log = []


class FakeKB:
    def _ev(self, etype, code, value):
        log.append((etype, code, value))

    def hold(self, code, down):
        self._ev(osk.EV_KEY, code, 1 if down else 0)

    def tap(self, code):
        self.hold(code, True)
        self.hold(code, False)

    def close(self):
        pass


def decode(seq):
    """turn (type,code,value) pairs back into the characters a client would see"""
    by_code = {v: k for k, v in osk.K.items()}
    shiftmap = {"1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^",
                "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
                "[": "{", "]": "}", "\\": "|", ";": ":", "'": '"', "`": "~",
                ",": "<", ".": ">", "/": "?"}
    shift, out = 0, []
    for et, code, val in seq:
        if et != osk.EV_KEY:
            continue
        name = by_code.get(code, "?%d" % code)
        if name == "SHIFT":
            shift = val
            continue
        if val == 1:
            out.append(shiftmap.get(name, name.upper()) if shift else name)
    return "".join(out)


bad = 0
kb = FakeKB()

# 0) entries and their labels must be unique per page - wofi_grid() maps a clicked
#    label back with .index(), so a duplicate resolves to the first match
for page in sorted(osk.PAGES):
    entries, cols = osk.flat(page)
    real = [e for e in entries if e != "<pad>"]
    labels = [osk.display(e) for e in real]
    for what, seq in (("entry", real), ("label", labels)):
        dupes = sorted({x for x in seq if seq.count(x) > 1})
        if dupes:
            print("  !! page=%s duplicate %ss: %s" % (page, what, dupes))
            bad += 1
    if len(entries) % cols:
        print("  !! page=%s is not a whole number of rows" % page)
        bad += 1

# 1) every entry on every page must produce events, never "skipped"
for page in sorted(osk.PAGES):
    entries, _ = osk.flat(page)
    for entry in entries:
        del log[:]
        kind, payload = osk.resolve(entry)
        if kind in ("page", "mod", "quit", "pad"):
            continue
        if kind == "action":
            kb.tap(osk.K[osk.ACTION_KEY[payload]])
            shown = osk.LABEL.get(entry, payload)
        else:
            shown = osk.send_char(kb, payload)
        if "skipped" in str(shown) or not log:
            print("  !! page=%s entry=%s kind=%s -> %s (no keycode)" % (page, repr(entry), kind, shown))
            bad += 1

# 2) shift latch / caps semantics
del log[:]; osk.send_char(kb, "a"); plain = decode(log)
del log[:]; osk.send_char(kb, "a", latch=True); latched = decode(log)
del log[:]; osk.send_char(kb, "a", caps=True); capped = decode(log)
del log[:]; osk.send_char(kb, "2", latch=True); at = decode(log)
del log[:]; osk.send_char(kb, "!"); bang = decode(log)
del log[:]; osk.send_char(kb, "_"); under = decode(log)
del log[:]; osk.send_char(kb, " "); space = decode(log)
del log[:]; osk.send_char(kb, "\n"); enter = decode(log)
for name, got, want in [("a", plain, "a"), ("A(latch)", latched, "A"),
                        ("A(caps)", capped, "A"), ("@(latch2)", at, "@"),
                        ("!", bang, "!"), ("_", under, "_"),
                        ("space", space, "SPACE"), ("newline", enter, "ENTER")]:
    ok = got == want
    print("  %-10s -> %-6s %s" % (name, got, "ok" if ok else "!! want " + want))
    bad += 0 if ok else 1

# 3) entries that look like actions but are keys must still resolve to keys
for sel, want in [("<", ("char", "<")), (">", ("char", ">")),
                  ("<backspace>", ("action", "backspace")),
                  ("<letters>", ("page", "letters")),
                  ("<shift>", ("mod", "shift")), ("<quit>", ("quit", "quit")),
                  ("<pad>", ("pad", "<pad>"))]:
    got = osk.resolve(sel)
    ok = got == want
    print("  resolve(%-14s) -> %-26s %s" % (repr(sel), str(got), "ok" if ok else "!! want %s" % (want,)))
    bad += 0 if ok else 1

# 4) pages must fit the 1024x768 panel with cells big enough for a thumb pointer
for page in sorted(osk.PAGES):
    entries, cols = osk.flat(page)
    _, w, h = osk.LAYOUT[page]
    rws = len(entries) // cols
    cellw, cellh = w / cols, (h - 50.0) / rws
    print("  %-8s %2d cells -> %2d x %2d, cell %.0fx%.0f px  %s" % (
        page, len(entries), cols, rws, cellw, cellh,
        "ok" if w <= 1024 and h <= 768 and cellw >= 55 and cellh >= 40 else "!! too small/big"))
    if not (w <= 1024 and h <= 768 and cellw >= 55 and cellh >= 40):
        bad += 1

# 5) the wofi command line must be the one proven to stay up on the device
cmd = " ".join(osk.wofi_cmd("letters", "p"))
print("  cmd: " + cmd)
for need in ("--show dmenu", "--normal-window", "--columns", "--hide-search", "--style"):
    if need not in cmd:
        print("  !! missing %s" % need)
        bad += 1

print("=== maptest: %s ===" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
