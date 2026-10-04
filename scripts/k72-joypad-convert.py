#!/usr/bin/env python3
"""k72-joypad-convert.py - the whole gpiod conversion in ONE pass from the
pristine source (the previous three-step version deleted too much: its brace
walk ran past the end of the rumble block and ate joypad_probe's signature).

Edits, all anchored on exact text and bounded by indentation:
  1. includes: <linux/of_gpio.h>/<linux/of_gpio_legacy.h> -> <linux/gpio/consumer.h>
  2. struct bt_gpio: int num -> struct gpio_desc *desc ; rumble_gpio likewise
  3. vibrator start/stop: gpio_is_valid/gpio_set_value -> bool test + gpiod_set_value_cansleep
  4. poll: gpio_get_value_cansleep -> gpiod_get_value_cansleep (skip NULL desc)
  5. button setup: of_get_gpio_flags + devm_gpio_request_one -> devm_fwnode_gpiod_get_index
  6. probe: of_get_named_gpio_flags("rumble-gpio") -> devm_gpiod_get_optional("rumble")
"""
import os
import re
import shutil
import subprocess

SRC = "/root/r36/joypad/src"
WORK = "/root/r36/k72joypad"
F = "rocknix-joypad.c"

shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree(SRC, WORK)
subprocess.run(f"find {WORK} \\( -name '*.o' -o -name '*.ko' -o -name '*.mod*' "
               f"-o -name '.*.cmd' -o -name Module.symvers -o -name modules.order \\) -delete",
               shell=True)

p = os.path.join(WORK, F)
text = open(p, encoding="utf-8", errors="replace").read()
log = []


def sub(pattern, repl, note, count=1):
    global text
    text, n = re.subn(pattern, repl, text, count=count, flags=re.S)
    log.append(f"  {'OK  ' if n else 'MISS'} x{n}  {note}")


sub(r"#if \(LINUX_VERSION_CODE < KERNEL_VERSION\(6, 3, 0\)\)\n"
    r"#include <linux/of_gpio\.h>\n#else\n"
    r"#include <linux/of_gpio_legacy\.h>\n#endif\n",
    "#include <linux/gpio/consumer.h>\n", "1 includes -> gpio/consumer.h")

sub(r"/\* GPIO Number \*/\n\tint num;",
    "/* GPIO descriptor */\n\tstruct gpio_desc *desc;", "2a bt_gpio int num -> gpio_desc *")
sub(r"\tint rumble_gpio;", "\tstruct gpio_desc *rumble_gpio;", "2b rumble_gpio -> gpio_desc *")

sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\) \{\n(\t\t)gpio_set_value\(joypad->rumble_gpio, 1\);",
    "if (joypad->rumble_gpio) {\n\\1gpiod_set_value_cansleep(joypad->rumble_gpio, 1);",
    "3a vibrator start")
sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\) \{\n(\t\t)gpio_set_value\(joypad->rumble_gpio, 0\);",
    "if (joypad->rumble_gpio) {\n\\1gpiod_set_value_cansleep(joypad->rumble_gpio, 0);",
    "3b vibrator stop")
sub(r"if \(gpio_is_valid\(joypad->rumble_gpio\)\)", "if (joypad->rumble_gpio)",
    "3c remaining rumble guards", count=0)

sub(r"\t\tif \(gpio_get_value_cansleep\(gpio->num\) < 0\) \{\n"
    r"\t\t\tdev_err\(joypad->dev, \"failed to get gpio state\\n\"\);\n"
    r"\t\t\tcontinue;\n\t\t\}\n"
    r"\t\tvalue = gpio_get_value_cansleep\(gpio->num\);",
    "\t\tif (!gpio->desc)\n\t\t\tcontinue;\n"
    "\t\tvalue = gpiod_get_value_cansleep(gpio->desc);\n"
    "\t\tif (value < 0) {\n"
    "\t\t\tdev_err(joypad->dev, \"failed to get gpio state\\n\");\n"
    "\t\t\tcontinue;\n\t\t}",
    "4 poll -> gpiod_get_value_cansleep")

