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

case "${TD_ROLE}" in
# Hub : l'ecran passe directement de la tete de Thibs a l'app, sans invite de connexion.
hub) UNITS="thibsdarts-hub mosquitto"; MASK="getty@tty1" ;;
cam) UNITS="thibsdarts-cam thibsdarts-vision" ;;
esac

on_chroot <<- CHROOT
	systemctl disable rpi-resize || true
	systemctl enable thibsdarts-firstboot thibsdarts-update.timer ${UNITS}
	if [ -n "${MASK:-}" ]; then systemctl mask ${MASK}; fi
	/usr/local/sbin/thibsdarts-splash-setup
CHROOT
