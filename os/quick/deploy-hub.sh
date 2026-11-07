#!/usr/bin/env bash
# Compile le hub pour le Pi 4 (flutter-pi) et le déploie sur le Pi.
# Prérequis Mac : flutterpi_tool (depuis github.com/ardera/flutterpi_tool) et Rosetta.
# Usage : os/quick/deploy-hub.sh [hote]   (defaut : thibs@dartos-hub.local)
set -euo pipefail
HOST="${1:-thibs@dartos-hub.local}"
cd "$(dirname "$0")/../../hub"
~/.pub-cache/bin/flutterpi_tool build --arch=arm64 --cpu=pi4 --release
rsync -az --delete build/flutter-pi/pi4-64/ "$HOST":/opt/thibsdarts/hub/
ssh "$HOST" 'sudo systemctl restart thibsdarts-hub && systemctl is-active thibsdarts-hub'
