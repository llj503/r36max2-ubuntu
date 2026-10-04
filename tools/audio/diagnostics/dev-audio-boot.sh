#!/bin/bash
# dev-audio-boot.sh - check whether r36-audio actually ran at boot (the sound card
# appears late because of deferred probing, so After=sound.target may be too early),
# and make it robust with a path unit + a wait loop.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=8 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== current mixer state (230 = our value, 140 = 55% = effectively mute) ==="
S 'amixer -c 0 contents 2>/dev/null | grep -E "name=.Master|values=|Playback Mux|Internal" -A3 | head -18'
S 'journalctl -u r36-audio --no-pager -o short-iso 2>/dev/null | tail -4 | sed "s/^/  /"
   echo "  card0 existed at service start? $(stat -c %y /proc/asound/card0 2>/dev/null)"
   echo "  service start: $(systemctl show r36-audio -p ExecMainStartTimestamp --value)"'

echo "=== make it wait for the card, and re-run it now ==="
cat > /tmp/r36-audio <<'EOS'
#!/bin/sh
# r36max2 audio defaults. The sound card only appears after a deferred probe
# (rk817-sound waits for its suppliers), so wait for it instead of assuming
# sound.target means the card is ready.
for i in $(seq 1 60); do [ -e /proc/asound/card0 ] && break; sleep 1; done
[ -e /proc/asound/card0 ] || { echo "r36-audio: no sound card after 60s"; exit 0; }
# 'Master' is steep on the rk817: 55% == -42.85 dB (mute-ish), 230/255 == -9.3 dB
amixer -c 0 sset 'Master' 230,230 >/dev/null 2>&1
amixer -c 0 sset 'Internal Speakers' on >/dev/null 2>&1
# the external amp is fed from the codec's HP outputs per the DT routing; both
# mux positions measured audible, HP is the natural one
for m in SPK HP; do amixer -c 0 sset 'Playback Mux' "$m" >/dev/null 2>&1; done
echo "r36-audio: $(amixer -c 0 sget 'Master' 2>/dev/null | grep -m1 Front | tr -s ' ')"
EOS
sshpass -p ubuntu scp -q /tmp/r36-audio "$DEV:/usr/local/sbin/r36-audio"
S 'chmod 755 /usr/local/sbin/r36-audio
   sed -i "/^After=sound.target/a After=multi-user.target" /etc/systemd/system/r36-audio.service
   systemctl daemon-reload; systemctl restart r36-audio
   journalctl -u r36-audio --no-pager | tail -2 | sed "s/^/  /"
   amixer -c 0 sget Master | grep -m1 Front | sed "s/^/  now: /"'

echo "=== 放 3 秒 440Hz（听听看）==="
S 'timeout 3 speaker-test -D plughw:0,0 -c 2 -t sine -f 440 -l 2 >/dev/null 2>&1; echo "  played"'
