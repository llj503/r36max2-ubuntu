#!/bin/bash
# k72-osk-focus-restore.sh - picks arrive at r36-osk (6/6 from the user) but the
# typed characters never reach the target window.  The control already proved that
# uinput typing DOES land in foot when foot is the only window, so the question is
# narrow: after wofi exits, is foot the focused surface again - and if yes, is
# 0.15 s simply too early to type?
#
# Reproduced without a human: drive the grid with an injected DOWN,DOWN,ENTER
# through a second transient uinput keyboard, then read the capture file.
#
# Two self-inflicted bugs this version avoids:
#  * pkill -f "r36-osk" also matched `foot --title=r36-osk-target` and killed the
#    test target.  The title is now free of that substring and pkill uses -x.
#  * dash cannot do arithmetic on "0.15" ($((S > 1 ...)) -> "Illegal number" and
#    the whole remote shell died mid-experiment).  Rounds are explicit now.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 260 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
content() { cat -v /tmp/osk-typed.txt 2>/dev/null | tr -d '\n'; }

echo "  host=$(hostname)  weston=$(systemctl is-active weston)"
systemctl is-active weston >/dev/null || systemctl restart weston
sleep 3
pkill -x foot 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -x r36-osk 2>/dev/null
pkill -f "bin/r36-osk" 2>/dev/null
sleep 1
: > /tmp/osk-typed.txt
(setsid timeout 900 foot --title=osktarget -- /bin/sh -c \
  'stty -icanon min 1 time 0 2>/dev/null; while :; do cat >> /tmp/osk-typed.txt; sleep 1; done' \
  >/tmp/foot-osk.log 2>&1 &)
sleep 3
echo "  foot=$(pgrep -cx foot) (target window up, title=osktarget so pkill cannot hit it)"

round() {   # round <settle> <wait-after>
  S=$1; W=$2
  echo
  echo "=== round settle=$S ==="
  pkill -f "bin/r36-osk" 2>/dev/null; pkill -x wofi 2>/dev/null; sleep 1
  (setsid timeout 120 /usr/local/bin/r36-osk --settle $S --pick-timeout 60 >/tmp/osk.log 2>&1 &)
  sleep 4
  before=$(content)
  echo "  grid up: wofi=$(pgrep -cx wofi)  foot=$(pgrep -cx foot)  file before=[$before]"
  /usr/local/bin/r36-osk --keys DOWN,DOWN,ENTER >/dev/null 2>&1
  sleep $W
  after=$(content)
  echo "  osk picked : $(grep -E '^  \[' /tmp/osk.log | tr -d '\n')"
  echo "  file after : [$after]"
  if [ "$after" != "$before" ]; then
    echo "  => VERDICT: the character reached foot (focus returns; settle=$S is enough)"
    return 0
  fi
  echo "  => nothing arrived (focus did not come back to foot by the time we typed)"
  return 1
}

round 0.15 3 && exit 0
round 0.6 4 && exit 0
round 1.5 6 && exit 0
echo
echo "=== all three failed: weston is NOT restoring focus to the previous surface ==="
echo "  the per-keystroke wofi round trip cannot work as designed; the fix has to be"
echo "  either an explicit refocus (absolute-pointer click on the target window) or a"
echo "  different front-end that never takes focus away."
exit 1
EOS
echo "=== focus-restore experiment finished (rc=$?) ==="
