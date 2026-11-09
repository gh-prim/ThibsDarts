# cam

Détection des fléchettes sur le Pi 5 `dartos-cam` (Python + OpenCV, 3 caméras OV9732).
Publie chaque fléchette sur MQTT vers le broker du hub (`dartos-hub`, port 1883).
En attendant la vision, `simulator/` joue le rôle des caméras.

## Contrat MQTT

QoS 1 partout. Coordonnées en mm, centre de la cible en (0, 0), x vers la droite, y vers le bas.

| Topic | Sens | Contenu |
| --- | --- | --- |
| `thibsdarts/cam/dart` | cam → hub | `{"id": uuid, "ts": ms, "segment": "T20"/"D16"/"S5"/"SB"/"DB"/"MISS", "number": 0-20 ou 25, "multiplier": 0-3, "score": int, "x": mm, "y": mm, "source": "sim"/"vision"/"manual"}` (x, y optionnels) |
| `thibsdarts/cam/takeout` | cam → hub | `{"ts": ms}` : fléchettes retirées, le hub passe au joueur suivant si le tour est fini |
| `thibsdarts/cam/status` | cam → hub | retenu, publié par le service caméras : `{"state": "online"/"offline", "mode": "sim"/"vision", "version": "...", "preview": "http://ip:8081", "cams": {"A": bool, ...}}`, "offline" aussi en dernière volonté MQTT |
| `thibsdarts/hub/state` | hub → cam | retenu : `{"playing": bool, "ts": ms}` |

Le hub ignore une fléchette dont l'`id` a déjà été reçu.

## Simulateur

Python 3 + `python3-paho-mqtt` (paquets apt). Hôte du broker : `MQTT_HOST` (défaut 192.168.1.239).

- `simulator/sim.py` : vise le T20 avec une dispersion gaussienne (`SIM_SPREAD`, 20 mm par défaut),
  3 fléchettes espacées de 2 à 4 s, retrait 5 s après. Ne lance que si le hub annonce une partie en cours.
- `simulator/throw.py T20` : une fléchette à la main (`takeout` pour le retrait).

## Caméras

`vision/server.py` (service `thibsdarts-vision`) possède les 3 caméras, repérées par leur prise USB
(elles ont toutes le même numéro de série) : A = contrôleur 0 port 2, B = contrôleur 0 port 1, C = contrôleur 1 port 1.
Aperçu HTTP sur le port 8081 : `/cam/A.mjpg` (flux 640x360, ~12 i/s), `/cam/A.jpg`, `/status`.
Une caméra ne s'ouvre que si quelqu'un regarde. Le hub relaie flux et état aux iPhone sur `/api/cams` (propriétaire).

Déployer et lancer les services sur le Pi 5 : `os/quick/deploy-cam.sh`.
