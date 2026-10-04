#!/bin/bash
# fetch-card-artifacts.sh - pull the two things this pipeline cannot build anymore
# off the running card, and prove they are the bytes the card is actually using.
#
#   DEV=192.168.0.141 bash scripts/fetch-card-artifacts.sh
#
# Why they come off the card: the EmulationStation binary was compiled there (1 GB of
# RAM, no cross recipe in this repo), and the theme it draws with is the tree that was
# verified by eye on 2026-10-04 under `r36-es --kmsdrm`.  apply-es.sh and pack-v20.sh
# refuse to build without these files, so "copied by hand once" cannot be how an image
# gets ES again.
#
# Read-only on the card: sha256sum + rsync pull.  Nothing is written, moved or deleted
# there, because this card is the only known-good system that exists.
set -uo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DEV=${DEV:-192.168.0.141}
export SSHPASS=${SSHPASS:-ubuntu}          # documented debug default; see SECURITY.md
DEST=${DEST:-$REPO/artifacts/es}
SSHOPTS="-o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new"
ESBIN=/root/es/emulationstation
THEME=/root/.emulationstation/themes/art-book-next
CFGDIR=/root/.emulationstation
remote() { timeout "${TMO:-300}" sshpass -e ssh $SSHOPTS root@"$DEV" "$@"; }

echo "=== [0] the card answers, and the rootfs has the files we expect ==="
remote 'sh -s' <<'EOS' || { echo "!! cannot reach root@$DEV - is the card booted and on this network?"; exit 1; }
echo "  uname: $(uname -r)"
for f in /root/es/emulationstation; do
  [ -x "$f" ] && echo "  $f: $(stat -c%s "$f") B" || echo "  !! $f missing or not executable"
done
[ -d /root/.emulationstation/themes/art-book-next ] \
  && echo "  theme: $(find /root/.emulationstation/themes/art-book-next -type f | wc -l) files, $(du -sh /root/.emulationstation/themes/art-book-next | cut -f1)" \
  || echo "  !! theme tree missing"
EOS
CARDBSIZE=$(remote "stat -c%s $ESBIN" | tr -dc '0-9')
[ -n "$CARDBSIZE" ] || { echo "!! could not stat $ESBIN on the card"; exit 1; }
echo "  card says the binary is $CARDBSIZE B"

mkdir -p "$DEST/theme"

echo "=== [1] checksums computed ON THE CARD (the reference, not our copy) ==="
remote "sha256sum $ESBIN" | awk '{print $1"  emulationstation"}' > "$DEST/.card-bin.sha256"
[ -s "$DEST/.card-bin.sha256" ] || { echo "!! no sha256 came back for the binary"; exit 1; }
echo "  binary: $(cut -c1-16 < "$DEST/.card-bin.sha256")"
TMO=900 remote "cd $THEME && find . -type f -print0 | sort -z | xargs -0 sha256sum" > "$DEST/.card-theme.sha256"
tn=$(grep -c . "$DEST/.card-theme.sha256")
echo "  theme: $tn files hashed on the card"
[ "$tn" -gt 100 ] || { echo "!! only $tn theme files hashed - the tree on the card is not the one we saw"; exit 1; }

echo "=== [2] pull them (rsync, resumable: this is ~400 MB over 2.4 GHz WiFi) ==="
timeout 1800 rsync -rltD --partial --timeout=120 -e "sshpass -e ssh $SSHOPTS" \
  root@"$DEV":$ESBIN "$DEST/emulationstation" || { echo "!! binary rsync failed"; exit 1; }
timeout 3600 rsync -rltD --partial --timeout=120 -e "sshpass -e ssh $SSHOPTS" \
  root@"$DEV":$THEME/ "$DEST/theme/art-book-next/" || { echo "!! theme rsync failed"; exit 1; }
echo "  got: $(du -sh "$DEST" | cut -f1) in $DEST"

echo "=== [3] verify our copy against the card's own hashes ==="
( cd "$DEST" && sha256sum -c --quiet .card-bin.sha256 ) \
  || { echo "!! the copied binary does not match the card's sha256"; exit 1; }
( cd "$DEST/theme/art-book-next" && sha256sum -c --quiet "$DEST/.card-theme.sha256" ) \
  || { echo "!! the copied theme does not match the card's sha256 (truncated transfer?)"; exit 1; }
echo "  binary + $tn theme files match the card byte for byte"

echo "=== [4] sanity: is this really the aarch64 ES we ran? ==="
file "$DEST/emulationstation" | sed 's/^/  /'
got=$(stat -c%s "$DEST/emulationstation")
[ "$got" = "$CARDBSIZE" ] || { echo "!! size mismatch: card $CARDBSIZE B, copy $got B"; exit 1; }
echo "  size matches the card exactly: $got B"
head -c 20 "$DEST/emulationstation" | od -An -tx1 | sed 's/^/  header:/;s/\r//'
case $(od -An -tx1 -N4 "$DEST/emulationstation" | tr -d ' \n') in
  7f454c46) echo "  ELF magic ok";;
  *) echo "!! not an ELF file - this is a truncated or text copy"; exit 1;;
esac

echo "=== [5] the manifest apply-es.sh checks ==="
# Relative to artifacts/es, in the format `sha256sum -c` writes, so apply-es.sh's
# `( cd $STAGE && sha256sum -c --quiet SHA256SUMS )` verifies the same bytes that
# step [3] just proved came off the card.
( cd "$DEST" && sha256sum emulationstation && \
  find theme/art-book-next -type f -print0 | sort -z | xargs -0 sha256sum ) > "$DEST/SHA256SUMS"
echo "  SHA256SUMS: $(grep -c . "$DEST/SHA256SUMS") entries"
( cd "$DEST" && sha256sum -c --quiet SHA256SUMS ) || { echo "!! SHA256SUMS does not verify in place"; exit 1; }
echo "  SHA256SUMS verifies from inside $DEST (the way apply-es.sh runs it)"

echo "=== [6] what the card has that the repo should maybe not hardcode ==="
for f in es_input.cfg es_settings.cfg es_systems.cfg; do
  remote "cat $CFGDIR/$f" > "$DEST/$f.card" 2>/dev/null
  [ -s "$DEST/$f.card" ] || { echo "  (no $f on the card)"; continue; }
  rp="$REPO/packages/r36-emulationstation/$( [ "$f" = es_input.cfg ] && echo es-input-r36max2.cfg || echo "$f" )"
  if [ -f "$rp" ]; then
    if cmp -s "$DEST/$f.card" "$rp"; then echo "  $f: identical to $rp"
    else echo "  $f: DIFFERS from $rp ($(wc -c < "$DEST/$f.card") B vs $(wc -c < "$rp") B) - diff it before trusting the repo copy"; fi
  else echo "  $f: no repo counterpart (would go in packages/r36-emulationstation/)"; fi
done

echo "=== [7] done; what still needs a human ==="
echo "  - the theme is 288 MB.  v20-tidy.sh measures the rootfs against the 2 GiB root"
echo "    partition; check it says there is room before packing v21."
echo "  - es_settings.cfg on the card sets Language=zh_CN; apply-es.sh writes a file with"
echo "    only ThemeSet.  Decide whether v21 ships the Chinese UI, do not let it drift."
echo "  - this directory is gitignored (artifacts/); the binary is not redistributable"
echo "    in the same way the vendor blobs are not, so keep it out of commits."
echo "=== fetch-card-artifacts done ==="
