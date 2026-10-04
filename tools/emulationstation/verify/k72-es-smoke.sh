#!/bin/bash
# k72-es-smoke.sh - end-to-end EmulationStation check, staged so that "the program
# does not run" and "there is no theme installed" cannot be confused with each other.
#
#   phase A: no es_systems.cfg at all  -> does ES come up and stay up? (nothing to
#            render a theme for, so a failure here is the binary/GL/window path)
#   phase B: a demo system whose "launch" just writes a marker file -> theme handling,
#            list rendering, and the launch round trip
#
# Driving it blind: ES keeps compiled-in keyboard defaults (arrows navigate, Return is
# A/OK), and r36-osk can inject those keys through /dev/uinput from ssh, so phase B
# presses DOWN/UP/RETURN itself and then reads ES's own side effects (marker file,
# gamelist.xml playCount/lastPlayed, es log, stall counter).  Only "what the panel
# actually shows" still needs a human.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WAIT=${WAIT:-20}
PHASE=${PHASE:-all}          # A = window/GL/UI only, B = + demo system + driving
ESBIN=/root/esrn/build/es-app/emulationstation
timeout 480 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "WAIT=$WAIT ESBIN=$ESBIN PHASE=$PHASE sh -s" <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0 HOME=/root
E=~/.emulationstation
stalls() { journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out'; }
start_es() {
  # Only flags this fork actually parses (main.cpp: --no-splash, --ignore-gamelist,
  # --debug, --windowed, --fullscreen, --no-exit ...).  It has no --no-update-check,
  # and ES exits on an option it does not know - which would have looked exactly like
  # "ES cannot start on this hardware".
  (setsid stdbuf -oL -eL "$ESBIN" --no-splash > "$1" 2>&1 &)
}
stop_es()  { pkill -f 'es-app/emulationstation' 2>/dev/null; sleep 2; }

[ -x "$ESBIN" ] || { echo "  !! $ESBIN missing - build still running? (k72-esrn.sh status)"; exit 1; }
echo "  host=$(hostname)  ES binary: $(ls -l $ESBIN | awk '{print $5}') bytes"
# self-check the flags we are about to pass: ES exits on an option it does not know,
# and that exit is otherwise indistinguishable from a broken renderer
help=$($ESBIN --help 2>&1 | head -40)
echo "$help" | grep -q -- "--no-splash" && echo "  --no-splash is accepted by this build" || { echo "  !! --no-splash not in its usage text - refusing to guess"; echo "$help" | head -20 | sed 's/^/     /'; exit 1; }
systemctl is-active weston >/dev/null || systemctl restart weston
sleep 3
systemctl is-active r36-keymapper >/dev/null || systemctl restart r36-keymapper
[ -f "$E/es_input.cfg" ] || echo "  (no es_input.cfg yet - run k72-es-inputcfg.sh; keyboard defaults still work)"

echo
echo "############ PHASE A: no systems configured at all ############"
[ -f "$E/es_systems.cfg" ] && mv "$E/es_systems.cfg" "$E/es_systems.cfg.bak"
a0=$(stalls)
start_es /tmp/es-a.log
sleep "$WAIT"
aliveA=$(pgrep -c -f 'es-app/emulationstation')
echo "  alive after ${WAIT}s: $aliveA    stalls: $a0 -> $(stalls)"
echo "  --- stdout/stderr ---"
head -22 /tmp/es-a.log 2>/dev/null | sed 's/^/     /'
echo "  --- es_log.txt tail ---"
tail -10 "$E/es_log.txt" 2>/dev/null | sed 's/^/     /' || echo "     (none)"
stop_es

if [ "$PHASE" = "A" ]; then
  echo "  PHASE=A: stopping here - nothing was added to ~/.emulationstation except what ES wrote itself"
  exit 0
fi

echo
echo "############ PHASE B: one demo system (launch = write a marker) ############"
mkdir -p /root/roms/demo
cat > /root/roms/demo/mario.sh <<'DEMO'
#!/bin/sh
echo "ES launched the demo at $(date +%T)" > /tmp/es-demo-launched.txt
DEMO
chmod 755 /root/roms/demo/mario.sh
cat > "$E/es_systems.cfg" <<'SYS'
<systemList>
  <system>
    <name>demo</name>
    <fullname>R36 demo system</fullname>
    <manufacturer>local</manufacturer>
    <release>2026</release>
    <hardware>test</hardware>
    <path>/root/roms/demo</path>
    <extension>.sh</extension>
    <command>%ROM%</command>
    <platform>pc</platform>
    <theme>pc</theme>
  </system>
</systemList>
SYS
rm -f /tmp/es-demo-launched.txt
b0=$(stalls)
start_es /tmp/es-b.log
sleep "$WAIT"
aliveB=$(pgrep -c -f 'es-app/emulationstation')
echo "  alive after ${WAIT}s: $aliveB   stalls: $b0 -> $(stalls)"
echo "  --- its output ---"
head -25 /tmp/es-b.log 2>/dev/null | sed 's/^/     /'
if [ "$aliveB" = 0 ]; then
  echo "  !! ES exited with a system configured - the theme/GL path is the suspect; see output above"
  exit 1
fi

echo "  --- driving it with injected keyboard keys (DOWN DOWN RETURN) ---"
for k in DOWN DOWN RETURN; do
  /usr/local/bin/r36-osk --keys $k >/dev/null 2>&1
  sleep 2
done
sleep 8
echo "  marker file : $(cat /tmp/es-demo-launched.txt 2>/dev/null || echo 'not created')"
echo "  ES still up : $(pgrep -c -f 'es-app/emulationstation')   (a live ES after launch means the round trip back to the list worked)"
echo "  gamelist side effects:"
find "$E" -name gamelist.xml 2>/dev/null | head -3 | sed 's/^/     /'
grep -hoE '<playCount>[0-9]+</playCount>|<lastPlayed>[^<]*</lastPlayed>|<name>[^<]*</name>' \
  "$E"/gamelist/demo/gamelist.xml "$E"/gamelist.xml 2>/dev/null | head -6 | sed 's/^/     /'
echo "  ES settings written? $(ls -l $E/es_settings.cfg 2>/dev/null | awk '{print $5" bytes"}')"
echo
echo "  final: stalls=$(stalls)  weston complaints last 3 min: $(journalctl -u weston --no-pager --since '-3 minutes' 2>/dev/null | grep -cE 'Device or resource busy|repaint-flush failed')"
echo "  ES is left running so the panel can be looked at; stop: pkill -f es-app/emulationstation"
EOS
echo "=== smoke finished (rc=$?) ==="
