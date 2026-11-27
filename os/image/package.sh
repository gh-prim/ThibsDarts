#!/usr/bin/env bash
# Fabrique le paquet de mise a jour d'un Pi : thibsdarts-<role>-<tag>.tar.gz
# Contenu : VERSION + hub/ (bundle flutter-pi) ou cam/ (Python) + system/ (le systeme du Pi :
# fichiers, paquets, services, config.txt, migrations ; applique par system/apply, voir os/README.md).
# Usage : os/image/package.sh hub|cam <tag> <dossier de sortie>
# Pour hub, compiler avant : flutterpi_tool build --arch=arm64 --cpu=pi4 --release (dans hub/)
set -euo pipefail
ROLE="$1" TAG="$2" OUT="$(mkdir -p "$3" && cd "$3" && pwd)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="$(mktemp -d)"
chmod 755 "$STAGE" # mktemp donne 700 : la racine de l'archive doit rester lisible par thibs
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

# Systeme : meme contenu que l'image (os/image/common + roles/<role>), plus de quoi l'appliquer.
SRC="$ROOT/os/image"
S="$STAGE/system"
mkdir -p "$S/root" "$S/migrations"
cp -a "$SRC/common/." "$SRC/roles/$ROLE/." "$S/root/"
{ cat "$SRC/stage-thibsdarts/00-thibsdarts/00-packages"; cat "$SRC/system/$ROLE/packages.txt"; } >"$S/packages.txt"
cp "$SRC/system/$ROLE/units.txt" "$SRC/system/$ROLE/config.txt" "$S/"
find "$SRC/system/migrations" -maxdepth 1 -name '*.sh' -exec cp {} "$S/migrations/" \;
cp "$SRC/system/apply" "$S/apply"
chmod 755 "$S/apply"
# Empreinte du systeme : les Pi n'appliquent que si elle change.
(cd "$S" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16) >"$S/ID"

tar -C "$STAGE" --owner=0 --group=0 -czf "$OUT/thibsdarts-$ROLE-$TAG.tar.gz" .
echo "$OUT/thibsdarts-$ROLE-$TAG.tar.gz"
