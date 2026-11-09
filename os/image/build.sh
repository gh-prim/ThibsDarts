#!/usr/bin/env bash
# Construit l'image Dart OS d'un Pi avec pi-gen (Raspberry Pi OS Lite 64-bit trixie).
# Sur Linux (runner GitHub ubuntu-24.04-arm) : pi-gen natif avec sudo.
# Sur Mac (ou DOCKER=1) : pi-gen dans Docker (Docker Desktop doit tourner).
#
# Usage : os/image/build.sh hub|cam <paquet thibsdarts-<role>-<tag>.tar.gz> <dossier de sortie>
# Variables : SSH_PUBKEY (cle publique du Mac, recommande), PI_PASSWORD (mot de passe de thibs)
set -euo pipefail
ROLE="$1"
SEED="$(realpath "$2")"
OUT="$(mkdir -p "$3" && realpath "$3")"
HERE="$(cd "$(dirname "$0")" && pwd)"
PIGEN_COMMIT=c0d2c9f2cffc08bc56850b0a3eb23178f4226e8a # branche arm64, 2026-11-06
WORK="${WORK:-$HERE/.work}"

case "$ROLE" in
hub) HOST=dartos-hub ;;
cam) HOST=dartos-cam ;;
*) echo "role inconnu : $ROLE" >&2; exit 1 ;;
esac
if [ -z "${SSH_PUBKEY:-}" ] && [ -z "${PI_PASSWORD:-}" ]; then
  echo "Il faut SSH_PUBKEY ou PI_PASSWORD, sinon personne ne peut se connecter au Pi." >&2
  exit 1
fi
# pi-gen exige un mot de passe ; sans PI_PASSWORD on en tire un au hasard (connexion par cle seulement).
PASS="${PI_PASSWORD:-$(openssl rand -hex 16)}"
TAG="$(tar -xzOf "$SEED" ./VERSION)"

rm -rf "$WORK" && mkdir -p "$WORK"
git clone -q https://github.com/RPi-Distro/pi-gen.git "$WORK/pi-gen"
git -C "$WORK/pi-gen" checkout -q "$PIGEN_COMMIT"
# On s'arrete a la base Lite (stage2) sans exporter son image, puis notre stage.
touch "$WORK/pi-gen/stage2/SKIP_IMAGES"

# Nos fichiers vont dans le dossier pi-gen : en mode Docker, seul ce dossier est copie dans le conteneur.
mkdir -p "$WORK/pi-gen/thibsdarts"
cp -R "$HERE/common" "$HERE/roles" "$HERE/stage-thibsdarts" "$WORK/pi-gen/thibsdarts/"
cp "$SEED" "$WORK/pi-gen/thibsdarts/seed.tar.gz"
if [ "$(uname -s)" = Linux ] && [ "${DOCKER:-0}" != 1 ]; then
  USE_DOCKER=0 PG="$WORK/pi-gen" DEPLOY="$OUT"
else
  USE_DOCKER=1 PG=/pi-gen DEPLOY=/pi-gen/deploy
fi

cat >"$WORK/config" <<CONF
IMG_NAME=$HOST
RELEASE=trixie
TARGET_HOSTNAME=$HOST
FIRST_USER_NAME=thibs
FIRST_USER_PASS='$PASS'
DISABLE_FIRST_BOOT_USER_RENAME=1
PASSWORDLESS_SUDO=1
ENABLE_SSH=1
PUBKEY_SSH_FIRST_USER='${SSH_PUBKEY:-}'
PUBKEY_ONLY_SSH=$([ -n "${SSH_PUBKEY:-}" ] && [ -z "${PI_PASSWORD:-}" ] && echo 1 || echo 0)
ENABLE_CLOUD_INIT=0
LOCALE_DEFAULT=fr_FR.UTF-8
KEYBOARD_KEYMAP=fr
KEYBOARD_LAYOUT=French
TIMEZONE_DEFAULT=Europe/Paris
WPA_COUNTRY=FR
DEPLOY_COMPRESSION=xz
DEPLOY_DIR=$DEPLOY
ARCHIVE_FILENAME=$HOST-$TAG
STAGE_LIST="stage0 stage1 stage2 $PG/thibsdarts/stage-thibsdarts"
export TD_ROLE=$ROLE
export TD_IMAGE_DIR=$PG/thibsdarts
export TD_SEED=$PG/thibsdarts/seed.tar.gz
CONF

cd "$WORK/pi-gen"
if [ $USE_DOCKER = 1 ]; then
  docker rm -v "pigen_$ROLE" >/dev/null 2>&1 || true
  CONTAINER_NAME="pigen_$ROLE" ./build-docker.sh -c "$WORK/config"
  cp deploy/*.img.xz "$OUT/"
else
  sudo ./build.sh -c "$WORK/config"
fi
ls -la "$OUT"
