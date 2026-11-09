#!/usr/bin/env bash
# Déploie cam/ sur le Pi 5 et redémarre les services (simulateur et caméras).
# Usage : os/quick/deploy-cam.sh [hote]   (defaut : thibs@dartos-cam.local)
set -euo pipefail
HOST="${1:-thibs@dartos-cam.local}"
UNITS="thibsdarts-cam thibsdarts-vision"
cd "$(dirname "$0")"
ssh "$HOST" 'sudo mkdir -p /opt/thibsdarts-cam && sudo chown thibs:thibs /opt/thibsdarts-cam'
rsync -az --delete --exclude __pycache__ --exclude captures ../../cam/ "$HOST":/opt/thibsdarts-cam/
rsync -az thibsdarts-cam.service thibsdarts-vision.service "$HOST":/tmp/
ssh "$HOST" "for u in $UNITS; do sudo mv /tmp/\$u.service /etc/systemd/system/; done && sudo systemctl daemon-reload && sudo systemctl enable $UNITS && sudo systemctl restart $UNITS && systemctl is-active $UNITS"
