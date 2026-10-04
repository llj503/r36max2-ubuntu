#!/usr/bin/env python3
"""k72-joypad-gpiod-all.py - convert BOTH joypad driver files to gpiod in one
pass from the pristine source.  The board binds to rocknix-singleadc-joypad, so
that file matters most; it also drives the analog mux through three more GPIOs.

Rules applied (all anchored on exact text, verified by the counts it prints):
  includes        of_gpio.h / of_gpio_legacy.h        -> gpio/consumer.h
  fields          int num / int rumble_gpio / amux    -> struct gpio_desc *
  reads           gpio_get_value_cansleep             -> gpiod_get_value_cansleep
  writes          gpio_set_value[_cansleep]           -> gpiod_set_value_cansleep
  presence test   gpio_is_valid(x)                    -> (x)
  requests        of_get_named_gpio_flags + request_one + direction_output
                  -> devm_gpiod_get_optional(dev, "<con>", GPIOD_OUT_LOW)
  button loop     of_get_gpio_flags(pp,...) + request_one
                  -> devm_fwnode_gpiod_get_index(dev, of_fwnode_handle(pp),
                                                 "gpios", 0, GPIOD_IN, label)
"""
import re
import shutil
import subprocess

SRC = "/root/r36/joypad/src"
WORK = "/root/r36/k72joypad"
FILES = ["rocknix-joypad.c", "rocknix-singleadc-joypad.c"]

shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree(SRC, WORK)
subprocess.run(f"find {WORK} \\( -name '*.o' -o -name '*.ko' -o -name '*.mod*' "
               f"-o -name '.*.cmd' -o -name Module.symvers -o -name modules.order \\) -delete",
               shell=True)

log = []


def rep(pat, repl, note, s, count=0):
    new, n = re.subn(pat, repl, s, count=count, flags=re.S)
    log.append(f"  {'OK  ' if n else 'MISS'} x{n}  {note}")
    return new


for f in FILES:
    p = f"{WORK}/{f}"
    s = open(p, encoding="utf-8", errors="replace").read()
    log.append(f"--- {f}")

    # 1. includes
    s = rep(r"#if \(LINUX_VERSION_CODE < KERNEL_VERSION\(6, 3, 0\)\)\n"
            r"#include <linux/of_gpio\.h>\n#else\n"
            r"#include <linux/of_gpio_legacy\.h>\n#endif\n",
            "#include <linux/gpio/consumer.h>\n", "includes -> gpio/consumer.h", s)

    # 2. struct fields
    s = rep(r"/\* GPIO Number \*/\n\tint num;",
            "/* GPIO descriptor */\n\tstruct gpio_desc *desc;", "bt_gpio.num -> desc", s)
    s = rep(r"\tint rumble_gpio;", "\tstruct gpio_desc *rumble_gpio;",
            "rumble_gpio -> desc", s)
    s = rep(r"\tint (sel_a_gpio|sel_b_gpio|en_gpio);", r"\tstruct gpio_desc *\1;",
            "amux gpio fields -> desc", s)

    # 3. value accessors (order matters: cansleep variants first)
    s = rep(r"\bgpio_set_value_cansleep\(", "gpiod_set_value_cansleep(",
            "gpio_set_value_cansleep -> gpiod", s)
    s = rep(r"\bgpio_get_value_cansleep\(", "gpiod_get_value_cansleep(",
            "gpio_get_value_cansleep -> gpiod", s)
    s = rep(r"\bgpio_set_value\(", "gpiod_set_value_cansleep(",
            "gpio_set_value -> gpiod", s)
    s = rep(r"\bgpio_is_valid\(", "!!(", "gpio_is_valid -> pointer test", s)

    # 4a. analog-mux GPIOs (that function has an err_out: label)
    s = rep(r"(\w+(?:->|\.)\w+) = of_get_named_gpio_flags\(\s*dev->of_node,\s*"
            r'"(amux-[^"]+?)-gpios?", 0, &flags\);\n'
            r"\tif \(!!\(\1\)\) \{.*?\n\t\}\n",
            r"\1 = devm_gpiod_get_optional(dev, \"\2\", GPIOD_OUT_LOW);\n"
            "\tif (IS_ERR(\1)) {\n"
            r"\t\tret = PTR_ERR(\1);\n"
            r"\t\tdev_err(dev, \"%s : failed to get \2\\n\", __func__);\n"
            "\t\tgoto err_out;\n"
            "\t}\n",
            "amux request -> devm_gpiod_get_optional", s)

    # 4b. the rumble GPIO, requested in probe (no err_out label there)
    s = rep(r"(\w+(?:->|\.)\w+) = of_get_named_gpio_flags\(\s*dev->of_node,\s*"
            r'"(rumble[^"]*?)-gpios?", 0, &flags\);\n'
            r"\tif \(!!\(\1\)\) \{.*?\n\t\}\n",
            r"\1 = devm_gpiod_get_optional(dev, \"\2\", GPIOD_OUT_LOW);\n"
            "\tif (IS_ERR(\1)) {\n"
            r"\t\tdev_err(dev, \"%s : failed to get \2, error: %ld\\n\", __func__,\n"
            "\t\t\tPTR_ERR(\1));\n"
            "\t\t\1 = NULL;\t\t/* vibration is optional */\n"
            "\t} else if (\1) {\n"
            "\t\tjoypad->has_rumble = true;\n"
            r"\t\tdev_info(dev, \"%s : has gpio rumble\\n\", __func__);\n"
            "\t}\n",
            "rumble request -> devm_gpiod_get_optional (probe)", s)

    # 5. button loop
    s = rep(r"\t\tenum of_gpio_flags flags;\n", "", "drop loop's flags decl", s)
    s = rep(r"\t\tgpio->num = of_get_gpio_flags\(pp, 0, &flags\);\n"
            r".*?(?=\t\tif \(of_property_read_u32\(pp, \"linux,code\")",
            "\t\tgpio->label = of_get_property(pp, \"label\", NULL);\n\n"
            "\t\t/* gpiod honours the DT polarity: asserted is logical 1 */\n"
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
            "\t\t}\n\n",
            "button loop -> devm_fwnode_gpiod_get_index", s)
    s = rep(r"gpio->num", "gpio->desc", "leftover gpio->num refs", s)
    s = rep(r"\t\t\t\tgpio->desc\);", "\t\t\t\t(unsigned)nbtn);",
            "dev_err arg that printed the gpio number", s)

    # 6. probe rumble (single-line form) + unused flags decl
    s = rep(r"\tenum of_gpio_flags flags;\n", "", "drop unused flags decl", s)

    open(p, "w", encoding="utf-8").write(s)

print("=== replacement log ===")
print("\n".join(log))

print("=== residual legacy references ===")
r = subprocess.run(f"grep -nE 'gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio"
                   f"|of_get_named_gpio|devm_gpio_request|OF_GPIO_|gpio_direction|of_gpio_flags' "
                   f"{' '.join(f'{WORK}/{f}' for f in FILES)} | head -20",
                   shell=True, capture_output=True, text=True)
print(r.stdout or "   none")
