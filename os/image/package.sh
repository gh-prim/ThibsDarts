#!/usr/bin/env bash
# Fabrique le paquet de mise a jour d'un Pi : thibsdarts-<role>-<tag>.tar.gz
# Contenu : VERSION + hub/ (bundle flutter-pi) ou cam/ (Python).
# Usage : os/image/package.sh hub|cam <tag> <dossier de sortie>
# Pour hub, compiler avant : flutterpi_tool build --arch=arm64 --cpu=pi4 --release (dans hub/)
set -euo pipefail
ROLE="$1" TAG="$2" OUT="$(mkdir -p "$3" && cd "$3" && pwd)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "$TAG" >"$STAGE/VERSION"
case "$ROLE" in
hub)
  BUNDLE="$ROOT/hub/build/flutter-pi/pi4-64"
  [ -x "$BUNDLE/flutter-pi" ] || { echo "bundle flutter-pi absent : $BUNDLE" >&2; exit 1; }
  cp -a "$BUNDLE" "$STAGE/hub"
  ;;
cam)
  cp -a "$ROOT/cam" "$STAGE/cam"
  find "$STAGE/cam" \( -name __pycache__ -o -name captures \) -prune -exec rm -rf {} +
  ;;
*) echo "role inconnu : $ROLE" >&2; exit 1 ;;
esac

tar -C "$STAGE" --owner=0 --group=0 -czf "$OUT/thibsdarts-$ROLE-$TAG.tar.gz" .
echo "$OUT/thibsdarts-$ROLE-$TAG.tar.gz"
