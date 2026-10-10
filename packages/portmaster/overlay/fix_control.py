#!/usr/bin/env python3
"""Teach PortMaster's get_controls() about this board's joypad.

Why this is needed, measured on the device rather than assumed:

get_controls() decides which SDL game-controller mapping to hand to a port by
probing /dev/input/by-path/ for a list of known joypads, and ends with
    else  DEVICE="${1}"; param_device="${2}"
and then
    grep "${SDLDBUSERFILE}" -e "${DEVICE}" > /tmp/gamecontrollerdb.txt
    sdl_controllerconfig="$(< "${SDL_GAMECONTROLLERCONFIG_FILE}")"

This board's node is platform-rocknix-singleadc-joypad-event-joystick (module
rocknix_singleadc_joypad), while the closest branch looks for
platform-singleadc-joypad-event-joystick without the "rocknix-" prefix - so no
branch matched. Running a port from ES calls get_controls with no arguments, so
DEVICE stayed empty, and grep with an empty pattern matches every line: the whole
1798-line gamecontrollerdb.txt (~472 KB) landed in a single environment variable.
That is past MAX_ARG_STRLEN (128 KB), so every execve afterwards failed with E2BIG -
"Argument list too long" on sudo, on pidof, and on the game binary - and no port
could start at all.

Adding the branch fixes both halves at once: DEVICE becomes this pad's GUID, the
grep narrows to the one mapping line, and SDL gets buttons that actually match the
hardware (see the a/b and x/y note in packages/rk3326/es-launcher/
es-input-r36max2.cfg - the entry shipped in the upstream database has them swapped
for this board).

Idempotent: re-running it is a no-op, and a PortMaster update that replaces
control.txt gets re-patched on the next start.
"""
import sys

PATH = "/roms/ports/PortMaster/control.txt"
MARK = "r36max2:"
GUID = "19009b4d4b4800000111000000010000"
ANCHOR = '  else\n    DEVICE="${1}"'

BRANCH = (
    '  elif [[ -e "/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick" ]]; then\n'
    f'    # {MARK} the node carries the rocknix- prefix, so the singleadc branch above\n'
    '    # never matches here. An unmatched chain leaves DEVICE empty, the DB grep below\n'
    '    # then matches every line, and one 472 KB environment variable makes every\n'
    '    # execve fail with E2BIG - no port can start.\n'
    f'    DEVICE="{GUID}"\n'
    '    param_device="r36max2"\n'
    '    ANALOGSTICKS="2"\n'
    '    LOWRES="N"\n'
)

try:
    s = open(PATH, encoding="utf-8", errors="surrogateescape").read()
except OSError as e:
    print(f"fix_control: cannot read {PATH}: {e}", file=sys.stderr)
    sys.exit(1)

if MARK in s:
    sys.exit(0)

if s.count(ANCHOR) != 1:
    print(f"fix_control: expected exactly one get_controls else-branch in control.txt, "
          f"found {s.count(ANCHOR)} - PortMaster changed, refusing to guess", file=sys.stderr)
    sys.exit(1)

open(PATH, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(ANCHOR, BRANCH + ANCHOR, 1))
print("fix_control: added the r36max2 joypad branch")
