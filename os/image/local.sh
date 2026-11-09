#!/usr/bin/env bash
# Construit l'image d'un Pi sur le Mac (sans attendre GitHub) puis propose de la flasher.
# Prerequis : Docker Desktop lance ; pour hub, flutterpi_tool (comme os/quick/deploy-hub.sh).
# Usage : os/image/local.sh hub|cam [tag]
#   tag par defaut : local-AAAAMMJJ. Au premier demarrage avec Internet, le Pi passe
#   sur la derniere release GitHub.
set -euo pipefail
ROLE="$1"
TAG="${2:-local-$(date +%Y%m%d)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/.work/out"
mkdir -p "$OUT"

docker info >/dev/null 2>&1 || { echo "Docker ne tourne pas : lancez Docker Desktop." >&2; exit 1; }
if [ -z "${SSH_PUBKEY:-}" ]; then
  for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do [ -f "$k" ] && SSH_PUBKEY="$(cat "$k")" && break; done
fi
export SSH_PUBKEY

if [ "$ROLE" = hub ]; then
  (cd "$ROOT/hub" && ~/.pub-cache/bin/flutterpi_tool build --arch=arm64 --cpu=pi4 --release)
fi
"$HERE/package.sh" "$ROLE" "$TAG" "$OUT"
WORK="$HERE/.work/$ROLE" "$HERE/build.sh" "$ROLE" "$OUT/thibsdarts-$ROLE-$TAG.tar.gz" "$OUT"

IMG="$OUT/dartos-$ROLE-$TAG.img.xz"
echo "Image prete : $IMG"
read -r -p "Flasher une carte SD maintenant ? (o/n) " GO
if [ "$GO" = o ]; then "$HERE/flash-sd.sh" "$IMG"; fi
