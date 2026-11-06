# ThibsDarts : liste des features

Système de comptage automatique des scores aux fléchettes pour Thibault.

## Matériel

- **Raspberry Pi 5** à la cible, avec 3 caméras USB OV9732 (100°, 1280x720, 30 fps)
- **Raspberry Pi 4 + écran 7 pouces** côté joueur
- **Appli iOS** : setup, création de partie, stats
- **Apple TV** : scoreboard projeté pour les soirées
- **Appli web** servie par le Pi 4, accessible depuis le MacBook

## Modes de jeu

### Matchs (multijoueur)

| Mode | Principe | Version |
|---|---|---|
| 301 / 501 | Options double out, double in, legs et sets | V1 |
| Around the clock | 1 à 20 dans l'ordre, variantes doubles ou triples | V1 |
| Cricket | Fermer 15 à 20 + bull | V2 |
| Killer | Chacun a un numéro, devient killer via son double, retire des vies aux autres | V2 |
| Shanghai | Une cible par manche, simple + double + triple en une volée = victoire | V2 |
| Halve-it | Cibles imposées, cible ratée = score divisé par 2 | V3 |
| Bob's 27 | Doubles 1 à 20, on gagne ou perd la valeur du double | V3 |

### Entraînement solo (practice)

| Mode | Principe | Version |
|---|---|---|
| Séries libres | X volées sur une cible choisie, % de réussite | V1 |
| Checkout trainer | Finir des scores tirés au hasard | V3 |
| Doubles trainer | Tous les doubles, stats par double | V3 |
| Score 99 | Moyenne sur 33 volées, suivi de progression | V3 |
| Heatmap | Où tombent les fléchettes, groupement | V3 |

## Features produit

### Système et setup

- Image Raspberry Pi OS custom (.img) avec logo ThibsDarts au démarrage (V1)
- Setup Wi-Fi du Pi 5 depuis l'appli iOS via Bluetooth (V1)
- Le Pi 5 transmet ensuite le Wi-Fi au Pi 4 via Bluetooth, les deux Pi dialoguent sur le réseau (V1)

### Détection (Pi 5 + 3 caméras)

- Score automatique de chaque fléchette (V1)
- Calibration guidée de la cible (V1)
- Détection du retrait des fléchettes pour passer au joueur suivant (V1)
- Correction manuelle en cas d'erreur (V1)

### Écran joueur (Pi 4 + 7 pouces)

- Cible virtuelle en live : chaque fléchette apparaît avec une animation ("bam, triple 20") (V1)
- Score en cours, volée, joueur actif (V1)
- Bouton fin de volée / fléchette hors cible (V1)
- Boutons annuler et corriger (V1)
- Suggestion de checkout, ex : 121 = T20 T11 D14 (V2)
- Design de l'interface à faire plus tard (prompts Claude Design)

### Appli iOS

- Setup Wi-Fi Bluetooth (V1)
- Création de partie : mode, joueurs, options (V1)
- Profils joueurs avec avatar (V2)
- Stats : moyenne par 3 fléchettes, % checkout, 180, meilleur leg, progression (V2)
- Historique des parties (V2)

### Apple TV (projecteur)

- Tableau des scores en grand (V2)
- Animations sur 180, checkout, victoire (V2)
- Annonce vocale du score façon arbitre (V2)

### Appli web (servie par le Pi 4)

- Accessible depuis le MacBook sur le réseau local (V3)
- Stats détaillées (V3)

### IA (optionnel)

- Analyse de jeu avec l'API Anthropic, éventuellement via LangGraph / LangChain (V3)

## Roadmap

- **V1 (jouable)** : image OS custom, setup Wi-Fi Bluetooth, détection et calibration, écran 7 pouces avec cible virtuelle live, 301 / 501 multi, Around the clock, séries d'entraînement
- **V2 (soirées)** : Apple TV, Cricket, Killer, Shanghai, profils, historique et stats de base sur iOS
- **V3 (bonus)** : appli web, modes restants, trainers, heatmap, analyse IA
