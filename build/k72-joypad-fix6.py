#!/usr/bin/env python3
"""k72-joypad-fix6.py - two problems left:
 (a) re.subn un-escaped the `\\n` I wrote in replacement strings, so three
     dev_err() literals contain a REAL newline instead of \n (won't compile);
 (b) `gpio->label = of_get_property(pp, "label", NULL);` was inside the span I
     deleted, but the gpiod call uses gpio->label -> restore it before the call.
Then build against 7.2.8 and 6.12.79.
"""
import re
import subprocess

P = "/root/r36/k72joypad/rocknix-joypad.c"
s = open(P, encoding="utf-8", errors="replace").read()

fixes = [
    ('dev_err(dev, "Failed to get gpio, error: %d\n\t\t\t\t, error);',
     'dev_err(dev, "Failed to get gpio, error: %d\\n", error);'),
    ('dev_err(dev, "Failed to get gpio, error: %d", error);',
     'dev_err(dev, "Failed to get gpio, error: %d\\n", error);'),
    ('dev_err(dev, "Button without keycode: 0x%x\n", (unsigned)nbtn);',
     'dev_err(dev, "Button without keycode: 0x%x\\n", (unsigned)nbtn);'),
    ('dev_err(joypad->dev, "failed to get gpio state\n\t\t\t);',
     'dev_err(joypad->dev, "failed to get gpio state\\n");'),
]
before = s
for pat, rep in fixes:
    s = s.replace(pat, rep)

# generic sweep: any string literal that ends a line without a closing quote and
# whose next line starts with the continuation of a dev_err arg list
s = re.sub(r'"((?:[^"\\\n]|\\.)*?%[dx])\n(\s*)", ', r'"\1\\n", ', s)
s = re.sub(r'"((?:[^"\\\n]|\\.)*?%[dx])\n(\s*)"\);', r'"\1\\n");', s)
s = re.sub(r'"((?:[^"\\\n]|\\.)*?%d)\n"\s*,', r'"\1\\n",', s)
s = re.sub(r'"((?:[^"\\\n]|\\.)*?0x%x)\n"(\s*),', r'"\1\\n",\2', s)

# (b) restore the label lookup before it is used
s = s.replace(
    "\t\t/* gpiod honours the DT polarity: asserted is always logical 1 */\n",
    "\t\tgpio->label = of_get_property(pp, \"label\", NULL);\n\n"
    "\t\t/* gpiod honours the DT polarity: asserted is always logical 1 */\n",
    1)
open(P, "w", encoding="utf-8").write(s)

print("=== unterminated string literals still present? ===")
bad = [(i + 1, l) for i, l in enumerate(s.split("\n"))
       if l.count('"') % 2 == 1 and not l.rstrip().endswith(("\\", ",", "(", '"'))]
for n, l in bad[:8]:
    print(f"   line {n}: {l.strip()[:110]}")
print(f"   ({len(bad)} suspicious line(s))")

print("=== the converted loop, final form ===")
m = re.search(r"\tfor_each_child_of_node\(node, pp\) \{.*?\n\t\}\n\t\}", s, re.S)
print(m.group(0)[:1200] if m else "  not found")
