#!/usr/bin/env python3
"""k72-gpiod-conid-fix.py - the real reason the 17 buttons never fired.

gpiolib builds the property candidates as "<con_id>-gpios" then "<con_id>-gpio"
(gpio_suffixes[] = {"gpios","gpio"}), and only falls back to the bare "gpios"
when con_id is NULL.  The mechanical conversion passed con_id == "gpios", so the
driver looked for "gpios-gpios" / "gpios-gpio" in every button child node, got
-ENOENT, and the code deliberately tolerates -ENOENT by setting desc = NULL ->
silently dead buttons, no consumers in debugfs, no error in dmesg.

It also explains why "amux-a"/"rumble" worked: the vendor DT spells the rumble
supply "rumble-gpio" (singular), which the second suffix matches.

Fix: con_id = NULL so the bare "gpios" property is used, exactly like the legacy
of_get_named_gpio_flags(pp, "gpios", 0, &flags).
"""
import io

FILES = ["/root/r36/k72joypad/rocknix-singleadc-joypad.c",
         "/root/r36/k72joypad/rocknix-joypad.c"]

OLD = '"gpios", 0, GPIOD_IN,'
NEW = 'NULL, 0, GPIOD_IN,		/* bare "gpios" property */'

for p in FILES:
    s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
    n = s.count(OLD)
    if n == 0:
        print("  -- %s: no con_id=\"gpios\" call site (already fixed or different shape)" % p.split("/")[-1])
        continue
    s = s.replace(OLD, NEW)
    io.open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
    print("  ok %s: %d call site(s) now use con_id=NULL" % (p.split("/")[-1], n))
