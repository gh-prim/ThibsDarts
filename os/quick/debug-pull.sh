#!/usr/bin/env bash
# Mode Debug : rapatrie sur le Mac les captures du Pi 5 (une par décision de la détection).
# Usage : os/quick/debug-pull.sh [N] [hote]   N = nombre de captures les plus récentes (defaut 40)
# Les captures arrivent dans captures/debug/<AAAAMMJJ-HHMMSS-mmm>-<type>/ (avant, après, diff, info.json).
set -euo pipefail
N="${1:-40}"
HOST="${2:-thibs@192.168.1.160}"
DEST="$(dirname "$0")/../../captures/debug"
mkdir -p "$DEST"
LIST=$(ssh "$HOST" "ls /data/thibsdarts/debug | tail -n $N")
[ -z "$LIST" ] && { echo "aucune capture"; exit 0; }
# Une seule connexion : tar des dossiers voulus.
ssh "$HOST" "cd /data/thibsdarts/debug && tar cf - $(echo $LIST)" | tar xf - -C "$DEST"
for d in $LIST; do printf '%s  %s\n' "$d" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['text'])" "$DEST/$d/info.json" 2>/dev/null)"; done
