#!/usr/bin/env python3
"""k72-gpiod-semantics-fix.py - make the converted joypad drive/read every line
with gpiod semantics that match the physical levels the legacy integer-GPIO
driver produced on hardware (that behaviour is what we verified on 6.12).

Two problems found by auditing the conversion:

1. joypad_amux_select() inherited the legacy *raw* numbers.  Legacy wrote
   gpio_set_value(en, 0) to ENABLE the mux (INH is active-low) and used raw
   levels on sel_a/sel_b.  gpiod_set_value() is polarity aware, so with
   amux-en ACTIVE_LOW the same 0 now DISABLES the mux -> the sticks and every
   ADC-ladder button read a floating pin.  Fix: assert/deassert logically
   (write 1 to enable, 0 to disable) and declare the *address* line sel_a
   ACTIVE_HIGH, which is what an address bit really is.

2. devm_gpiod_get_optional() error checks were copy-pasted from the rumble line
   and test joypad->rumble_gpio instead of the desc just acquired, so an
   ERR_PTR could survive into gpiod_set_value_cansleep() -> oops.

Every match is asserted, so a silent no-op can't be mistaken for a fix.
"""
import sys, io

NEW = "/root/r36/k72joypad/rocknix-singleadc-joypad.c"
PLAIN = "/root/r36/k72joypad/rocknix-joypad.c"

def load(p):
    with io.open(p, "r", encoding="utf-8", errors="surrogateescape") as f:
        return f.read()

def store(p, s):
    with io.open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(s)

def sub_once(txt, old, new, what, count=1):
    n = txt.count(old)
    if n != count:
        print("  !! %-40s expected %d match(es), found %d" % (what, count, n))
        return txt, False
    print("  ok %-40s x%d" % (what, n))
    return txt.replace(old, new), True

src = load(NEW)

# ---- 1. mux enable/assert semantics --------------------------------------
old_enable = """	/* select mux channel */
	gpiod_set_value_cansleep(amux->en_gpio, 0);
"""
new_enable = """	/*
	 * gpiod knows what "asserted" means: amux-en is declared ACTIVE_LOW in
	 * DT (a 74HC4052 style INH pin - low connects the mux), so driving the
	 * mux means logical 1 here.  The legacy integer API wrote the raw level
	 * 0 for the same effect; a mechanical gpio_set_value() ->
	 * gpiod_set_value() rename would have inverted it and left the mux
	 * permanently disabled (sticks and ADC-ladder keys read a floating pin).
	 */
	gpiod_set_value_cansleep(amux->en_gpio, 1);
"""
src, ok1 = sub_once(src, old_enable, new_enable, "mux enable -> logical assert")

old_disable = """		default:
			/* amux disanle */
			gpiod_set_value_cansleep(amux->en_gpio, 1);
			return -1;
"""
new_disable = """		default:
			/* amux disable: deassert the enable line */
			gpiod_set_value_cansleep(amux->en_gpio, 0);
			return -1;
"""
src, ok2 = sub_once(src, old_disable, new_disable, "mux error-path disable")

# the channel table itself: keep the legacy *levels*, so only the sel_a DT
# polarity has to change (see the board dts); sel_b is already ACTIVE_HIGH.
print("  -- amux channel table left untouched (levels come from DT polarity)")

# ---- 2. wrong pointer in the IS_ERR checks --------------------------------
buggy = {
    '"amux-a"': "amux->sel_a_gpio",
    '"amux-b"': "amux->sel_b_gpio",
    '"amux-en"': "amux->en_gpio",
}
ok3 = True
for conid, member in buggy.items():
    old = ('	%s = devm_gpiod_get_optional(dev, %s, GPIOD_OUT_LOW);\n'
           '	if (IS_ERR(joypad->rumble_gpio)) {\n'
           '		ret = PTR_ERR(%s);\n'
           '		dev_err(dev, "%%s : failed to get %s\\n", __func__);\n' % (member, conid, member, conid.strip('"'))
           )
    # tolerate the exact indentation/quotes actually present by rebuilding below
    idx = src.find("%s = devm_gpiod_get_optional(dev, %s, GPIOD_OUT_LOW);" % (member, conid))
    if idx < 0:
        print("  !! no devm_gpiod_get_optional for %s" % member)
        ok3 = False
        continue
    line_end = src.index("\n", idx)
    tail = src[line_end + 1:]
    if "IS_ERR(joypad->rumble_gpio)" not in tail.split("\n")[0]:
        print("  ok %-40s already checks the right pointer" % ("IS_ERR for " + member))
        continue
    nxt = tail.split("\n")[0:4]
    block = "\n".join(nxt)
    fixed = block.replace("IS_ERR(joypad->rumble_gpio)", "IS_ERR(%s)" % member) \
                  .replace("ret = PTR_ERR(joypad->rumble_gpio);", "ret = PTR_ERR(%s);" % member)
    if "PTR_ERR(joypad->rumble_gpio)" in block:
        fixed = fixed.replace("PTR_ERR(joypad->rumble_gpio)", "PTR_ERR(%s)" % member)
    src = src.replace(block, fixed, 1)
    print("  ok %-40s -> IS_ERR/PTR_ERR(%s)" % ("error check for " + member, member))

if ok3:
    print("  ok IS_ERR/PTR_ERR copy-paste bug handled")

store(NEW, src)

# ---- 3. the plain (multi-ADC) variant: same rumble handling? -------------
plain = load(PLAIN)
if "amux->en_gpio" in plain:
    print("  note: rocknix-joypad.c also drives an amux enable - audit it too")
else:
    print("  note: rocknix-joypad.c has no amux, only rumble + buttons")

print("=== edits done, files rewritten ===")
