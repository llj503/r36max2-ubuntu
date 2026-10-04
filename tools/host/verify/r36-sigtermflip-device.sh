#!/bin/sh
# r36-sigtermflip-device.sh - the SIGKILL round did not reproduce the wedge, and
# running it taught us why: the smoking-gun log line
#     destroying output DSI-1 (id 0) with a pending flip
# was preceded by "caught signal 15".  SIGKILL cannot produce either - a killed
# process logs nothing.  That message therefore came from a *graceful* shutdown
# (SIGTERM) that ran weston's own teardown path while a page flip was outstanding,
# and the instance that printed it was one whose startup had aborted right after
# modesetting (the "unhandled option --tty" failure).
#
# So: reproduce with SIGTERM instead, in two shapes - during animation, and during
# the first flips right after start.  r36-flipprobe measures the consequence below
# the compositor, so a lost vsync completion shows up as flip timeouts.
PROBE="/usr/local/bin/r36-flipprobe 40 15"
PROBE_RC=0

count_err() {
	journalctl -b --no-pager -k 2>/dev/null |
		grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out'
}
pending_lines() { journalctl -u weston --no-pager -n 120 2>/dev/null | grep -c 'pending flip'; }
run_probe() {
	$PROBE > /tmp/flipprobe.out 2>&1
	PROBE_RC=$?
	sed 's/^/      /' /tmp/flipprobe.out
	echo "  [$1] probe rc=$PROBE_RC  kernel errors=$(count_err)"
}
back_to_console() { chvt 1 2>/dev/null; systemctl restart getty@tty1 2>/dev/null; sleep 1; }
start_weston() {
	systemctl start weston
	i=0
	while [ $i -lt 20 ]; do
		sleep 1; i=$((i + 1)); [ -S /run/wayland/wayland-0 ] && return 0
	done
	return 1
}

echo "  kernel $(uname -r)  errors=$(count_err)  vt=$(fgconsole 2>/dev/null)"
[ -x /usr/local/bin/r36-flipprobe ] || { echo "  !! probe missing"; exit 5; }

echo "=== [0] baseline ==="
systemctl stop weston 2>/dev/null
sleep 2
back_to_console
run_probe baseline
[ "$PROBE_RC" = 0 ] || { echo "  !! not clean at baseline (rc=$PROBE_RC) - reboot first"; exit 4; }

echo
echo "=== [1] SIGTERM during animation (weston's own teardown path) ==="
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
a=1
while [ $a -le 6 ]; do
	systemctl stop weston 2>/dev/null
	sleep 2
	start_weston || { echo "  weston did not start"; break; }
	timeout 20 weston-simple-egl >/tmp/st-egl.log 2>&1 &
	sleep "$a"
	echo "  --- attempt $a: systemctl stop (SIGTERM) ${a}s into the animation ---"
	systemctl stop weston
	wait 2>/dev/null
	sleep 3
	back_to_console
	echo "  pending-flip lines: $(pending_lines)"
	run_probe "sigterm-anim-$a"
	[ "$PROBE_RC" = 0 ] || {
		echo "  ==> REPRODUCED: SIGTERM teardown during animation stalls the pipeline"
		journalctl -u weston --no-pager -n 16 | sed 's/^/      weston: /'
		exit 1
	}
	a=$((a + 1))
done

echo
echo "=== [2] SIGTERM seconds after start (teardown while the first flips fly) ==="
b=1
while [ $b -le 5 ]; do
	systemctl stop weston 2>/dev/null
	sleep 2
	echo "  --- attempt $b: stop $((b * 2))s after start, no client ---"
	systemctl start weston
	sleep "$((b * 2))"
	systemctl stop weston
	sleep 3
	back_to_console
	echo "  pending-flip lines: $(pending_lines)"
	run_probe "sigterm-startup-$b"
	[ "$PROBE_RC" = 0 ] || {
		echo "  ==> REPRODUCED: stopping weston right after start stalls the pipeline"
		journalctl -u weston --no-pager -n 16 | sed 's/^/      weston: /'
		exit 1
	}
	b=$((b + 1))
done

echo
echo "=== neither SIGTERM shape reproduced it ==="
echo "  total pending-flip lines seen: $(pending_lines)   kernel errors: $(count_err)"
echo "  => the wedge is not explained by 'weston torn down with a flip pending' either;"
echo "     remaining suspects: elapsed time / idle-blank + repaint resume / many surfaces."
exit 0
