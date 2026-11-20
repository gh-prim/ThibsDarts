#!/usr/bin/env bash
# Prépare le Pi 5 pour le vidéoprojecteur (une fois) : cage + Chromium, page plein écran sur le HDMI.
# Usage : os/quick/install-projector.sh [hote]   (defaut : thibs@dartos-cam.local)
# Le code (cam/projector) arrive avec os/quick/deploy-cam.sh.
set -euo pipefail
HOST="${1:-thibs@dartos-cam.local}"
cd "$(dirname "$0")"
ssh "$HOST" 'sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cage chromium && sudo usermod -aG video,render,input thibs'
rsync -az thibsdarts-kiosk.service "$HOST":/tmp/
ssh "$HOST" 'sudo mv /tmp/thibsdarts-kiosk.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable thibsdarts-kiosk && sudo systemctl restart thibsdarts-kiosk && systemctl is-active thibsdarts-kiosk'
