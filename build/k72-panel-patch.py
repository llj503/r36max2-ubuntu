#!/usr/bin/env python3
"""k72-panel-patch.py - port panel-generic-dsi.c to the 7.2 drm_panel API.

Two compile errors, both from upstream API movement:
  hex2bin        -> moved to <linux/hex.h>
  drm_panel_init -> replaced by devm_drm_panel_alloc(), which allocates the
                    container and initialises the embedded struct drm_panel
                    (refcounted) in one step.
The edit is done with whitespace-tolerant regexes because the file mixes tabs.
"""
import re
import subprocess
import sys

P = "/root/r36/linux-7.2.8/drivers/gpu/drm/panel/panel-generic-dsi.c"
H = "/root/r36/linux-7.2.8/include/drm/drm_panel.h"

src = open(P).read()
orig = src

# --- what does the new helper look like, exactly? -------------------------
hdr = open(H).read()
m = re.search(r"#define devm_drm_panel_alloc\(.*?\)\s*\\\n.*?\n", hdr, re.S)
print("=== devm_drm_panel_alloc macro ===")
mac = re.search(r"#define devm_drm_panel_alloc.*?(?=\n\n)", hdr, re.S)
print(mac.group(0) if mac else "  MACRO NOT FOUND - aborting")
if not mac:
    sys.exit(1)
print("=== __devm_drm_panel_alloc return on failure ===")
impl = re.search(r"void \*__devm_drm_panel_alloc\(", hdr)
print("  declared" if impl else "  not in header")
ret = re.search(r"return ERR_PTR\([^)]*\);", mac.group(0))
print("  uses ERR_PTR in macro:", bool(ret))

# --- 1. hex2bin include ---------------------------------------------------
if "#include <linux/hex.h>" not in src:
    src = src.replace("#include <linux/module.h>",
                      "#include <linux/hex.h>\n#include <linux/module.h>", 1)
    print("[1] added #include <linux/hex.h>")
else:
    print("[1] hex.h already there")

# --- 2. container allocation ---------------------------------------------
alloc_re = re.compile(
    r"ctx\s*=\s*devm_kzalloc\(\s*dev,\s*sizeof\(\*ctx\),\s*GFP_KERNEL\s*\)\s*;")
if alloc_re.search(src):
    src = alloc_re.sub(
        "ctx = devm_drm_panel_alloc(dev, struct generic_panel, panel,\n"
        "\t\t\t\t\t   &generic_panel_funcs, DRM_MODE_CONNECTOR_DSI);",
        src, count=1)
    print("[2] devm_kzalloc -> devm_drm_panel_alloc")
else:
    print("[2] !! alloc site not matched")

# the new helper returns ERR_PTR on failure; keep the NULL check but add IS_ERR
nullchk_re = re.compile(r"if\s*\(\s*!ctx\s*\)\s*\n?\s*return -ENOMEM\s*;")
if nullchk_re.search(src):
    src = nullchk_re.sub("if (IS_ERR(ctx))\n\t\treturn PTR_ERR(ctx);", src, count=1)
    print("[2b] NULL check -> IS_ERR/PTR_ERR")

# --- 3. drop the now-nonexistent drm_panel_init --------------------------
init_re = re.compile(
    r"drm_panel_init\(\s*&ctx->panel,\s*&dsi->dev,\s*&generic_panel_funcs,\s*"
    r"DRM_MODE_CONNECTOR_DSI\s*\)\s*;")
if init_re.search(src):
    src = init_re.sub("/* the panel was initialised by devm_drm_panel_alloc() */",
                      src, count=1)
    print("[3] removed drm_panel_init() call")
else:
    print("[3] !! drm_panel_init call not matched")

# --- 4. generic_panel_funcs must be visible before probe -----------------
funcs_def = re.search(r"^static const struct drm_panel_funcs generic_panel_funcs",
                      src, re.M)
probe = re.search(r"^static int generic_panel_probe", src, re.M)
if funcs_def and probe:
    if funcs_def.start() > probe.start():
        src = src[:probe.start()] + \
            "static const struct drm_panel_funcs generic_panel_funcs;\n\n" + \
            src[probe.start():]
        print("[4] added forward declaration of generic_panel_funcs")
    else:
        print("[4] funcs already defined before probe")
else:
    print("[4] !! could not locate funcs/probe")

if src != orig:
    open(P + ".bak", "w").write(orig)
    open(P, "w").write(src)
    print("=== patched (backup at panel-generic-dsi.c.bak) ===")
    subprocess.run(f"diff -u {P}.bak {P} | head -60", shell=True)
else:
    print("=== nothing changed ===")
