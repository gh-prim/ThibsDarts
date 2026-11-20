#!/usr/bin/env bash
# Sauvegarde ou remet les données du Pi 5 (caméras nommées, calibrations, apprentissage, projecteur,
# Wi-Fi) avant et après avoir reflashé sa carte SD.
# Usage : os/quick/cam-data.sh save|restore [hote] [fichier]
#   defaut : thibs@dartos-cam.local, ~/thibsdarts-cam-data.tar.gz
set -euo pipefail
ACTION="${1:?save ou restore}"
HOST="${2:-thibs@dartos-cam.local}"
FILE="${3:-$HOME/thibsdarts-cam-data.tar.gz}"
case "$ACTION" in
save)
  ssh "$HOST" 'sudo tar -czf - -C /data thibsdarts' >"$FILE"
  echo "sauvegardé dans $FILE ($(du -h "$FILE" | cut -f1))"
  ;;
restore)
  [ -s "$FILE" ] || { echo "pas de sauvegarde $FILE" >&2; exit 1; }
  ssh "$HOST" 'sudo systemctl stop thibsdarts-vision thibsdarts-cam || true'
  ssh "$HOST" 'sudo tar -xzf - -C /data && sudo chown -R thibs:thibs /data/thibsdarts' <"$FILE"
  ssh "$HOST" 'sudo systemctl start thibsdarts-vision thibsdarts-cam && systemctl is-active thibsdarts-vision'
  ;;
*)
  echo "save ou restore" >&2; exit 1 ;;
esac
