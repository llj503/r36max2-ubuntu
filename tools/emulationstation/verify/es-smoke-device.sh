#!/bin/sh
# es-smoke-device.sh - the device-side half of k72-es-smoke.sh, rewritten as POSIX sh so
# the board can run it BY ITSELF once the binary appears (no ssh session has to stay
# open, no host-side relay has to be re-armed every 9 minutes).
#
# Run on the board:   PHASE=A WAIT=25 sh /root/es-smoke-device.sh > /tmp/es-smoke-A.txt 2>&1
# It is deliberately the same logic that k72-es-smoke.sh used, so results are comparable:
#   phase A: no es_systems.cfg at all  -> is it the binary/GL/window path or the theme?
#   phase B: one fake system whose "launch" writes a marker file, driven by injected keys
set -u

ESBIN=${ESBIN:-/root/esrn/build/es-app/emulationstation}
PHASE=${PHASE:-A}
WAIT=${WAIT:-25}
E=/root/.emulationstation
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0 HOME=/root

stalls() { journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out'; }

start_es() {
  # Only flags this fork actually parses (--no-splash, --ignore-gamelist, --debug,
  # --windowed, --fullscreen, --no-exit).  It has no --no-update-check and exits on an
  # unknown option, which otherwise looks exactly like "ES cannot start on this hardware".
  setsid stdbuf -oL -eL "$ESBIN" --no-splash > "$1" 2>&1 &
}
# The pattern must come from ESBIN.  'es-app/emulationstation' matches the ROCKNIX tree's
# path but NOT this fork's /root/es/emulationstation, so both the alive check and the kill
# silently matched nothing (an "alive: 0" that proved nothing, and an ES left running).
alive_es() { pgrep -c -f "$ESBIN" 2>/dev/null | head -1; }
stop_es() { pkill -f "$ESBIN" 2>/dev/null; sleep 2; pkill -x emulationstation 2>/dev/null; sleep 1; }

echo "=== es-smoke phase=$PHASE at $(date '+%F %T')  host=$(hostname)  up=$(cut -d' ' -f1 /proc/uptime)s ==="
[ -x "$ESBIN" ] || { echo "  !! $ESBIN missing"; exit 1; }
echo "  ES binary: $(ls -l "$ESBIN" | awk '{print $5}') bytes  (built $(stat -c '%y' "$ESBIN" | cut -c1-19))"

help=$("$ESBIN" --help 2>&1 | head -40)
if echo "$help" | grep -q -- '--no-splash'; then
  echo "  --no-splash is accepted by this build"
else
  echo "  !! --no-splash not in its usage text - refusing to guess"
  echo "$help" | head -20 | sed 's/^/     /'
  exit 1
fi

systemctl is-active weston >/dev/null || { echo "  starting weston"; systemctl restart weston; }
sleep 3
systemctl is-active r36-keymapper >/dev/null || { echo "  starting r36-keymapper"; systemctl restart r36-keymapper; }
[ -f "$E/es_input.cfg" ] || echo "  (no es_input.cfg yet - keyboard defaults still work)"

echo
echo "############ PHASE A: an EMPTY but valid system list ############"
# Measured 2026-10-03 20:11 on this very binary: with no es_systems.cfg at all, batocera's
# ES logs "ERROR es_systems.cfg file does not exist!" + "Error while parsing systems
# configuration file!" and EXITS.  So "install nothing and see if it survives" is not a
# valid phase-A design for this fork - it proves nothing about the renderer.  A present but
# empty <systemList/> still gives zero systems (hence no theme is needed), which is the
# isolation this phase was supposed to provide.
[ -f "$E/es_systems.cfg" ] && mv "$E/es_systems.cfg" "$E/es_systems.cfg.bak"
mkdir -p "$E"
printf '<systemList>\n</systemList>\n' > "$E/es_systems.cfg"
echo "  wrote an empty $E/es_systems.cfg (zero systems -> no theme lookup)"
a0=$(stalls)
start_es /tmp/es-a.log
sleep "$WAIT"
aliveA=$(alive_es); aliveA=${aliveA:-0}
echo "  alive after ${WAIT}s: $aliveA    kernel stalls: $a0 -> $(stalls)"
echo "  --- stdout/stderr ---"
head -25 /tmp/es-a.log 2>/dev/null | sed 's/^/     /'
echo "  --- weston saw what? (last 20 lines since ES started) ---"
journalctl -u weston --no-pager --since "-${WAIT} seconds" 2>/dev/null | tail -12 | sed 's/^/     /'
echo "  --- es_log.txt tail ---"
if [ -f "$E/es_log.txt" ]; then tail -12 "$E/es_log.txt" | sed 's/^/     /'; else echo "     (no es_log.txt)"; fi
echo "  --- what ES created in $E ---"
ls -l "$E" 2>/dev/null | sed 's/^/     /'
echo "  --- is there a weston surface at all? (clients seen by the compositor) ---"
ls -l /run/wayland/ 2>/dev/null | sed 's/^/     /'
wm_list=$(ls "$XDG_RUNTIME_DIR/wayland"* 2>/dev/null | tr '\n' ' ')
echo "      sockets: ${wm_list:-none}"
stop_es
echo "  after stop: procs=$(alive_es 2>/dev/null || echo 0)  weston=$(systemctl is-active weston)"
rm -f "$E/es_systems.cfg"

if [ "$PHASE" = "A" ]; then
  echo "  PHASE=A done - nothing added to $E except what ES wrote itself"
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
aliveB=$(alive_es 2>/dev/null); aliveB=${aliveB:-0}
echo "  alive after ${WAIT}s: $aliveB   stalls: $b0 -> $(stalls)"
echo "  --- its output ---"
head -25 /tmp/es-b.log 2>/dev/null | sed 's/^/     /'
if [ "$aliveB" = 0 ] || [ -z "$aliveB" ]; then
  echo "  !! ES exited with a system configured - theme/GL is the suspect; see output above"
  exit 1
fi

echo "  --- driving it with injected keys: ENTER (system view -> list), ENTER (list -> launch) ---"
# Two corrections, both measured on this board at 20:23:
#   * DOWN,DOWN was the original guess.  With a single system the cursor has nowhere to go,
#     so it changed nothing; the path in from the system view is ENTER.
#   * RETURN is not a name r36-osk knows (its table says ENTER).  The old rig piped its
#     output to /dev/null, so "injected 0/1 key presses" was invisible and the run looked
#     like "ES ignored the keys".  r36-osk now also exits non-zero on an unknown name.
for k in ENTER ENTER; do
  out=$(/usr/local/bin/r36-osk --keys "$k" 2>&1)
  rc=$?
  echo "      $out"
  case "$out" in
    *"1/1"*) ;;
    *) echo "      !! injection failed (rc=$rc) - nothing can be concluded about ES here" ;;
  esac
  sleep 4
done
sleep 8
echo "  marker file : $(cat /tmp/es-demo-launched.txt 2>/dev/null || echo 'not created')"
echo "  ES still up : $(alive_es 2>/dev/null || echo 0)   (live ES after launch = the round trip back to the list worked)"
echo "  gamelist side effects:"
find "$E" -name gamelist.xml 2>/dev/null | head -3 | sed 's/^/     /'
grep -hoE '<playCount>[0-9]+</playCount>|<lastPlayed>[^<]*</lastPlayed>|<name>[^<]*</name>' \
  "$E"/gamelist/demo/gamelist.xml "$E"/gamelist.xml 2>/dev/null | head -6 | sed 's/^/     /'
echo "  ES settings written? $(ls -l "$E/es_settings.cfg" 2>/dev/null | awk '{print $5" bytes"}')"
echo
echo "  final: stalls=$(stalls)  weston complaints last 3 min: $(journalctl -u weston --no-pager --since '-3 minutes' 2>/dev/null | grep -cE 'Device or resource busy|repaint-flush failed')"
echo "  ES is left running so the panel can be looked at; stop: pkill -f "$ESBIN""
