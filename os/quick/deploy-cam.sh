#!/usr/bin/env bash
# Déploie cam/ sur le Pi 5 et redémarre le service.
# Usage : os/quick/deploy-cam.sh [hote]   (defaut : thibs@dartos-cam.local)
set -euo pipefail
HOST="${1:-thibs@dartos-cam.local}"
cd "$(dirname "$0")"
ssh "$HOST" 'sudo mkdir -p /opt/thibsdarts-cam && sudo chown thibs:thibs /opt/thibsdarts-cam'
rsync -az --delete --exclude __pycache__ ../../cam/ "$HOST":/opt/thibsdarts-cam/
rsync -az thibsdarts-cam.service "$HOST":/tmp/
ssh "$HOST" 'sudo mv /tmp/thibsdarts-cam.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable thibsdarts-cam && sudo systemctl restart thibsdarts-cam && systemctl is-active thibsdarts-cam'
