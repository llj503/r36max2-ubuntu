#!/usr/bin/env python3
"""k72-joypad-fixsoh.py - Python read the `\\1` in a non-raw replacement string as
an octal escape and wrote literal SOH (\\x01) bytes into the source.  Replace them
with the variable they were meant to be, then build against both kernels."""
import subprocess

for p, var in [("/root/r36/k72joypad/rocknix-joypad.c", "joypad->rumble_gpio"),
               ("/root/r36/k72joypad/rocknix-singleadc-joypad.c", "joypad->rumble_gpio")]:
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    n = s.count("\x01")
    s = s.replace("\x01", var)
    open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
    print(f"{p.split('/')[-1]}: replaced {n} SOH byte(s) with {var}")
    for line in s.split("\n"):
        if "rumble_gpio = devm_gpiod" in line or "IS_ERR(joypad->rumble_gpio)" in line \
           or "PTR_ERR(joypad->rumble_gpio)" in line or "rumble_gpio = NULL" in line:
            print("   ", line.strip()[:110])
