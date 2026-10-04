#!/usr/bin/env python3
"""theme-check-local.py - walk a staged Art Book Next theme the way EmulationStation
would, and report every file reference that does not resolve on disk.

Why this exists: k72-es-theme-install.sh mirrors ROCKNIX's makeinstall, which deletes the
unused artwork variants and then prunes "the <include name=...> lines that referenced
them".  In THIS tarball (rev 9a50ef36) the variants are not referenced by <include> at
all - they are <path> children of <image> elements, e.g.

    <path ifSubset="system-view-artwork:noir">./_inc/systems/artwork-noir/_default.png</path>

so that sed deletes the directories and leaves every reference dangling.  Rather than
argue about whether ES tolerates a missing <path>, measure it: this script lists exactly
which references break, per artwork variant, for the tree as it is and for the tree after
the prune.

Runs entirely on the host copy (build/vendor/theme-stage) - zero I/O on the board while it
is still compiling.

    python3 tools/theme/verify/theme-check-local.py [dir] [--prune a,b,c]
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

REF_TAGS = ("path", "image", "font", "include", "background", "logo", "tile", "help")
# Paths built from ${themeCustomizationsPath} point at the USER's optional override
# folder (/userdata/theme-customizations/art-book-next/), which is not in the tarball by
# design - the theme falls back to its own artwork.  Counting those as breakage would be
# a false alarm, so they are reported separately and never fail the check.
OPTIONAL_MARKERS = ("themeCustomizationsPath", "customPath", "userCustom")
VAR_RE = re.compile(r"\$\{[^}]*\}")
# ES themes write conditions like  if="${a} == '1' && ${b} == '2'"  - a raw '&' that is
# not an entity reference.  Python's ElementTree refuses it; Batocera's own ES loads the
# same file every day (this theme ships with v40+), so the strict parse is a property of
# my checker, not a defect in the theme.  Escape lone ampersands before parsing.
LONE_AMP = re.compile(r"&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)")


def parse_lenient(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    return ET.fromstring(LONE_AMP.sub("&amp;", txt))



def refs_in(elem):
    """Yield (tag, attribute-or-text, ifSubset) for anything that can name a file."""
    for e in elem.iter():
        tag = e.tag
        if not isinstance(tag, str):
            continue
        cand = []
        if tag in REF_TAGS:
            if e.text and e.text.strip():
                cand.append(e.text.strip())
            for a in ("path", "name", "value", "font"):
                v = e.get(a)
                if v and "/" in v or (v or "").endswith((".png", ".jpg", ".ttf", ".xml")):
                    cand.append(v.strip())
        for v in cand:
            yield tag, v, e.get("ifSubset", "")


def check(root_dir, label):
    total = missing = unresolved_vars = optional = 0
    bad = []
    for dirpath, _dirs, files in os.walk(root_dir):
        for fn in files:
            if not fn.endswith(".xml"):
                continue
            f = os.path.join(dirpath, fn)
            try:
                root_el = parse_lenient(f)
            except ET.ParseError as exc:
                bad.append(("PARSE", os.path.relpath(f, root_dir), str(exc)))
                continue
            for tag, val, ifsub in refs_in(root_el):
                # a reference names a file if it has a separator or a theme extension;
                # requiring "./" would miss ../../fonts/x.ttf and ./-less includes
                if not ("/" in val or val.endswith((".png", ".jpg", ".jpeg", ".ttf", ".xml", ".svg"))):
                    continue
                if tag == "include" and not val.startswith((".", "/")):
                    continue          # a <subset> option name, resolved by ES differently
                total += 1
                if any(m in val for m in OPTIONAL_MARKERS):
                    optional += 1
                    continue
                rel = VAR_RE.sub("*", val)
                # ES writes "./_inc/..." root-relative, but a nested include may write it
                # relative to itself.  Accept either; only call it missing if neither the
                # including file's directory nor the theme root has it (no false alarms).
                t_here = os.path.normpath(os.path.join(dirpath, rel))
                t_root = os.path.normpath(os.path.join(root_dir, rel.lstrip("./")))
                if os.path.exists(t_here):
                    continue
                if os.path.exists(t_root):
                    continue
                if "*" in rel:
                    # a variable path (${system.theme}.png): fine as long as the directory
                    # it points into still exists - that is exactly what a prune breaks
                    if not (os.path.isdir(os.path.dirname(t_here)) or os.path.isdir(os.path.dirname(t_root))):
                        unresolved_vars += 1
                        bad.append(("MISSING-DIR", os.path.relpath(f, root_dir), val))
                    continue
                missing += 1
                if len(bad) < 400:
                    bad.append(("MISSING-FILE", os.path.relpath(f, root_dir), val))
    print("=== %s ===" % label)
    print("  path references scanned : %d" % total)
    print("  missing files           : %d" % missing)
    print("  references into a deleted directory (variable paths): %d" % unresolved_vars)
    print("  optional user-customization paths (absent by design): %d" % optional)
    print("  xml parse errors after escaping lone & : %d" % sum(1 for b in bad if b[0] == "PARSE"))
    bysrc = {}
    for kind, src, val in bad:
        bysrc.setdefault(src, []).append((kind, val))
    for src, items in sorted(bysrc.items(), key=lambda kv: -len(kv[1]))[:8]:
        print("    %-46s %3d dangling, e.g. %s" % (src, len(items), items[0][1][:70]))
    return missing + unresolved_vars


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             "vendor", "theme-stage")
    if not os.path.isdir(root):
        print("  !! %s missing - run: EXTRACT=1 bash scripts/theme-stage-local.sh" % root)
        return 1
    print("theme tree: %s" % root)
    print("  xml files: %d, png: %d, ttfs: %d" % (
        sum(1 for d, _, fs in os.walk(root) for f in fs if f.endswith(".xml")),
        sum(1 for d, _, fs in os.walk(root) for f in fs if f.endswith(".png")),
        sum(1 for d, _, fs in os.walk(root) for f in fs if f.endswith(".ttf"))))
    before = check(root, "A) tree as downloaded (nothing pruned)")

    prune = []
    for a in sys.argv[1:]:
        if a.startswith("--prune"):
            prune = a.split("=", 1)[1].split(",") if "=" in a else \
                ["artwork-circuit", "artwork-classic", "artwork-nintendont",
                 "artwork-noir", "artwork-outline"]
    if prune:
        import shutil
        import tempfile
        tmp = tempfile.mkdtemp(prefix="theme-prune-")
        dst = os.path.join(tmp, "theme")
        shutil.copytree(root, dst)
        for a in prune:
            p = os.path.join(dst, "_inc", "systems", a)
            if os.path.isdir(p):
                shutil.rmtree(p)
            # exactly what k72-es-theme-install.sh does today:
            tf = os.path.join(dst, "theme.xml")
            if os.path.exists(tf):
                txt = open(tf, encoding="utf-8", errors="replace").read()
                open(tf, "w", encoding="utf-8").write(
                    "\n".join(l for l in txt.splitlines()
                              if '<include name="%s"' % a not in l))
        after = check(dst, "B) after MY CURRENT installer prune (dirs gone, include-only sed)")
        # and what a correct prune would do: drop every line that names the dir
        for a in prune:
            p = os.path.join(dst, "_inc", "systems", a)
            if os.path.isdir(p):
                shutil.rmtree(p)
        for dirpath, _d, files in os.walk(dst):
            for fn in files:
                if not fn.endswith(".xml"):
                    continue
                f = os.path.join(dirpath, fn)
                txt = open(f, encoding="utf-8", errors="replace").read()
                keep = [l for l in txt.splitlines()
                        if not any("_inc/systems/%s" % a in l for a in prune)]
                if len(keep) != len(txt.splitlines()):
                    open(f, "w", encoding="utf-8").write("\n".join(keep) + "\n")
        fixed = check(dst, "C) prune done properly (dirs AND the lines naming them)")
        shutil.rmtree(tmp, ignore_errors=True)
        print("verdict: current installer leaves %d dangling refs, a line-based prune leaves %d"
              % (after, fixed))
        return 0 if fixed == 0 else 2
    return 0 if before == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
