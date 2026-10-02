#!/bin/bash
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
echo "=== did systemd-sysv give us /sbin/init? ==="
ls -la "$ROOT/sbin/init" "$ROOT/usr/sbin/init" 2>&1 | tail -3
chroot "$ROOT" /bin/sh -c 'dpkg -l | grep -E "^ii +(systemd-sysv|dbus|avahi-daemon|wireless-regdb) "' 2>/dev/null
echo
echo "=== sound: what is the real Kconfig symbol for simple-audio-card? ==="
cd "$K"
grep -rn "config SND_SOC" sound/soc/generic/Kconfig 2>/dev/null | head
echo "--- where does simple-card.o get built from? ---"
grep -rn "simple-card" sound/soc/generic/Makefile sound/soc/Makefile 2>/dev/null | head
echo "--- current config state of those symbols ---"
grep -nE "SND_SOC_SIMPLE_AUDIO_CARD|SND_SOC_AUDIO_GRAPH_CARD|SND_SOC_GENERIC" .config | head
echo "--- was the object actually built? ---"
find sound -name "*simple*card*.o" -o -name "audio-graph-card2*o" 2>/dev/null | head
echo "--- and is it in modules.builtin / installed modules? ---"
grep -c "simple-audio-card\|audio-graph" modules.builtin 2>/dev/null
ls "$ROOT/lib/modules/6.12.79/kernel/sound/soc/generic/" 2>/dev/null
