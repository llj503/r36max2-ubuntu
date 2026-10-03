#!/bin/bash
# k72-wayland-install.sh - install weston and whatever companion packages this
# Ubuntu actually ships (a single unknown package name makes apt abort the whole
# transaction, so filter the list against apt-cache first).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}

timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== weston-related packages in this release ==="
apt-cache search --names-only "weston|wayland-protocols|libwayland-dev|foot|wofi|grim" 2>/dev/null |
  sort | sed 's/^/  /' | head -30
EOS

# what exists here: probe the candidate list, install only the ones apt knows
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
WANT="weston weston-examples weston-utils wayland-protocols libwayland-dev \
      libwayland-bin grim wf-recorder foot wofi libdumbcap-dev cmake pkg-config"
HAVE=""
for p in $WANT; do
  c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  case "$c" in ""|none) ;; *) HAVE="$HAVE $p";; esac
done
echo "  will install :$HAVE"
echo "  skipped      : $(for p in $WANT; do case " $HAVE " in *" $p "*) ;; *) printf " %s" "$p";; esac; done)"
EOS

timeout 500 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
WANT="weston weston-examples weston-utils wayland-protocols libwayland-dev \
      libwayland-bin grim wf-recorder foot wofi cmake pkg-config"
HAVE=""
for p in $WANT; do
  c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  case "$c" in ""|none) ;; *) HAVE="$HAVE $p";; esac
done
DEBIAN_FRONTEND=noninteractive apt-get install -y -q $HAVE 2>&1 | tail -12
echo "  apt exit=$?"
EOS

timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo
echo "=== what landed ==="
echo "  weston      : $(weston --version 2>&1 | head -1)"
echo "  backends    : $(find /usr/lib -name '*backend*so*' 2>/dev/null | xargs -r -n1 basename | sort -u | tr '\n' ' ')"
echo "  weston bins : $(ls /usr/bin | grep -i '^weston' | tr '\n' ' ')"
echo "  clients     : $(ls /usr/bin | grep -iE 'simple-egl|simple-dmabuf|flower|cliptest|terminal|foot' | tr '\n' ' ')"
echo "  screenshot  : weston-screenshooter=$(command -v weston-screenshooter || echo no) grim=$(command -v grim || echo no) wf-recorder=$(command -v wf-recorder || echo no)"
echo "  protocols   : $(ls /usr/share/wayland-protocols 2>/dev/null | tr '\n' ' ')"
echo "  units       : $(systemctl list-unit-files 2>/dev/null | grep -i weston | tr '\n' ' ')"
echo "  mem now     : $(free -m | awk '/^Mem/{print $7" MiB available"}')"
echo "  disk now    : $(df -h / | awk 'NR==2{print $4" free"}')"
EOS
echo "=== install done ==="
