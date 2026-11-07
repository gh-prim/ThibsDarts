# Voie rapide (avant l'image pi-gen)

Raspberry Pi OS Lite 64-bit flashé avec Raspberry Pi Imager (hôte `dartos-hub`, utilisateur `thibs`, SSH par clé).

Préparation du Pi (une fois) :

- paquets : `mosquitto mosquitto-clients libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev libdrm-dev libgbm-dev libsystemd-dev libinput-dev libudev-dev libxkbcommon-dev fontconfig libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-plugins-base`
- `sudo mkdir -p /data/thibsdarts /opt/thibsdarts/hub && sudo chown -R thibs:thibs /data/thibsdarts /opt/thibsdarts`
- `sudo usermod -aG video,render,input thibs`
- copier `50-thibsdarts-network.rules` dans `/etc/polkit-1/rules.d/` (le hub pilote le Wi-Fi via nmcli)
- copier `thibsdarts-mosquitto.conf` dans `/etc/mosquitto/conf.d/` puis `sudo systemctl enable --now mosquitto` (broker MQTT pour dartos-cam)
- copier `thibsdarts-hub.service` dans `/etc/systemd/system/` puis `sudo systemctl enable thibsdarts-hub`

Déployer une nouvelle version du hub depuis le Mac : `os/quick/deploy-hub.sh`
