# ThibsDarts / Dart OS

Système de comptage automatique des fléchettes pour Thibault.

| Dossier | Contenu |
|---|---|
| `hub/` | Écran joueur Flutter (Pi 4) |
| `packages/darts_engine/` | Règles des jeux en Dart pur, testées |
| `cam/` | Détection caméras (Pi 5), à venir |
| `os/` | Images Dart OS (pi-gen), à venir |
| `FEATURES.md` | Liste des features |

## Lancer l'écran sur le Mac

```sh
cd hub
flutter run -d macos
```

## Tests du moteur

```sh
cd packages/darts_engine
dart test
```
