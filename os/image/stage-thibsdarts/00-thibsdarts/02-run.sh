#!/bin/bash -e
# Fichiers Dart OS : commun + role, version livree, services.
IMAGE_DIR="${TD_IMAGE_DIR:?}"

cp -rT "${IMAGE_DIR}/common" "${ROOTFS_DIR}"
cp -rT "${IMAGE_DIR}/roles/${TD_ROLE}" "${ROOTFS_DIR}"

install -D -m 644 "${TD_SEED:?}" "${ROOTFS_DIR}/usr/share/thibsdarts/seed.tar.gz"
ln -sfn /data/system/current "${ROOTFS_DIR}/opt/thibsdarts"
touch "${ROOTFS_DIR}/etc/thibsdarts/firstboot"

# La partition /data est creee au premier demarrage dans la place libre :
# on ne laisse pas Raspberry Pi OS agrandir le systeme sur toute la carte.
sed -i 's/ resize//' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
# Cam : le vidéoprojecteur (Acer) ne signale pas sa présence (HPD) : sortie HDMI 0 forcée, en
# 1280x720 car il n'affiche rien dans son 1280x800 natif (le kiosk reprend ce mode).
if [ "${TD_ROLE}" = cam ]; then
	sed -i '1 s/$/ video=HDMI-A-1:1280x720@60D/' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
fi

case "${TD_ROLE}" in
# Hub : l'ecran passe directement de la tete de Thibs a l'app, sans invite de connexion.
hub) UNITS="thibsdarts-hub mosquitto"; MASK="getty@tty1" ;;
# Cam : le vidéoprojecteur prend tty1 (page plein écran sur le HDMI).
cam) UNITS="thibsdarts-cam thibsdarts-vision thibsdarts-pair thibsdarts-kiosk" ;;
esac

on_chroot <<- CHROOT
	systemctl disable rpi-resize || true
	systemctl enable thibsdarts-firstboot thibsdarts-update.timer ${UNITS}
	if [ -n "${MASK:-}" ]; then systemctl mask ${MASK}; fi
	/usr/local/sbin/thibsdarts-splash-setup
CHROOT
