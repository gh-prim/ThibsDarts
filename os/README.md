# os

Construction des images Dart OS avec pi-gen (à venir) :

- `dartos-hub` (Pi 4) : flutter-pi + `hub`, moteur de jeu, SQLite, broker MQTT
- `dartos-cam` (Pi 5) : vision Python + OpenCV (`cam`)

Base commune : Raspberry Pi OS Lite 64-bit, splash Plymouth "Dart OS", boot silencieux,
système en lecture seule (overlayfs) + partition `/data`.
