#!/bin/bash
# dev-safety.sh - mask suspend (it sleeps but cannot wake), fix the locale warning,
# and make the audio settings survive a reboot.
set -uo pipefail
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== 1. 电源键彻底不动作 + 屏蔽 suspend（直到唤醒修好）==="
S 'mkdir -p /etc/systemd/logind.conf.d
   cat > /etc/systemd/logind.conf.d/99-r36-power.conf <<EOF
# r36max2: 短按电源键不能关机（曾经直接 poweroff），也不能睡眠（睡下去叫不醒）。
# 唤醒链路修好之前，HandlePowerKey 保持 ignore，长按 3-5 秒仍会硬件强制断电。
[Login]
HandlePowerKey=ignore
HandlePowerLongKey=poweroff
IdleAction=ignore
IdleActionSec=0
RemoveIPC=no
EOF
   systemctl restart systemd-logind
   systemctl mask suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target 2>&1 | sed "s/^/  /"
   echo "  HandlePowerKey=$(loginctl show-user root 2>/dev/null | head -0; grep -h HandlePowerKey /etc/systemd/logind.conf.d/99-r36-power.conf)"'

echo "=== 2. /etc/default/locale（消掉 pam_env 的报错）==="
S 'printf 'LANG=C.UTF-8\n' > /etc/default/locale; cat /etc/default/locale'

echo "=== 3. 开机自动设音频路由（mux + 音量），并探测哪一路真的响 ==="
cat > /tmp/r36-audio <<'EOS'
#!/bin/sh
# r36max2: the rk817 'Master' control is very steep (55% == -42 dB), and the
# external speaker amp is fed from the codec's HP outputs per the DT routing.
[ -d /proc/asound/card0 ] || exit 0
amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1
amixer -c 0 sset 'Internal Speakers' on >/dev/null 2>&1
# external speaker amp is fed from the codec's HP outputs per the DT routing, so
# leave the mux on HP (that is the position that measured audible).
for m in SPK HP; do
    amixer -c 0 sset 'Playback Mux' "$m" >/dev/null 2>&1 && echo "r36-audio: Playback Mux -> $m"
done
exit 0
EOS
sshpass -p "$PW" scp -q /tmp/r36-audio "$DEV:/usr/local/sbin/r36-audio"
cat > /tmp/r36-audio.service <<'EOS'
[Unit]
Description=r36max2 audio defaults (amp mux + realistic volume)
After=sound.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/r36-audio
[Install]
WantedBy=multi-user.target
EOS
sshpass -p "$PW" scp -q /tmp/r36-audio.service "$DEV:/etc/systemd/system/r36-audio.service"
S 'chmod 755 /usr/local/sbin/r36-audio; chmod 644 /etc/systemd/system/r36-audio.service
   ln -sf /etc/systemd/system/r36-audio.service /etc/systemd/system/multi-user.target.wants/r36-audio.service
   systemctl daemon-reload; systemctl restart r36-audio; cat /proc/asound/cards | tail -2
   amixer -c 0 sget "Playback Mux" | grep Item0; amixer -c 0 sget Master | grep Front'

echo "=== 4. 现在的显示状态（顺便看有没有睡坏的痕迹）==="
S 'cat /sys/class/drm/card0-DSI-1/status 2>/dev/null; cat /sys/class/backlight/*/brightness 2>/dev/null; dmesg | grep -iE "drm|panel|dsi" | tail -5'
