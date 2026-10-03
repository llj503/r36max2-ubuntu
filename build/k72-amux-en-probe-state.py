#!/usr/bin/env python3
"""k72-amux-en-probe-state.py - request the mux enable the way the legacy driver
left it: gpio_direction_output(en, 0) drove the INH pin LOW = mux connected.
With amux-en declared ACTIVE_LOW in DT, the gpiod equivalent of "physical low"
is GPIOD_OUT_HIGH (deasserted means released, i.e. the pin follows the flag).
Without this the line comes up disconnected and anything that reads the ADC
before the first amux_select() sees a floating pin.
"""
p = "/root/r36/k72joypad/rocknix-singleadc-joypad.c"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
old = '\tamux->en_gpio = devm_gpiod_get_optional(dev, "amux-en", GPIOD_OUT_LOW);'
new = ('\t/* GPIOD_OUT_HIGH + ACTIVE_LOW in DT == the raw level 0 the legacy\n'
       '\t * driver applied at probe: INH low, mux connected, ADC pin driven.\n'
       '\t */\n'
       '\tamux->en_gpio = devm_gpiod_get_optional(dev, "amux-en", GPIOD_OUT_HIGH);')
assert s.count(old) == 1, "amux-en request line not found exactly once: %d" % s.count(old)
open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s.replace(old, new))
print("ok: amux-en now requested as asserted (physical low)")
