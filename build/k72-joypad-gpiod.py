#!/usr/bin/env python3
"""k72-joypad-gpiod.py - convert rocknix-joypad.c from the (removed) legacy
integer GPIO API to the gpiod consumer API.

Why rewrite instead of carrying Rocknix's gpiolib-revert patch: 7.x deleted
include/linux/of_gpio.h AND the whole integer API (gpio_get_value_cansleep,
gpio_is_valid, devm_gpio_request_one), so the revert patch has nothing to patch.
All the gpiod helpers used here are exported by BOTH 6.12.79 and 7.2.8, so this
one source builds on both kernels and the revert patch becomes unnecessary.

Polarity note: gpiod applies the DT ACTIVE_LOW flag, so a "pressed" button reads
1 and rumble writes become logical.  The DT says rumble is ACTIVE_LOW, so if the
motor behaves inverted the DT flag is what needs fixing, not the driver.
"""
import re
import shutil
import subprocess
import sys

SRC = "/root/r36/joypad/src"
WORK = "/root/r36/k72joypad"
F = "rocknix-joypad.c"

shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree(SRC, WORK)
# drop build artifacts so the diff later is source-only
for junk in subprocess.run(f"find {WORK} -name '*.o' -o -name '*.ko' -o -name '*.mod*' "
                           f"-o -name '.*.cmd' -o -name Module.symvers -o -name modules.order",
                           shell=True, capture_output=True, text=True).stdout.split():
    try:
        import os
        os.remove(junk)
    except OSError:
        pass

p = f"{WORK}/{F}"
s = open(p, encoding="utf-8", errors="replace").read()
orig = s
report = []

def sub(pattern, repl, note, flags=0, count=1):
    global s
    new, n = re.subn(pattern, repl, s, count=count, flags=flags)
    report.append(f"  {'OK  ' if n else 'MISS'} x{n}  {note}")
    s = new

# 1. includes: of_gpio.h / of_gpio_legacy.h -> gpio/consumer.h
sub(r"#if \(LINUX_VERSION_CODE < KERNEL_VERSION\(6, 3, 0\)\)\n"
    r"#include <linux/of_gpio\.h>\n#else\n"
    r"#include <linux/of_gpio_legacy\.h>\n#endif\n",
    "#include <linux/gpio/consumer.h>\n",
    "includes: of_gpio* -> gpio/consumer.h")

# 2. bt_gpio: int num -> struct gpio_desc *desc
sub(r"/\* GPIO Number \*/\n\tint num;",
    "/* GPIO descriptor */\n\tstruct gpio_desc *desc;",
    "struct bt_gpio: int num -> gpio_desc *desc")
sub(r"\tint rumble_gpio;", "\tstruct gpio_desc *rumble_gpio;",
    "struct joypad: int rumble_gpio -> gpio_desc *")

# 3. vibrator start/stop
sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\) \{\n\t\tgpio_set_value\(joypad->rumble_gpio, 1\);",
    "if (joypad->rumble_gpio) {\n\t\tgpiod_set_value_cansleep(joypad->rumble_gpio, 1);",
    "vibrator start: gpiod_set_value_cansleep")
sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\) \{\n\t\tgpio_set_value\(joypad->rumble_gpio, 0\);",
    "if (joypad->rumble_gpio) {\n\t\tgpiod_set_value_cansleep(joypad->rumble_gpio, 0);",
    "vibrator stop: gpiod_set_value_cansleep")
sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\)",
    "if (joypad->rumble_gpio)", "remaining rumble gpio_is_valid guards", count=0)

# 4. poll loop
sub(r"\t\tif \(gpio_get_value_cansleep\(gpio->num\) < 0\) \{\n"
    r"\t\t\tdev_err\(joypad->dev, \"failed to get gpio state\\\\n\"\);\n"
    r"\t\t\tcontinue;\n\t\t\}\n"
    r"\t\tvalue = gpio_get_value_cansleep\(gpio->num\);",
    "\t\tif (!gpio->desc)\n\t\t\tcontinue;\n"
    "\t\tvalue = gpiod_get_value_cansleep(gpio->desc);\n"
    "\t\tif (value < 0) {\n"
    "\t\t\tdev_err(joypad->dev, \"failed to get gpio state\\n\");\n"
    "\t\t\tcontinue;\n\t\t}",
    "poll: gpio_get_value_cansleep -> gpiod_get_value_cansleep")

# 5. button setup loop
sub(r"\t\tenum of_gpio_flags flags;\n\t\tstruct bt_gpio \*gpio = &joypad->gpios\[nbtn\+\+\];",
    "\t\tstruct bt_gpio *gpio = &joypad->gpios[nbtn++];",
    "setup: drop enum of_gpio_flags")
