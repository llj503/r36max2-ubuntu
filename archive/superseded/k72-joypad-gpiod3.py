#!/usr/bin/env python3
"""k72-joypad-gpiod3.py - remove the two leftovers from the line surgery (a
duplicated poll read and the rumble request_one block), show the final regions,
and build against BOTH kernels."""
import re
import subprocess

P = "/root/r36/k72joypad/rocknix-joypad.c"
lines = open(P, encoding="utf-8", errors="replace").read().split("\n")

# 1. stale duplicate poll read
before = len(lines)
lines = [l for l in lines if "gpio_get_value_cansleep(gpio->num)" not in l]
print(f"[1] dropped {before - len(lines)} stale poll line(s)")

# 2. the leftover devm_gpio_request_one block for rumble
i = next((n for n, l in enumerate(lines)
          if "devm_gpio_request_one(dev, joypad->rumble_gpio" in l), None)
if i is not None:
    # walk back to the enclosing `if (` line
    start = i
    while start > 0 and not lines[start].strip().startswith("if ("):
        start -= 1
    depth = 0
    end = start
    for n in range(start, len(lines)):
        depth += lines[n].count("{") - lines[n].count("}")
        if "{" in lines[n] and depth == 0:
            end = n
            break
    print(f"[2] removing rumble request block, lines {start+1}-{end+1}:")
    for l in lines[start:end + 1]:
        print("      " + l.rstrip())
    del lines[start:end + 1]
else:
    print("[2] no leftover request_one block")

s = "\n".join(lines)
open(P, "w", encoding="utf-8").write(s)
left = [l.strip() for l in lines
        if re.search(r"gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio|devm_gpio_request|OF_GPIO_|gpio->num|of_gpio_flags", l)]
print(f"=== remaining legacy references: {len(left)} ===")
for l in left:
    print("   ", l[:130])

print("=== final poll function ===")
m = re.search(r"static void joypad_gpio_check\(.*?\n\}", s, re.S)
print(m.group(0) if m else "  not found")
print("=== final button setup ===")
m = re.search(r"gpio->label = of_get_property\(pp.*?\n\t\t\}", s, re.S)
print(m.group(0)[:900] if m else "  not found")
print("=== final rumble acquisition ===")
m = re.search(r"joypad->rumble_gpio = devm_gpiod_get_optional.*?\n\t\}", s, re.S)
print(m.group(0) if m else "  not found")
