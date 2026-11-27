#!/bin/bash -e
# Paquets propres a chaque Pi (TD_ROLE vient de la config : hub ou cam).
# La liste est dans os/image/system/<role>/packages.txt : les mises a jour la lisent aussi.
PKGS=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${TD_IMAGE_DIR:?}/system/${TD_ROLE:?}/packages.txt" | tr '\n' ' ')
on_chroot <<- CHROOT
	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y --no-install-recommends ${PKGS}
	if [ "${TD_ROLE}" = cam ]; then usermod -aG video,render,input thibs || true; fi
CHROOT
