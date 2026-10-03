#!/usr/bin/env python3
"""k72-joypad-fix7.py - repair the last split string literal in the poll loop and
print the converted regions for review."""
P = "/root/r36/k72joypad/rocknix-joypad.c"
s = open(P, encoding="utf-8", errors="replace").read()

broken = '\t\t\tdev_err(joypad->dev, "failed to get gpio state\n");'
fixed = '\t\t\tdev_err(joypad->dev, "failed to get gpio state\\n");'
n = s.count(broken)
s = s.replace(broken, fixed)
print(f"[fix] repaired {n} split literal(s)")
open(P, "w", encoding="utf-8").write(s)

bad = [(i + 1, l) for i, l in enumerate(s.split("\n"))
       if l.count('"') % 2 == 1 and not l.rstrip().endswith(("\\", ",", "(", '"'))]
print(f"=== suspicious lines now: {len(bad)} ===")
for k, l in bad[:6]:
    print(f"   {k}: {l.strip()[:110]}")

lines = s.split("\n")
def show(tag, anchor, span=26):
    i = next((k for k, l in enumerate(lines) if anchor in l), None)
    print(f"=== {tag} (line {i+1 if i is not None else '?'}) ===")
    if i is None:
        return
    for l in lines[i:i + span]:
        print("   |" + l.rstrip())
        if l.strip() == "}" and "for_each" not in l:
            pass
    print()

show("poll function", "static void joypad_gpio_check(", 24)
show("button loop", "for_each_child_of_node(node, pp)", 22)
show("rumble in probe", "devm_gpiod_get_optional(dev, \"rumble\"", 12)
show("vibrator start", "static int joypad_vibrator_start", 10)
