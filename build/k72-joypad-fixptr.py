#!/usr/bin/env python3
"""k72-joypad-fixptr.py - the rumble replacement lost its backreference inside
PTR_ERR(), leaving `PTR_ERR())`.  Point it back at the descriptor and rebuild
against both kernels."""
import re

for p in ["/root/r36/k72joypad/rocknix-joypad.c",
          "/root/r36/k72joypad/rocknix-singleadc-joypad.c"]:
    s = open(p, encoding="utf-8", errors="replace").read()
    # recover the variable from the enclosing `if (IS_ERR(x))` line
    def fix(m):
        var = m.group(1)
        return m.group(0).replace("PTR_ERR())", f"PTR_ERR({var}))")
    new = re.sub(r"if \(IS_ERR\(([\w>.->\[\]]+)\)\) \{\n[^\0]*?PTR_ERR\(\)\)",
                 fix, s, flags=re.S)
    n = s.count("PTR_ERR())")
    open(p, "w", encoding="utf-8").write(new)
    print(f"{p.split('/')[-1]}: repaired {n} empty PTR_ERR()")
    for m in re.finditer(r".*PTR_ERR\(.*", new):
        print("   ", m.group(0).strip()[:110])
