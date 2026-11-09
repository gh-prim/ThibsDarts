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
| `thibsdarts/cam/status` | cam → hub | retenu, publié par le service caméras : `{"state": "online"/"offline", "mode": "sim"/"vision", "version": "...", "preview": "http://ip:8081", "cams": {"<id>": "Haut" ou null, ...}}`, "offline" aussi en dernière volonté MQTT |
| `thibsdarts/hub/state` | hub → cam | retenu : `{"playing": bool, "ts": ms}` |

Le hub ignore une fléchette dont l'`id` a déjà été reçu.

## Simulateur

Python 3 + `python3-paho-mqtt` (paquets apt). Hôte du broker : `MQTT_HOST` (défaut 192.168.1.239).

- `simulator/sim.py` : vise le T20 avec une dispersion gaussienne (`SIM_SPREAD`, 20 mm par défaut),
  3 fléchettes espacées de 2 à 4 s, retrait 5 s après. Ne lance que si le hub annonce une partie en cours.
- `simulator/throw.py T20` : une fléchette à la main (`takeout` pour le retrait).

## Caméras

`vision/server.py` (service `thibsdarts-vision`) possède les caméras. Elles sont cherchées dans
`/dev/v4l/by-path` toutes les 3 s : on peut les débrancher et les rebrancher sur n'importe quel port.

Les 3 caméras (Realtek 0bda:5844) sont identiques jusqu'au numéro de série et aux descripteurs USB :
rien dans le matériel ne les distingue. `vision/identity.py` les reconnaît donc à leur vue : quand le
propriétaire nomme une caméra ("Haut"), une image de référence est gardée dans `/data/thibsdarts/cameras/`
(liste dans `cameras.json`). Chaque caméra branchée est comparée aux références (points ORB, homographie
RANSAC, meilleure répartition des noms) et prend le nom qui lui correspond. Une caméra qui ne ressemble à
aucune référence est "non reconnue". Ça ne marche bien qu'une fois les caméras fixées autour de la cible.

Aperçu HTTP sur le port 8081 : `/status` (liste des caméras avec `id`, `label`, `moving`...),
`/cam/<id>.mjpg` (flux 640x360, ~12 i/s), `/cam/<id>.jpg`, `POST /cam/<id>/name {"name": "Haut"}`.
L'`id` désigne la prise (ex. `0-2`), pas la caméra. `thibsdarts/cam/motion` signale quand une caméra
voit bouger quelque chose (main passée devant pour la repérer). Le hub relaie tout ça aux iPhone sur
`/api/cams` (propriétaire).

Déployer et lancer les services sur le Pi 5 : `os/quick/deploy-cam.sh`.
