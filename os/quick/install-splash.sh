#!/usr/bin/env bash
# Installe l'ecran de demarrage ThibsDarts (Plymouth) sur un Pi deja installe, puis le redemarre.
# Usage : os/quick/install-splash.sh [hote]   (defaut : thibs@dartos-hub.local)
set -euo pipefail
HOST="${1:-thibs@dartos-hub.local}"
cd "$(dirname "$0")/.."
rsync -az --rsync-path="sudo rsync" --delete image/common/usr/share/plymouth/themes/thibsdarts/ "$HOST":/usr/share/plymouth/themes/thibsdarts/
rsync -az --rsync-path="sudo rsync" image/common/usr/local/sbin/thibsdarts-splash-setup "$HOST":/usr/local/sbin/
if [ "$(ssh "$HOST" hostname)" = dartos-hub ]; then
  rsync -az --rsync-path="sudo rsync" quick/thibsdarts-hub.service "$HOST":/etc/systemd/system/
fi
ssh "$HOST" 'set -e
  sudo apt-get install -y plymouth
  if [ "$(hostname)" = dartos-hub ]; then sudo systemctl mask getty@tty1; fi
  sudo systemctl daemon-reload
  sudo /usr/local/sbin/thibsdarts-splash-setup
  sudo systemctl reboot' || true
echo "Le Pi redemarre avec la tete de Thibs."