sub(r"\t\tgpio->num = of_get_gpio_flags\(pp, 0, &flags\);\n"
    r"\t\tif \(gpio->num < 0\) \{\n\t\t\terror = gpio->num;\n"
    r"\t\t\tdev_err\(dev, \"Failed to get gpio flags, error: %d\\\\n\",\n"
    r"\t\t\t\terror\);\n\t\t\treturn error;\n\t\t\}\n\n"
    r"\t\t/\* gpio active level\(key press level\) \*/\n"
    r"\t\tgpio->active_level = \(flags & OF_GPIO_ACTIVE_LOW\) \? 0 : 1;\n\n"
    r"\t\tgpio->label = of_get_property\(pp, \"label\", NULL\);\n\n"
    r"\t\tif \(gpio_is_valid\(gpio->num\)\) \{\n"
    r"\t\t\terror = devm_gpio_request_one\(dev, gpio->num,\n"
    r"\t\t\t\t\t\t      GPIOF_IN, gpio->label\);\n"
    r"\t\t\tif \(error < 0\) \{\n"
    r"\t\t\t\tdev_err\(dev,\n"
    r"\t\t\t\t\t\"Failed to request GPIO %d, error %d\\\\n\",\n"
    r"\t\t\t\t\tgpio->num, error\);\n"
    r"\t\t\t\treturn error;\n\t\t\t\}\n\t\t\}",
    "\t\tgpio->label = of_get_property(pp, \"label\", NULL);\n\n"
    "\t\t/* gpiod honours the DT polarity: asserted is always logical 1 */\n"
    "\t\tgpio->active_level = true;\n"
    "\t\tgpio->desc = devm_fwnode_gpiod_get_index(dev, of_fwnode_handle(pp),\n"
    "\t\t\t\t\t\t\t \"gpios\", 0, GPIOD_IN,\n"
    "\t\t\t\t\t\t\t gpio->label ? gpio->label : \"button\");\n"
    "\t\tif (IS_ERR(gpio->desc)) {\n"
    "\t\t\terror = PTR_ERR(gpio->desc);\n"
    "\t\t\tif (error != -ENOENT && error != -ENOSYS) {\n"
    "\t\t\t\tdev_err(dev, \"Failed to get gpio, error: %d\\n\", error);\n"
    "\t\t\t\treturn error;\n\t\t\t}\n"
    "\t\t\tgpio->desc = NULL;\n\t\t}",
    "setup: of_get_gpio_flags + request_one -> devm_fwnode_gpiod_get_index")
sub(r"\"Button without keycode: 0x%x\\\\n\",\n\t\t\t\tgpio->num\)",
    "\"Button without keycode: 0x%x\\n\", (unsigned)nbtn)",
    "setup: dev_err no longer uses gpio->num")

# 6. rumble acquisition in probe
sub(r"\tjoypad->rumble_gpio = of_get_named_gpio_flags\(dev->of_node, \"rumble-gpio\", 0, &flags\);\n"
    r"\tif \(gpio_is_valid\(joypad->rumble_gpio\)\) \{\n"
    r"\t\terror = devm_gpio_request_one\(dev, joypad->rumble_gpio, GPIOF_IN, \"rumble-gpio\"\);\n"
    r"\t\tif \(error < 0\) \{\n"
    r"\t\t\tdev_err\(dev, \"Failed to request rumble gpio, error: %d\\\\n\",\n"
    r"\t\t\t\t\terror\);\n\t\t\treturn error;\n\t\t\}\n",
    "\tjoypad->rumble_gpio = devm_gpiod_get_optional(dev, \"rumble\", GPIOD_OUT_LOW);\n"
    "\tif (IS_ERR(joypad->rumble_gpio)) {\n"
    "\t\tdev_err(dev, \"Failed to get rumble gpio, error: %ld\\n\",\n"
    "\t\t\tPTR_ERR(joypad->rumble_gpio));\n"
    "\t\tjoypad->rumble_gpio = NULL;\t/* vibration is optional */\n\t}\n",
    "probe: rumble-gpio -> devm_gpiod_get_optional")

open(p, "w", encoding="utf-8").write(s)
print("=== replacements ===")
print("\n".join(report))

left = [ln for ln in s.splitlines()
        if re.search(r"gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio|devm_gpio_request|OF_GPIO_|gpio->num", ln)]
print(f"=== remaining legacy references: {len(left)} ===")
for ln in left[:15]:
    print("   ", ln.strip()[:130])

# any now-unused 'enum of_gpio_flags flags;' left anywhere?
for i, ln in enumerate(s.splitlines(), 1):
    if "of_gpio_flags" in ln:
        print(f"    line {i}: {ln.strip()}")