sub(r"\t\tenum of_gpio_flags flags;\n(\t\tstruct bt_gpio \*gpio = &joypad->gpios\[nbtn\+\+\];)",
    "\\1", "5a drop enum of_gpio_flags in the loop")
sub(r"\t\tgpio->num = of_get_gpio_flags\(pp, 0, &flags\);\n.*?\n\t\t\}\n",
    "\t\t/* gpiod honours the DT polarity: asserted is always logical 1 */\n"
    "\t\tgpio->active_level = true;\n"
    "\t\tgpio->desc = devm_fwnode_gpiod_get_index(dev, of_fwnode_handle(pp),\n"
    "\t\t\t\t\t\t\t \"gpios\", 0, GPIOD_IN,\n"
    "\t\t\t\t\t\t\t gpio->label ? gpio->label : \"button\");\n"
    "\t\tif (IS_ERR(gpio->desc)) {\n"
    "\t\t\terror = PTR_ERR(gpio->desc);\n"
    "\t\t\tif (error != -ENOENT && error != -ENOSYS) {\n"
    "\t\t\t\tdev_err(dev, \"Failed to get gpio, error: %d\\n\", error);\n"
    "\t\t\t\treturn error;\n"
    "\t\t\t}\n"
    "\t\t\tgpio->desc = NULL;\n"
    "\t\t}\n",
    "5b of_get_gpio_flags + request_one -> devm_fwnode_gpiod_get_index")
sub(r"\"Button without keycode: 0x%x\\n\",\n\t\t\t\tgpio->num\)",
    "\"Button without keycode: 0x%x\\n\", (unsigned)nbtn)", "5c dev_err arg")

open(p, "w", encoding="utf-8").write(text)

# ---- 6. the rumble block in probe: line-based, bounded by indentation ----
lines = text.split("\n")
i = next((n for n, l in enumerate(lines)
          if "of_get_named_gpio_flags(dev->of_node, \"rumble-gpio\"" in l), None)
if i is None:
    log.append("  MISS      6 rumble anchor not found")
else:
    # the block is: <anchor line> then `if (...) {` ... closed by a line that is
    # exactly one tab + '}' (kernel style).  Find that, never further than 40 lines.
    j = i + 1
    end = -1
    for n in range(j, min(j + 40, len(lines))):
        if lines[n] == "\t}":
            end = n
            break
    if end < 0:
        log.append("  MISS      6 could not bound the rumble block")
    else:
        removed = lines[i:end + 1]
        new = [
            "\tjoypad->rumble_gpio = devm_gpiod_get_optional(dev, \"rumble\", GPIOD_OUT_LOW);",
            "\tif (IS_ERR(joypad->rumble_gpio)) {",
            "\t\tdev_err(dev, \"Failed to get rumble gpio, error: %ld\\n\",",
            "\t\t\tPTR_ERR(joypad->rumble_gpio));",
            "\t\tjoypad->rumble_gpio = NULL;\t/* vibration is optional */",
            "\t} else if (joypad->rumble_gpio) {",
            "\t\tjoypad->has_rumble = true;",
            "\t\tdev_info(dev, \"%s : has gpio rumble\\n\", __func__);",
            "\t}",
        ]
        lines[i:end + 1] = new
        log.append(f"  OK   x1   6 rumble block ({end - i + 1} lines -> {len(new)})")
        print("   removed:")
        for l in removed:
            print("      |" + l.rstrip())
    text = "\n".join(lines)
    open(p, "w", encoding="utf-8").write(text)

# drop a now-unused enum of_gpio_flags declaration anywhere at function scope
text = re.sub(r"\tenum of_gpio_flags flags;\n", "", text)
open(p, "w", encoding="utf-8").write(text)

print("=== replacements ===")
print("\n".join(log))
left = [l.strip() for l in text.split("\n")
        if re.search(r"gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio"
                     r"|devm_gpio_request|OF_GPIO_|gpio->num|of_gpio_flags|gpio_direction_output", l)]
print(f"=== remaining legacy GPIO references: {len(left)} ===")
for l in left[:10]:
    print("   ", l[:130])
