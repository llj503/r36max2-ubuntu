#!/usr/bin/env python3
"""k72-joypad-fixesc.py - repair the escape damage from re.sub replacements:
(a) `\"` that should be plain quotes, (b) string literals whose \\n turned into a
real newline.  Verified against the pristine source: it contains no `\\"` at all,
so the global fix is safe.
"""
import re
import subprocess

FILES = ["/root/r36/joypad/src/rocknix-joypad.c",
         "/root/r36/joypad/src/rocknix-singleadc-joypad.c"]
pristine = "".join(open(f, encoding="utf-8", errors="replace").read() for f in FILES)
print(f"pristine sources contain {pristine.count(chr(92)+chr(34))} backslash-quote sequence(s)")

for p in ["/root/r36/k72joypad/rocknix-joypad.c",
          "/root/r36/k72joypad/rocknix-singleadc-joypad.c"]:
    s = open(p, encoding="utf-8", errors="replace").read()
    n1 = s.count('\\"')
    s = s.replace('\\"', '"')
    # split literals: "...%d\n<newline>", ...)  ->  "...%d\\n", ...)
    n2 = len(re.findall(r'%[dx]\n"', s))
    s = re.sub(r'(%[dx])\n(")', r'\1\\n\2', s)
    # also:  "...%ld\n", __func__,  spread over two lines
    n3 = len(re.findall(r'%ld\n"', s))
    open(p, "w", encoding="utf-8").write(s)
    print(f"{p.split('/')[-1]}: fixed {n1} escaped quotes, {n2} split literals")

# show the repaired regions
for p in ["/root/r36/k72joypad/rocknix-joypad.c",
          "/root/r36/k72joypad/rocknix-singleadc-joypad.c"]:
    s = open(p, encoding="utf-8", errors="replace").read()
    print(f"=== {p.split('/')[-1]}: inserted blocks ===")
    for m in re.finditer(r"dev_err\(dev, \"[^\"]*\\n\"[^\n]*\n[^\n]*\n?", s):
        if "failed to get" in m.group(0) or "Failed to get gpio" in m.group(0):
            print("   " + m.group(0).rstrip().replace("\n", "\n   "))
    bad = [(i + 1, l) for i, l in enumerate(s.split("\n"))
           if l.count('"') % 2 == 1 and not l.rstrip().endswith(("\\", ",", "(", '"'))]
    print(f"   suspicious lines: {len(bad)}")
    for k, l in bad[:4]:
        print(f"     {k}: {l.strip()[:110]}")
