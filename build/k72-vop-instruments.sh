#!/bin/bash
# k72-vop-instruments.sh - what instrumentation does THIS kernel actually allow?
# tracefs was missing, so decide between (a) rebuilding the kernel with tracing and
# (b) a no-rebuild instrument: DRM's own runtime debug categories, which the vblank
# core itself writes to (drm_dbg_vbl / drm_dbg_crtc).  Also confirm the real names
# and writability of the parameters on the running board.
set -uo pipefail
K=${K:-/root/r36/linux-7.2.8}
PW=ubuntu
DEV=${DEV:-192.168.31.209}

echo "=== [local] kernel tree $K ==="
C=$K/.config
if [ -f "$C" ]; then
  echo "  tracing-relevant config lines:"
  grep -E "^(CONFIG_FTRACE|CONFIG_DYNAMIC_FTRACE|CONFIG_KPROBES|CONFIG_KPROBE_EVENTS|CONFIG_TRACING|CONFIG_FUNCTION_TRACER|CONFIG_DEBUG_FS|CONFIG_KALLSYMS|CONFIG_KALLSYMS_ALL)=" "$C" | sed 's/^/    /'
  echo "  ...and what was explicitly turned off:"
  grep -E "^# (CONFIG_FTRACE|CONFIG_KPROBES|CONFIG_KPROBE_EVENTS|CONFIG_TRACING|CONFIG_DYNAMIC_FTRACE) is not set" "$C" | sed 's/^/    /'
else
  echo "  !! no .config at $C"
fi
echo
echo "  DRM debug category bits (include/drm/drm_print.h):"
grep -nE "define DRM_UT_[A-Z]+" "$K/include/drm/drm_print.h" 2>/dev/null | sed 's/^/    /'
echo
echo "  which debug macros the vblank core uses (so we know what will print):"
grep -ohrE "drm_dbg_(vbl|crtc|core|kms)" "$K/drivers/gpu/drm/drm_crtc_helper.c" "$K/drivers/gpu/drm/drm_atomic_helper.c" "$K/drivers/gpu/drm/drm_vblank.c" 2>/dev/null | sort | uniq -c | sed 's/^/    /'
echo
echo "  is rockchipdrm built-in or a module?"
grep -E "^CONFIG_DRM_ROCKCHIP=" "$C" 2>/dev/null | sed 's/^/    config says /'
ls "$K/drivers/gpu/drm/rockchip/rockchipdrm.ko" 2>/dev/null | sed 's/^/    module exists: /' || echo "    (no rockchipdrm.ko -> built-in)"

echo
echo "=== [device] runtime knobs on the running board ==="
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  /sys/module/drm/parameters:"
for f in /sys/module/drm/parameters/*; do
  [ -e "$f" ] || continue
  echo "     $(basename $f) = $(cat $f 2>/dev/null)   $(ls -l $f | awk '{print $1}')"
done
echo "  /sys/module/rockchipdrm/parameters (if it is a module):"
ls /sys/module/rockchipdrm/parameters 2>/dev/null | sed 's/^/     /' || echo "     (no rockchipdrm module dir -> built-in)"
echo "  tracing dirs present: $(ls /sys/kernel/debug/ 2>/dev/null | tr '\n' ' ')"
echo "  /proc/sys/kernel/ftrace_enabled = $(cat /proc/sys/kernel/ftrace_enabled 2>/dev/null || echo absent)"
echo "  kallsyms has the vop functions? $(grep -cw vop_crtc_enable_vblank /proc/kallsyms 2>/dev/null) enable, $(grep -cw vop_crtc_disable_vblank /proc/kallsyms 2>/dev/null) disable, $(grep -cw vop_isr /proc/kallsyms 2>/dev/null) isr"
echo "  debug messages already in flight:"
echo "     vblank-related kernel lines this boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -icE 'vblank|drm_dbg')"
EOS
echo "=== instrument probe done ==="
