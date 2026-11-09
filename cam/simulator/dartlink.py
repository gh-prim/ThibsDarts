"""Géométrie de la cible et envoi des fléchettes au hub par MQTT (contrat : cam/README.md)."""

import json
import math
import os
import time
import uuid

import paho.mqtt.client as mqtt


def _release_version():
    """Tag de la release installée (fichier VERSION à la racine du paquet), "dev" sinon."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "VERSION")
    try:
        with open(path) as f:
            return f.read().strip() or "dev"
    except OSError:
        return "dev"


VERSION = _release_version()

MQTT_HOST = os.environ.get("MQTT_HOST", "192.168.1.239")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))

DART_TOPIC = "thibsdarts/cam/dart"
TAKEOUT_TOPIC = "thibsdarts/cam/takeout"
STATUS_TOPIC = "thibsdarts/cam/status"
STATE_TOPIC = "thibsdarts/hub/state"

# Ordre des secteurs en partant du haut, sens horaire (comme le hub).
SECTORS = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

# Rayons officiels en mm.
R_BULL, R_OUTER_BULL = 6.35, 15.9
R_TRIPLE_IN, R_TRIPLE_OUT = 99.0, 107.0
R_DOUBLE_IN, R_DOUBLE_OUT = 162.0, 170.0


def dart_at(x, y):
    """(number, multiplier) touché en (x, y) mm, centre de la cible, x vers la droite, y vers le bas."""
    r = math.hypot(x, y)
    if r <= R_BULL:
        return 25, 2
    if r <= R_OUTER_BULL:
        return 25, 1
    if r > R_DOUBLE_OUT:
        return 0, 0
    a = math.degrees(math.atan2(x, -y)) % 360
    number = SECTORS[int((a + 9) // 18) % 20]
    if R_TRIPLE_IN <= r <= R_TRIPLE_OUT:
        return number, 3
    if r >= R_DOUBLE_IN:
        return number, 2
    return number, 1


def target_point(number, multiplier):
    """Centre du segment visé, en mm."""
    if number == 25:
        return 0.0, 0.0
    r = {3: 103.0, 2: 166.0}.get(multiplier, 135.0)
    a = math.radians(SECTORS.index(number) * 18)
    return r * math.sin(a), -r * math.cos(a)


def segment_name(number, multiplier):
    if number == 0 or multiplier == 0:
        return "MISS"
    if number == 25:
        return "DB" if multiplier == 2 else "SB"
    return "SDT"[multiplier - 1] + str(number)


def parse_segment(text):
    """T20, D16, S5, 5, SB/25, DB/BULL, MISS -> (number, multiplier)."""
    t = text.strip().upper()
    if t in ("MISS", "0"):
        return 0, 0
    if t in ("SB", "25"):
        return 25, 1
    if t in ("DB", "BULL", "50"):
        return 25, 2
    mult = {"S": 1, "D": 2, "T": 3}.get(t[0])
    n = int(t[1:] if mult else t)
    if not 1 <= n <= 20:
        raise ValueError(f"segment inconnu : {text}")
    return n, mult or 1


def dart_message(number, multiplier, x=None, y=None, source="sim"):
    msg = {
        "id": str(uuid.uuid4()),
        "ts": int(time.time() * 1000),
        "segment": segment_name(number, multiplier),
        "number": number,
        "multiplier": multiplier,
        "score": number * multiplier,
        "source": source,
    }
    if x is not None and y is not None:
        msg["x"], msg["y"] = round(x, 1), round(y, 1)
    return json.dumps(msg)


def new_client(name):
    return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"{name}-{uuid.uuid4().hex[:6]}")
