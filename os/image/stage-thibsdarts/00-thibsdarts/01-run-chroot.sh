#!/bin/bash -e
# Paquets propres a chaque Pi (TD_ROLE vient de la config : hub ou cam).
export DEBIAN_FRONTEND=noninteractive
case "${TD_ROLE}" in
hub)
	apt-get install -y --no-install-recommends mosquitto \
		libgl1-mesa-dri libegl1 libgles2 libgbm1 libdrm2 libinput10 libxkbcommon0 libsystemd0 libudev1 \
		fontconfig libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-plugins-base
	;;
cam)
	apt-get install -y --no-install-recommends python3-opencv python3-numpy python3-paho-mqtt v4l-utils
	;;
*)
	echo "TD_ROLE inconnu : ${TD_ROLE}" >&2
	exit 1
	;;
esac
