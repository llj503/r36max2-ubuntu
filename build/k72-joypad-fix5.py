#!/usr/bin/env python3
"""k72-joypad-fix5.py - the 5b regex stopped at the first `\t\t}` (the end of the
`if (gpio->num < 0)` block) and so left the original body behind.  Delete the
leftover span: from the OF_GPIO_ACTIVE_LOW line through the closing brace of the
gpio_is_valid() block, then build against BOTH kernels."""
import re
import subprocess

P = "/root/r36/k72joypad/rocknix-joypad.c"
lines = open(P, encoding="utf-8", errors="replace").read().split("\n")

a = next((n for n, l in enumerate(lines) if "OF_GPIO_ACTIVE_LOW" in l), None)
if a is None:
    print("[5b] nothing to clean - already fine")
else:
    g = next((n for n in range(a, len(lines)) if "gpio_is_valid(gpio->num)" in lines[n]), None)
    b = None
    if g is not None:
        for n in range(g, min(g + 20, len(lines))):
            if lines[n] == "\t\t}":
                b = n
                break
    if b is None:
        print(f"[5b] FAILED to bound the leftover (a={a}, g={g}) - not touching the file")
    else:
        print(f"[5b] deleting leftover lines {a+1}-{b+1}:")
        for l in lines[a:b + 1]:
            print("      |" + l.rstrip())
        del lines[a:b + 1]
        open(P, "w", encoding="utf-8").write("\n".join(lines))

text = "\n".join(lines)
left = [l.strip() for l in text.split("\n")
        if re.search(r"gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio"
                     r"|devm_gpio_request|OF_GPIO_|gpio->num|of_gpio_flags|gpio_direction_output", l)]
print(f"=== remaining legacy GPIO references: {len(left)} ===")
for l in left:
    print("   ", l[:130])

print("=== the converted button setup loop ===")
m = re.search(r"\tfor \(;.*?of_node\).*?\n\t\}", text, re.S)
seg = re.search(r"static int joypad_gpio_setup\(.*?\n\}", text, re.S)
print(seg.group(0)[-1500:] if seg else "  not found")
