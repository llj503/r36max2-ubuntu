#!/bin/sh
# r36-killmidflip-device.sh - runs ON the r36max2 (pushed by k72-killmidflip.sh).
#
# Test the competing explanation for the weston panel freeze: not "weston ran too
# long" but "weston was SIGKILLed while a page flip was in flight, and the VOP lost
# its vsync completion".  The smoking gun is a line weston only logs when it dies
# with a flip pending:
#     destroying output DSI-1 ... with a pending flip
# so every attempt checks for it, and pipeline health is measured with
# r36-flipprobe, which times flip completions underneath any compositor.
#
# Order is deliberate: the first phase that wedges ends the run, because after a
# wedge every later measurement is meaningless (and the panel needs a reboot).

PROBE="/usr/local/bin/r36-flipprobe 40 15"
PROBE_RC=0

count_err() {
	journalctl -b --no-pager -k 2>/dev/null |
		grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out'
}
pending_flip_lines() {
	journalctl -u weston --no-pager -n 80 2>/dev/null | grep -c 'pending flip'
}
# keep the exit code of the probe itself (piping it through sed would hide it)
run_probe() {
	$PROBE > /tmp/flipprobe.out 2>&1
	PROBE_RC=$?
	sed 's/^/      /' /tmp/flipprobe.out
	echo "  [$1] probe rc=$PROBE_RC  kernel errors=$(count_err)"
}
wait_socket() {
	i=0
	while [ $i -lt 20 ]; do
		sleep 1; i=$((i + 1)); [ -S /run/wayland/wayland-0 ] && return 0
	done
	return 1
}
back_to_console() {
	chvt 1 2>/dev/null
	systemctl restart getty@tty1 2>/dev/null
	sleep 1
}

echo "  kernel $(uname -r)   weston=$(systemctl is-active weston)   vt=$(fgconsole 2>/dev/null)   fb0blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null)   errors=$(count_err)"

echo
echo "=== [0] baseline: no compositor involved at all ==="
if [ ! -x /usr/local/bin/r36-flipprobe ]; then
	echo "  !! r36-flipprobe was not built - fix the compile before running this"
	exit 5
fi
systemctl stop weston 2>/dev/null
sleep 2
back_to_console
run_probe baseline
if [ "$PROBE_RC" = 3 ]; then
	echo "  !! the pipeline is ALREADY stalled (before touching weston) - reboot and re-check"
	exit 4
fi
if [ "$PROBE_RC" != 0 ]; then
	echo "  !! probe failed to run (rc=$PROBE_RC) - not a stall, tooling problem"
	exit 5
fi

echo
echo "=== [1] SIGKILL weston while a client is animating ==="
attempt=1
while [ $attempt -le 7 ]; do
	echo "  --- attempt $attempt (kill ${attempt}s into the animation) ---"
	systemctl stop weston 2>/dev/null
	sleep 2
	systemctl start weston
	wait_socket || { echo "  weston did not come up"; break; }
	export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
	timeout 12 weston-simple-egl >/tmp/killprobe-egl.log 2>&1 &
	sleep "$attempt"
	wp=$(pgrep -x weston | head -1)
	[ -n "$wp" ] || { echo "  no weston pid to kill"; break; }
	kill -9 "$wp"
	echo "  SIGKILLed weston pid $wp; pending-flip lines: $(pending_flip_lines)"
	sleep 3
	back_to_console
	run_probe "kill-attempt-$attempt"
	[ "$PROBE_RC" = 0 ] || {
		echo
		echo "  ==> REPRODUCED: weston killed with a flip in flight stalls the pipeline"
		journalctl -u weston --no-pager -n 14 | sed 's/^/      weston: /'
		journalctl -b --no-pager -k | grep -E 'rockchip-drm|drm_atomic_helper' | tail -5 | sed 's/^/      kernel: /'
		exit 1
	}
	attempt=$((attempt + 2))
done

echo
echo "=== [2] control: SIGKILL while the compositor is idle (no client) ==="
systemctl stop weston 2>/dev/null
sleep 2
systemctl start weston
if wait_socket; then
	kill -9 "$(pgrep -x weston | head -1)" 2>/dev/null
	sleep 3
	back_to_console
	run_probe idle-kill
	[ "$PROBE_RC" = 0 ] || { echo "  !! idle kill stalled it too - not about pending flips"; exit 1; }
fi

echo
echo "=== [3] control: kill storm during animation (6 rounds) ==="
c=1
while [ $c -le 6 ]; do
	systemctl start weston 2>/dev/null
	sleep 2
	export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
	timeout 5 weston-simple-egl >/dev/null 2>&1 &
	sleep 2
	kill -9 "$(pgrep -x weston | head -1)" 2>/dev/null
	wait 2>/dev/null
	c=$((c + 1))
done
sleep 2
back_to_console
run_probe storm
echo
if [ "$PROBE_RC" = 0 ]; then
	echo "=== no phase reproduced it: 'killed mid-flip' is not sufficient on its own ==="
	echo "    pending-flip lines seen in total: $(pending_flip_lines), errors=$(count_err)"
	exit 0
fi
echo "=== the storm reproduced it (rc=$PROBE_RC) ==="
exit 1
