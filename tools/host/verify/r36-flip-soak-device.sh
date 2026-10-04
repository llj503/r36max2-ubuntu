#!/bin/sh
# r36-flip-soak.sh - runs ON the r36max2 (fed by flip-soak-host.sh).
# Long soak of weston with a churning EGL client, watching the kernel's flip
# counters and weston's CPU time (which proves the client is really compositing).
MINUTES=${MINUTES:-12}

count_err() {
	journalctl -b -k 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out'
}
count_warn() {
	journalctl -b -k 2>/dev/null | grep -c 'WARNING: drivers/gpu/drm'
}
wcpu() {
	# cumulative CPU seconds of every weston process (100 Hz ticks)
	ps -o times= -C weston 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'
}

export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0

echo "  pre: weston=$(systemctl is-active weston) errors=$(count_err) warns=$(count_warn)"
systemctl stop r36-keymapper 2>/dev/null
systemctl start weston
i=0
while [ $i -lt 20 ]; do
	sleep 1; i=$((i + 1)); [ -S /run/wayland/wayland-0 ] && break
done
echo "  weston up after ${i}s, socket=$(ls /run/wayland 2>/dev/null | tr '\n' ' ')"
[ -S /run/wayland/wayland-0 ] || { echo "!! no socket"; journalctl -u weston -n 12; exit 1; }

echo "=== [A] does a client actually composite here? (CPU time, not vibes) ==="
idle0=$(wcpu); sleep 15; idle1=$(wcpu)
echo "  weston idle 15s      : cpu ${idle0}s -> ${idle1}s  (delta $((idle1 - idle0))s)"
timeout 15 weston-simple-egl >/tmp/soak-egl-probe.log 2>&1
p1=$(wcpu)
echo "  with simple-egl 15s  : cpu ${idle1}s -> ${p1}s  (delta $((p1 - idle1))s)   client output: $(head -c 70 /tmp/soak-egl-probe.log | tr '\n' ' ')"
if [ "$((p1 - idle1))" -lt 3 ]; then
	echo "  !! suspiciously little work - the client may not be attaching; check the log above"
fi

echo
echo "=== [B] soak ${MINUTES} minutes with a client that keeps coming and going ==="
base_err=$(count_err); base_warn=$(count_warn)
cycles=$((MINUTES))
c=0
while [ $c -lt $cycles ]; do
	c=$((c + 1))
	timeout 20 weston-simple-egl >/dev/null 2>&1 &
	cpid=$!
	sleep 20
	kill -9 "$cpid" 2>/dev/null
	wait "$cpid" 2>/dev/null
	sleep 5
	e=$(count_err); w=$(count_warn); a=$(pgrep -c -x weston); cpu=$(wcpu)
	echo "  min $c: weston=$a procs cpu=${cpu}s errors=$((e - base_err)) warns=$((w - base_warn))"
	if [ "$e" != "$base_err" ] || [ "$w" != "$base_warn" ]; then
		echo "  !! reproduced in minute $c"
		journalctl -b -k | grep -E 'rockchip-drm|WARNING: drivers/gpu/drm' | tail -6
		break
	fi
	if [ "$a" = 0 ]; then
		echo "  !! weston died in minute $c"; journalctl -u weston -n 15; break
	fi
done

echo
echo "=== [C] teardown ==="
echo "  final errors=$(count_err) warns=$(count_warn) cpu=$(wcpu)s"
pkill -f weston-simple-egl 2>/dev/null
systemctl stop weston
sleep 2
chvt 1 2>/dev/null
systemctl restart getty@tty1 2>/dev/null
echo "  weston=$(systemctl is-active weston) getty=$(systemctl is-active getty@tty1) vt=$(fgconsole 2>/dev/null) fb0blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
if [ "$(count_err)" != "$base_err" ]; then
	echo "  VERDICT: pageflip-timeout=500 does NOT prevent the wedge"
else
	echo "  VERDICT: ${MINUTES} minutes of churn with pageflip-timeout=500 stayed clean"
fi
