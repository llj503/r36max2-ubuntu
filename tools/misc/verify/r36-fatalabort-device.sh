#!/bin/sh
# r36-fatalabort-device.sh - last remaining shape of the "pending flip" theory,
# and the one that actually matches the original incident.
#
# The log line we are chasing came from weston's OWN exit path:
#     [..] Loading module desktop-shell.so
#     fatal: unhandled option: --tty=/dev/tty2
#     ...
#     destroying output DSI-1 (id 0) with a pending flip, but as we are shutting
#     down we can't wait to destroy it when the flip completes... destroying it now
# i.e. weston had already modeset the output and started compositing, THEN aborted
# during startup.  Neither SIGKILL nor systemctl-stop reproduces that (they never
# produce the "pending flip" line at all - just proven), so reproduce the real
# thing: start weston with a bogus option so it dies right after its first flips.
#
# Also answers a question the user's photo raised: the desktop came out bright
# blue, not the 0x102030 we configured, so dump what weston thought about the
# background keys.
PROBE="/usr/local/bin/r36-flipprobe 40 15"
PROBE_RC=0

count_err() {
	journalctl -b --no-pager -k 2>/dev/null |
		grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out'
}
pending_lines() { journalctl -b --no-pager -u weston 2>/dev/null | grep -c 'pending flip'; }
run_probe() {
	$PROBE > /tmp/flipprobe.out 2>&1
	PROBE_RC=$?
	sed 's/^/      /' /tmp/flipprobe.out
	echo "  [$1] probe rc=$PROBE_RC  kernel errors=$(count_err)"
}
back_to_console() { chvt 1 2>/dev/null; systemctl restart getty@tty1 2>/dev/null; sleep 1; }

echo "  start: weston=$(systemctl is-active weston) errors=$(count_err) pending-flip-lines=$(pending_lines)"
[ -x /usr/local/bin/r36-flipprobe ] || { echo "  !! probe missing"; exit 5; }
systemctl stop weston 2>/dev/null
sleep 2
back_to_console
run_probe baseline
[ "$PROBE_RC" = 0 ] || { echo "  !! baseline not clean (rc=$PROBE_RC)"; exit 4; }
base_pending=$(pending_lines)

echo
echo "=== [1] weston that aborts during startup, after it has modeset and flipped ==="
a=1
while [ $a -le 4 ]; do
	echo "  --- attempt $a: weston -B drm with a bogus trailing option ---"
	mkdir -p /run/wayland
	XDG_RUNTIME_DIR=/run/wayland timeout 25 /usr/bin/weston -B drm \
		--config=/etc/xdg/weston/weston.ini --this-option-does-not-exist \
		>/tmp/fatal-$a.log 2>&1
	echo "    exit=$? ; last lines:"
	tail -5 /tmp/fatal-$a.log | sed 's/^/      /'
	sleep 3
	back_to_console
	run_probe "fatal-abort-$a"
	[ "$PROBE_RC" = 0 ] || {
		echo "  ==> REPRODUCED: weston aborting after its first flips stalls the pipeline"
		journalctl -b --no-pager -k | grep -E 'rockchip-drm|drm_atomic_helper' | tail -6 | sed 's/^/      kernel: /'
		exit 1
	}
	a=$((a + 1))
done

echo
echo "=== [2] same, but let it composite a real client first ==="
systemctl start weston
i=0
while [ $i -lt 20 ]; do sleep 1; i=$((i + 1)); [ -S /run/wayland/wayland-0 ] && break; done
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
timeout 10 weston-simple-egl >/dev/null 2>&1 &
sleep 3
XDG_RUNTIME_DIR=/run/wayland timeout 25 /usr/bin/weston -B drm \
	--config=/etc/xdg/weston/weston.ini --this-option-does-not-exist \
	>/tmp/fatal-client.log 2>&1
echo "  second-weston exit=$? (a second compositor normally refuses the card; check the log)"
tail -4 /tmp/fatal-client.log | sed 's/^/      /'
wait 2>/dev/null
systemctl stop weston
sleep 3
back_to_console
run_probe with-client

echo
echo "=== [3] why did the desktop look bright blue? what did weston say about the background ==="
grep -nE "background|colour|color" /etc/xdg/weston/weston.ini | sed 's/^/  ini:   /'
journalctl -b --no-pager -u weston | grep -iE "background|invalid|panel-color" | tail -6 | sed 's/^/  log:   /'
echo "  (weston 14 keys: [shell] background-image / background-type / background-color=0xRRGGBBAA)"

echo
echo "=== result: fatal startup abort did not wedge it either ==="
echo "  pending-flip lines before/after: $base_pending / $(pending_lines)   errors=$(count_err)"
exit 0
