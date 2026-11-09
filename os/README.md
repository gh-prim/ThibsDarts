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
2. construit les deux images et attache `dartos-hub-<tag>.img.xz` et `dartos-cam-<tag>.img.xz`

Sur chaque Pi, `thibsdarts-update.timer` lance `thibsdarts-update` 2 min après le démarrage puis
toutes les 15 min. Il attend la fin de la partie en cours, télécharge le paquet, vérifie le SHA256,
bascule `current`, redémarre l'app. Si elle ne tient pas 30 s, retour à la version d'avant et le tag
est noté dans `system/bad-releases` (plus retenté, sauf `sudo thibsdarts-update --force`).

Une pre-release sert à tester sans que les Pi la prennent.

## Reset usine

`sudo thibsdarts-factory-reset` efface `/data/thibsdarts` et redémarre. Les versions dans
`/data/system` restent : on repart sur la dernière mise à jour, pas sur la version de l'image.

## Construire une image

Sur GitHub : automatique à chaque release. Réglages du repo nécessaires :

- variable `SSH_PUBKEY` : clé publique du Mac (connexion `ssh thibs@dartos-hub.local`)
- secret `PI_PASSWORD` (optionnel) : mot de passe de `thibs`. Sans lui, connexion par clé seulement.

Sur le Mac, sans attendre GitHub (Docker Desktop lancé) : `os/image/local.sh hub` ou
`os/image/local.sh cam`. Le script compile, construit l'image dans Docker (30 à 50 min), puis
propose de la flasher (`os/image/flash-sd.sh`, demande le disque et une confirmation). La clé
`~/.ssh/id_ed25519.pub` du Mac est mise dans l'image.

Pour modifier le système une fois l'image flashée : `sudo raspi-config nonint do_overlayfs 1`,
redémarrer, modifier, puis `do_overlayfs 0` et redémarrer.
