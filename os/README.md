# os

Images Dart OS construites avec pi-gen (Raspberry Pi OS Lite 64-bit trixie) :

- `dartos-hub` (Pi 4) : flutter-pi + `hub`, broker MQTT
- `dartos-cam` (Pi 5) : vision Python + OpenCV (`cam`)

`quick/` : la voie rapide d'avant l'image (Pi OS Lite installé à la main, déploiement par rsync).

## Carte SD

| Partition | Contenu |
|---|---|
| `bootfs` | démarrage |
| `rootfs` | système, en lecture seule (overlayroot), jamais modifié |
| `thibsdata` → `/data` | créée au premier démarrage dans la place libre |

Dans `/data` :

- `system/releases/<tag>/` : versions de ThibsDarts installées, `system/current` = celle qui tourne
  (`/opt/thibsdarts` pointe dessus), `system/previous` = la précédente
- `thibsdarts/` : profils, historique, caméras nommées, réseaux Wi-Fi (`nm-connections/`)

## Mises à jour

Publier une release GitHub (pas une pre-release) lance `.github/workflows/release.yml` :

1. compile le hub (flutterpi_tool), emballe `cam/`, attache `thibsdarts-hub-<tag>.tar.gz`,
   `thibsdarts-cam-<tag>.tar.gz` et `SHA256SUMS` à la release
2. construit les deux images et attache `dartos-hub-<tag>.img.xz` et `dartos-cam-<tag>.img.xz`,
   seulement pour une version en .0 (v0.3.0, v1.0.0) ou si `os/image/` a changé depuis la release
   d'avant (lancement manuel : case "image" pour forcer). L'image ne sert qu'à installer un Pi neuf :
   les paquets mettent aussi le système à jour (voir plus bas), plus besoin de reflasher.

Sur chaque Pi, `thibsdarts-update.timer` lance `thibsdarts-update` 2 min après le démarrage puis
toutes les 15 min. Il attend la fin de la partie en cours, télécharge le paquet, vérifie le SHA256,
bascule `current`, redémarre l'app. Si elle ne tient pas 30 s, retour à la version d'avant et le tag
est noté dans `system/bad-releases` (plus retenté, sauf `sudo thibsdarts-update --force`).

Une pre-release sert à tester sans que les Pi la prennent.

### Mise à jour du système (sans reflasher)

Chaque paquet contient `system/` : les fichiers de `os/image/common` + `os/image/roles/<role>`,
les paquets Debian (`00-packages` + `os/image/system/<role>/packages.txt`), les services
(`units.txt`), le bloc `thibsdarts` de `config.txt` (`config.txt`), les migrations
(`os/image/system/migrations`) et `system/apply`. `system/ID` est l'empreinte de tout ça.

Après avoir basculé sur la nouvelle version, `thibsdarts-update` lance `system/apply`. Si l'ID est
déjà installé (`/etc/thibsdarts/system-id`), rien. Sinon il remonte en écriture la vraie couche du
système (`/media/root-ro` sous overlayroot) et `/boot/firmware`, sauve ce qu'il remplace dans
`/data/system/system-backup`, copie les fichiers, installe les paquets manquants (listes apt sur
`/data`), active les services, écrit le bloc de `config.txt`, passe les migrations, reconstruit
l'initramfs si l'écran de démarrage a changé, puis redémarre le Pi. L'écran affiche "Mise à jour du
système" pendant ce temps. Au démarrage suivant, `thibsdarts-update` vérifie que les services
tiennent 30 s ; sinon il remet le système et la version d'avant, note l'ID dans
`/data/system/bad-system` et redémarre. Rien n'a changé (seulement des scripts identiques) : pas de
redémarrage.

Pour changer le système : modifier `os/image/...`, merger, publier une release. Exemples : une
ligne dans `os/image/system/hub/config.txt` (écran), un paquet dans `packages.txt`, un service dans
`roles/hub/etc/systemd/system` + `units.txt`, ou un script `os/image/system/migrations/0001-xxx.sh`
pour le reste (`cmdline.txt`, suppression de fichiers). Ancien `thibsdarts-update` (images
<= v0.2.22) : l'app (hub et cam) lance elle-même `system/apply` au premier démarrage de la nouvelle
version, qui installe au passage le nouveau `thibsdarts-update`.

Réglages > Système affiche la version des deux Pi et "Chercher une mise à jour" lance tout de suite
`thibsdarts-update --force` sur le Pi 4 et, par MQTT, sur le Pi 5.

## Reset usine

`sudo thibsdarts-factory-reset` efface `/data/thibsdarts` et redémarre. Les versions dans
`/data/system` restent : on repart sur la dernière mise à jour, pas sur la version de l'image.

## Écran de démarrage

Pas de texte console : Plymouth montre la tête de Thibs (`splash/boot.gif`), une barre et des
phrases qui défilent. Source dans `splash/` : modifier `quotes.txt` ou `boot.gif`, puis
`python3 os/splash/make-theme.py` (Pillow) régénère `image/common/usr/share/plymouth/themes/thibsdarts/`.
L'image l'installe toute seule (`thibsdarts-splash-setup`). Sur un Pi déjà installé :
`os/quick/install-splash.sh thibs@dartos-hub.local` (le Pi redémarre).

## Construire une image

Sur GitHub : automatique à chaque release. Réglages du repo nécessaires :

- variable `SSH_PUBKEY` : clé publique du Mac (connexion `ssh thibs@dartos-hub.local`)
- secret `PI_PASSWORD` (optionnel) : mot de passe de `thibs`. Sans lui, connexion par clé seulement.

Sur le Mac, sans attendre GitHub (Docker Desktop lancé) : `os/image/local.sh hub` ou
`os/image/local.sh cam`. Le script compile, construit l'image dans Docker (30 à 50 min), puis
propose de la flasher (`os/image/flash-sd.sh`, demande le disque et une confirmation). La clé
`~/.ssh/id_ed25519.pub` du Mac est mise dans l'image.

Pour modifier le système à la main (sans release) : `sudo raspi-config nonint do_overlayfs 1`,
redémarrer, modifier, puis `do_overlayfs 0`, remettre `overlayroot=tmpfs:recurse=0` dans
`/boot/firmware/cmdline.txt` (sinon `/data` passe aussi en RAM) et redémarrer.
