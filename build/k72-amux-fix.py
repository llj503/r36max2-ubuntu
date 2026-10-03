#!/usr/bin/env python3
"""k72-amux-fix.py - `int sel_a_gpio, sel_b_gpio;` declares two fields on one
line, so the per-field regex only caught en_gpio.  Convert the pair, then build
against both kernels."""
import subprocess

p = "/root/r36/k72joypad/rocknix-singleadc-joypad.c"
s = open(p, encoding="utf-8", errors="replace").read()
old = "\tint sel_a_gpio, sel_b_gpio;"
new = "\tstruct gpio_desc *sel_a_gpio, *sel_b_gpio;"
n = s.count(old)
s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
print(f"converted the sel_a/sel_b pair: {n} site(s)")
i = s.find("struct analog_mux {")
print(s[i:i + 240])
