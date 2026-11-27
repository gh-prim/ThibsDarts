# Migrations système

Scripts lancés une seule fois par Pi, dans l'ordre du nom (`0001-...sh`, `0002-...sh`), à
l'intérieur du vrai système (chroot sur la couche en lecture seule). Ils servent à ce que les
fichiers ne savent pas faire : modifier `cmdline.txt`, supprimer un fichier, `usermod`, etc.

- Variables : `ROLE` (hub ou cam), `BOOT` (`/boot/firmware`).
- Le script doit s'arrêter avec une erreur si quelque chose rate : la mise à jour du système
  est alors annulée et le Pi garde son ancien système.
- `systemctl start/restart` ne marche pas ici (chroot) : le Pi redémarre de toute façon après.
- Une migration déjà passée n'est jamais relancée (liste dans `/etc/thibsdarts/migrations.done`).
