#!/usr/bin/env bash
# Ecrit une image Dart OS (.img.xz) sur une carte SD, depuis le Mac.
# Usage : os/image/flash-sd.sh <image.img.xz>
set -euo pipefail
IMG="$1"
[ -f "$IMG" ] || { echo "image introuvable : $IMG" >&2; exit 1; }

echo "Cartes et cles externes branchees :"
diskutil list external physical
echo
read -r -p "Disque de la carte SD (ex. disk4) : " DISK
DISK="${DISK#/dev/}"
case "$DISK" in disk[0-9]*) ;; *) echo "nom invalide : $DISK" >&2; exit 1 ;; esac
diskutil info "/dev/$DISK" | grep -q "Device Location: *External" ||
  { echo "/dev/$DISK n'est pas un disque externe, on arrete." >&2; exit 1; }
diskutil info "/dev/$DISK" | grep -E "Media Name|Disk Size"
read -r -p "Tout /dev/$DISK sera EFFACE. Taper OUI pour continuer : " OK
[ "$OK" = OUI ] || { echo "annule"; exit 1; }

diskutil unmountDisk "/dev/$DISK"
echo "Ecriture en cours (quelques minutes)..."
xz -dc "$IMG" | sudo dd of="/dev/r$DISK" bs=4m
sync
diskutil eject "/dev/$DISK"
echo "Termine : carte ejectee, vous pouvez la mettre dans le Pi."
