#!/usr/bin/env python3
"""r36-hostkeys.service writer + SSID sweep for the staging rootfs.

Two things a shared image must not carry:

1. Our network name.  The passphrase sweep already ran clean; this one looks for
   the SSID too (the credential file spells it "Name=", which is why an earlier
   grep with an empty pattern "matched" every file in the tree - an empty -F
   pattern matches everything, so verify the pattern is non-empty first).

2. SSH host keys.  The image was built once, so /etc/ssh/ssh_host_* are the same
   on every card flashed from it - two strangers on the same network would see
   identical fingerprints, and anyone who has the published image has the private
   keys.  Delete them and ship a first-boot unit that regenerates them with
   `ssh-keygen -A` (sshd refuses to start with no keys, so it must run before
   ssh.service).
"""
from pathlib import Path
import glob
import os
import re
import subprocess
import sys

R = os.environ.get("R", "/root/r36/rootfs")
REPO = Path(__file__).resolve().parents[1]
CRED = f"{REPO}/build/wifi-cred.txt"

UNIT = """[Unit]
Description=Generate fresh SSH host keys on first boot
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ssh-keygen -A
ExecStart=/bin/systemctl try-restart ssh.service

[Install]
WantedBy=multi-user.target
"""


def read_key(name):
    if not os.path.exists(CRED):
        return ""
    for line in open(CRED, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*([A-Za-z_-]+)\s*=\s*(.*?)\s*$", line)
        if m and m.group(1).lower() == name.lower():
            return m.group(2).strip('"\'')
    return ""


def main():
    ssid = read_key("Name")
    psk = read_key("Passphrase")
    print("  credential file: name=%d chars, passphrase=%d chars (values not shown)"
          % (len(ssid), len(psk)))
    if not psk:
        print("  !! cannot read the passphrase - refusing to claim the image is clean")
        return 1

    print("=== [1] sweep the rootfs for the SSID (only if the pattern is non-empty) ===")
    bad = []
    if ssid:
        for base in ("etc", "root", "home", "var/log", "var/lib/connman", "srv"):
            d = os.path.join(R, base)
            if not os.path.isdir(d):
                continue
            out = subprocess.run(["grep", "-rlI", "--exclude-dir=share", "-F", "--", ssid, d],
                                 capture_output=True, text=True).stdout
            for f in out.split("\n"):
                if f:
                    bad.append(f)
                    print("  !! SSID appears in: %s" % f[len(R) + 1:])
    else:
        print("  (no SSID in the credential file - skipping)")
    print("  files with the SSID: %d" % len(bad))

    print("=== [2] sweep for the passphrase too (belt and braces) ===")
    hits = subprocess.run(
        ["grep", "-rlI", "-F", "--", psk,
         os.path.join(R, "etc"), os.path.join(R, "root"), os.path.join(R, "var")],
        capture_output=True, text=True).stdout.split("\n")
    hits = [h for h in hits if h]
    for h in hits:
        print("  !! passphrase in: %s" % h[len(R) + 1:])
    print("  files with the passphrase: %d" % len(hits))

    print("=== [3] SSH host keys: remove them from the image, regenerate at boot ===")
    keys = sorted(glob.glob(os.path.join(R, "etc/ssh/ssh_host_*")))
    for k in keys:
        print("  removing %s" % k[len(R) + 1:])
    if not keys:
        print("  (none present)")
    for k in keys:
        os.remove(k)
    unit_path = os.path.join(R, "etc/systemd/system/r36-hostkeys.service")
    with open(unit_path, "w") as f:
        f.write(UNIT)
    os.chmod(unit_path, 0o644)
    wants = os.path.join(R, "etc/systemd/system/multi-user.target.wants")
    os.makedirs(wants, exist_ok=True)
    link = os.path.join(wants, "r36-hostkeys.service")
    if os.path.islink(link) or os.path.exists(link):
        os.remove(link)
    os.symlink("/etc/systemd/system/r36-hostkeys.service", link)
    # ssh.service must not start before the keys exist
    dropin = os.path.join(R, "etc/systemd/system/ssh.service.d")
    os.makedirs(dropin, exist_ok=True)
    with open(os.path.join(dropin, "r36-hostkeys.conf"), "w") as f:
        f.write("[Unit]\nRequires=r36-hostkeys.service\nAfter=r36-hostkeys.service\n")
    print("  installed r36-hostkeys.service (+ ssh.service.d ordering)")
    print("  ssh host keys left in the image: %d" % len(glob.glob(os.path.join(R, "etc/ssh/ssh_host_*"))))
    clean = not hits and not bad
    print("=== %s ===" % ("image carries no credentials" if clean else "STOP: secrets still present"))
    return 0 if clean else 1


sys.exit(main())
