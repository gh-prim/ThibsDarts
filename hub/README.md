# dartos_hub

Écran joueur Dart OS (Raspberry Pi 4 + écran 7 ou 10 pouces) en Flutter.
L'interface est dessinée en 1024x600 (planches de design) et mise à l'échelle selon la résolution
réelle (`ScreenFit` dans `lib/main.dart`) : 7" = 1024x600 logiques, 10" (1280x800 et plus,
ex. EVICIV 1920x1200) = 1280x800 logiques, plus de place pour la cible et les graphiques.
Tester une autre taille : `SCREEN=1280x800 flutter test`.
Sur le Pi il tourne via `flutter-pi` (sans navigateur, sans bureau). Sur le Mac, en fenêtre 1024x600.

```sh
cd hub
flutter run -d macos
```
