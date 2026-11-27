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

# Services : meme liste que les mises a jour (os/image/system/<role>/units.txt).
UNITS="" MASK=""
while read -r u; do
	case "$u" in mask\ *) MASK="$MASK ${u#mask }" ;; *) UNITS="$UNITS $u" ;; esac
done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${IMAGE_DIR}/system/${TD_ROLE}/units.txt")

# Bloc thibsdarts de config.txt (meme format que system/apply).
CFG=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "${IMAGE_DIR}/system/${TD_ROLE}/config.txt")
if [ -n "$CFG" ]; then
	printf '\n# >>> thibsdarts (ecrit par les mises a jour ThibsDarts, ne pas modifier)\n[all]\n%s\n# <<< thibsdarts\n' "$CFG" \
		>>"${ROOTFS_DIR}/boot/firmware/config.txt"
fi

# Systeme livre = celui du paquet : pas de mise a jour systeme au premier demarrage.
tar -xzOf "${TD_SEED}" ./system/ID >"${ROOTFS_DIR}/etc/thibsdarts/system-id"
tar -xzOf "${TD_SEED}" ./VERSION >"${ROOTFS_DIR}/etc/thibsdarts/system-version"
ls "${IMAGE_DIR}/system/migrations/"*.sh 2>/dev/null | xargs -rn1 basename >"${ROOTFS_DIR}/etc/thibsdarts/migrations.done"

on_chroot <<- CHROOT
	systemctl disable rpi-resize || true
	systemctl enable thibsdarts-firstboot thibsdarts-update.timer ${UNITS}
	if [ -n "${MASK}" ]; then systemctl mask ${MASK}; fi
	/usr/local/sbin/thibsdarts-splash-setup
CHROOT
