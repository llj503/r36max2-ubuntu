#!/usr/bin/env python3
"""v20-scan-check.py - the secret scanner flagged `psk=` inside build-rootfs.sh.
Decide whether that is only template code (it writes a wpa config at build time)
or an actual passphrase. Prints line numbers and masked content only - the secret
must never be echoed, least of all into a log that then gets committed."""
import io
import re

ROOT = "/mnt/e/ubuntu/"
CRED = ROOT + "build/wifi-cred.txt"
TARGETS = ["build/build-rootfs.sh", "README.md", "build/v20-strip-creds.sh",
           "build/v20-hostkeys.py", "build/apply-v19.sh", "build/r36-wifi-setup"]

def cred_value(key):
    for line in io.open(CRED, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*([A-Za-z_-]+)\s*=\s*(.*?)\s*$", line)
        if m and m.group(1).lower() == key:
            return m.group(2).strip('"\'')
    return ""

psk = cred_value("passphrase")
ssid = cred_value("name")
print("  credential lengths: psk=%d ssid=%d (not shown)" % (len(psk), len(ssid)))

for t in TARGETS:
    path = ROOT + t
    try:
        text = io.open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("  %-28s unreadable: %s" % (t, e))
        continue
    lines = text.split("\n")
    hits = [i + 1 for i, ln in enumerate(lines) if re.search(r"psk|passphrase|SSID|ssid", ln)]
    leak = bool(psk and psk in text) or bool(ssid and ssid in text)
    print("  %-28s template lines=%-3s real-secret-present=%s" % (t, len(hits), "YES !!" if leak else "no"))
    if leak:
        for i, ln in enumerate(lines):
            if (psk and psk in ln) or (ssid and ssid in ln):
                print("      line %d: %s" % (i + 1, ln.replace(psk, "<PSK>").replace(ssid, "<SSID>")))
    # show the shape of the flagged lines with any long token masked
    for i in hits[:3]:
        ln = lines[i - 1].strip()
        ln = re.sub(r"(=|\"|')([A-Za-z0-9!@#$%^&*._-]{8,})", r"\1<token>", ln)
        print("      %4d: %s" % (i, ln[:120]))
