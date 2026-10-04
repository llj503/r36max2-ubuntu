#!/usr/bin/env python3
"""k72-joypad-gpiod2.py - finish the gpiod conversion with line/brace surgery
(the remaining four regions failed the whitespace-exact regexes).
Operates on the working copy that k72-joypad-gpiod.py already partly converted.
"""
import re

P = "/root/r36/k72joypad/rocknix-joypad.c"
lines = open(P, encoding="utf-8", errors="replace").read().split("\n")

def find(pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    return -1

def block_end(i):
    """index of the line closing the brace opened on/before line i"""
    depth = 0
    started = False
    while i < len(lines):
        depth += lines[i].count("{") - lines[i].count("}")
        if "{" in lines[i]:
            started = True
        if started and depth == 0:
            return i
        i += 1
    return -1

changed = []

# ---- 1. poll loop -------------------------------------------------------
i = find(lambda l: "gpio_get_value_cansleep(gpio->num) < 0" in l)
assert i > 0, "poll guard not found"
j = find(lambda l: l.strip().startswith("value = gpio_get_value_cansleep(gpio->num)"), i)
assert j > 0
# the guard block is: if (...) { dev_err; continue; }  -> 3 lines after the if
end = block_end(i)
new = [
    "\t\tif (!gpio->desc)",
    "\t\t\tcontinue;",
    "\t\tvalue = gpiod_get_value_cansleep(gpio->desc);",
    "\t\tif (value < 0) {",
    "\t\t\tdev_err(joypad->dev, \"failed to get gpio state\\n\");",
    "\t\t\tcontinue;",
    "\t\t}",
]
lines[i:end + 1] = new
changed.append(f"poll block (lines {i+1}-{end+1})")

# ---- 2. button setup: of_get_gpio_flags .. request_one ------------------
i = find(lambda l: "gpio->num = of_get_gpio_flags(pp, 0, &flags);" in l)
assert i > 0, "setup not found"
# find the end of the "if (gpio_is_valid(gpio->num)) {" block
k = find(lambda l: "if (gpio_is_valid(gpio->num))" in l, i)
assert k > 0
end = block_end(k)
new = [
    "\t\tgpio->label = of_get_property(pp, \"label\", NULL);",
    "",
    "\t\t/* gpiod honours the DT polarity: asserted is always logical 1 */",
    "\t\tgpio->active_level = true;",
    "\t\tgpio->desc = devm_fwnode_gpiod_get_index(dev, of_fwnode_handle(pp),",
    "\t\t\t\t\t\t\t \"gpios\", 0, GPIOD_IN,",
    "\t\t\t\t\t\t\t gpio->label ? gpio->label : \"button\");",
    "\t\tif (IS_ERR(gpio->desc)) {",
    "\t\t\terror = PTR_ERR(gpio->desc);",
    "\t\t\tif (error != -ENOENT && error != -ENOSYS) {",
    "\t\t\t\tdev_err(dev, \"Failed to get gpio, error: %d\\n\", error);",
    "\t\t\t\treturn error;",
    "\t\t\t}",
    "\t\t\tgpio->desc = NULL;",
    "\t\t}",
]
# the label assignment already exists before the gpio_is_valid block; replace the
# whole span from of_get_gpio_flags through the end of that if-block
lines[i:end + 1] = new
changed.append(f"button setup block (lines {i+1}-{end+1})")

# ---- 3. the dev_err that printed gpio->num ------------------------------
i = find(lambda l: "Button without keycode" in l)
if i > 0 and "gpio->num" in lines[i + 1]:
    lines[i + 1] = lines[i + 1].replace("gpio->num", "(unsigned)nbtn")
    changed.append("Button-without-keycode arg")

# ---- 4. probe: rumble-gpio ----------------------------------------------
i = find(lambda l: "of_get_named_gpio_flags(dev->of_node, \"rumble-gpio\"" in l)
assert i > 0, "rumble probe not found"
k = find(lambda l: "if (gpio_is_valid(joypad->rumble_gpio))" in l, i)
end = block_end(k) if k > 0 else i
new = [
    "\tjoypad->rumble_gpio = devm_gpiod_get_optional(dev, \"rumble\", GPIOD_OUT_LOW);",
    "\tif (IS_ERR(joypad->rumble_gpio)) {",
    "\t\tdev_err(dev, \"Failed to get rumble gpio, error: %ld\\n\",",
    "\t\t\tPTR_ERR(joypad->rumble_gpio));",
    "\t\tjoypad->rumble_gpio = NULL;\t/* vibration is optional */",
    "\t}",
]
lines[i:end + 1] = new
changed.append(f"rumble acquisition (lines {i+1}-{end+1})")

# ---- 5. drop the now-unused enum of_gpio_flags declaration --------------
i = find(lambda l: l.strip() == "enum of_gpio_flags flags;")
if i > 0:
    del lines[i]
    changed.append("unused enum of_gpio_flags declaration")

open(P, "w", encoding="utf-8").write("\n".join(lines))
print("changed:")
for c in changed:
    print("   ", c)

s = "\n".join(lines)
left = [l.strip() for l in lines
        if re.search(r"gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio|devm_gpio_request|OF_GPIO_|gpio->num|of_gpio_flags", l)]
print(f"=== remaining legacy references: {len(left)} ===")
for l in left[:10]:
    print("   ", l[:130])
