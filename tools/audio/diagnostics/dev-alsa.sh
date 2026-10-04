#!/bin/bash
# dev-alsa.sh - install the audio + input tools the verified system actually used,
# then prove r36-audio can do its job and make real noise.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== install alsa-utils + evtest (small) and kick off the dev baseline in the background ==="
S 'export DEBIAN_FRONTEND=noninteractive
   apt-get update -qq >/dev/null 2>&1
   apt-get -y -qq install alsa-utils evtest input-utils >/dev/null 2>&1
   nohup apt-get -y install build-essential git vim curl wget htop tmux tree jq rsync unzip pkg-config file </dev/null >/root/setup.log 2>&1 &
   echo "  dev baseline installing in background (pid $!, log /root/setup.log)"
   echo "  amixer       : $(command -v amixer || echo MISSING)"
   echo "  speaker-test : $(command -v speaker-test || echo MISSING)"
   echo "  evtest       : $(command -v evtest || echo MISSING)"'

echo "=== restart r36-audio and read back the mixer ==="
S 'systemctl restart r36-audio
   sleep 1
   journalctl -u r36-audio --no-pager -o cat 2>/dev/null | tail -2 | sed "s/^/  /"
   amixer -c 0 sget Master 2>/dev/null | grep -m1 Front | sed "s/^/  Master: /"
   amixer -c 0 sget "Playback Mux" 2>/dev/null | grep Item0 | sed "s/^/  Mux:    /"
   amixer -c 0 sget "Internal Speakers" 2>/dev/null | grep Mono | sed "s/^/  Spk:    /"'

echo "=== 存一份 alsactl 状态，万一服务没跑也有兜底 ==="
S 'alsactl -f /var/lib/alsa/asound.state store 2>/dev/null && echo "  state stored ($(wc -l < /var/lib/alsa/asound.state) lines)" || echo "  alsactl store failed"
   systemctl enable alsa-restore 2>/dev/null | head -1'

echo "=== 真放音：1.5s 440Hz，停 1s，1.5s 880Hz ==="
S 'timeout 2 speaker-test -D plughw:0,0 -c 2 -t sine -f 440 -l 1 >/dev/null 2>&1
   sleep 1
   timeout 2 speaker-test -D plughw:0,0 -c 2 -t sine -f 880 -l 1 >/dev/null 2>&1
   echo "  played 440 then 880"'
