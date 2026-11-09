#!/usr/bin/env python3
"""Appairage Wi-Fi du Pi 5 caméra avec le hub, sans Ethernet ni écran.

Tant que le Pi 5 n'est sur aucun réseau, il ouvre son propre point d'accès
"ThibsDarts-cam-XXXX" (clé PAIR_KEY). Le hub le voit dans ses scans, s'y connecte
quelques secondes et lui envoie le Wi-Fi de la maison (POST /pair). Le Pi 5 s'y
connecte, retrouve le hub par dartos-hub.local et le point d'accès disparaît.

Si le Wi-Fi de la maison tombe ou change, le point d'accès revient et le hub
recommence. Tourne en root (nmcli). Stdlib Python seulement.
"""
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

IFACE = os.environ.get("PAIR_IFACE", "wlan0")
PORT = int(os.environ.get("PAIR_PORT", "8090"))
# Même valeur côté hub (hub/lib/cam/cam_pairing.dart).
PAIR_KEY = os.environ.get("PAIR_KEY", "thibsdarts-pair")
AP_CON = "thibsdarts-cam-ap"
HOME_CON = "thibsdarts-home"
# Au démarrage, NetworkManager a le temps de rejoindre un réseau connu avant le point d'accès.
OFFLINE_GRACE = 45
# Point d'accès ouvert depuis longtemps : on retente le Wi-Fi enregistré (box redémarrée...).
AP_RETRY_HOME = 180

lock = threading.Lock()
state = {"ap": False, "ap_since": 0.0, "offline_since": None, "busy": False}


def log(*a):
    print("pair:", *a, flush=True)


def nmcli(*args, timeout=40):
    try:
        r = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return 1, "", "timeout"


def ap_ssid():
    try:
        with open(f"/sys/class/net/{IFACE}/address") as f:
            mac = f.read().strip().replace(":", "")
    except OSError:
        mac = "0000"
    return "ThibsDarts-cam-" + mac[-4:].upper()


def online():
    """Vrai si le Pi 5 est sur un réseau (Wi-Fi client ou câble), pas sur son propre point d'accès."""
    _, out, _ = nmcli("-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active")
    for line in out.splitlines():
        parts = line.rsplit(":", 2)
        if len(parts) != 3 or not parts[2]:
            continue
        name, typ, _dev = parts
        if typ.endswith("ethernet"):
            _, carrier, _ = nmcli("-g", "GENERAL.STATE", "dev", "show", _dev)
            if carrier.startswith("100"):
                return True
        if typ.endswith("wireless") and name.replace("\\:", ":") != AP_CON:
            return True
    return False


def saved_wifi():
    """Profils Wi-Fi enregistrés (hors point d'accès)."""
    _, out, _ = nmcli("-t", "-f", "NAME,TYPE", "con", "show")
    names = []
    for line in out.splitlines():
        name, _, typ = line.rpartition(":")
        name = name.replace("\\:", ":")
        if typ.endswith("wireless") and name != AP_CON:
            names.append(name)
    return names


def start_ap():
    ssid = ap_ssid()
    nmcli("con", "delete", AP_CON)
    nmcli("con", "add", "type", "wifi", "ifname", IFACE, "con-name", AP_CON, "autoconnect", "no",
          "ssid", ssid, "802-11-wireless.mode", "ap", "802-11-wireless.band", "bg",
          "ipv4.method", "shared", "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", PAIR_KEY)
    code, _, err = nmcli("con", "up", AP_CON)
    if code == 0:
        log("point d'accès ouvert :", ssid)
        state["ap"], state["ap_since"] = True, time.time()
    else:
        log("point d'accès impossible :", err)


def stop_ap():
    nmcli("con", "down", AP_CON)
    state["ap"] = False


def try_saved():
    """Coupe le point d'accès et essaie les Wi-Fi enregistrés. Vrai si l'un d'eux marche."""
    stop_ap()
    for name in saved_wifi():
        nmcli("dev", "wifi", "rescan", "ifname", IFACE)
        time.sleep(3)
        if nmcli("con", "up", name, timeout=30)[0] == 0:
            log("reconnecté à", name)
            return True
    return False


def join_home(ssid, password):
    """Enregistre le Wi-Fi de la maison envoyé par le hub et s'y connecte."""
    with lock:
        state["busy"] = True
    try:
        stop_ap()
        nmcli("con", "delete", HOME_CON)
        args = ["con", "add", "type", "wifi", "ifname", IFACE, "con-name", HOME_CON,
                "autoconnect", "yes", "ssid", ssid]
        if password:
            args += ["wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password]
        nmcli(*args)
        # Après le mode point d'accès, la puce n'a rien scanné : on rescanne avant chaque essai.
        for _ in range(4):
            nmcli("dev", "wifi", "rescan", "ifname", IFACE)
            time.sleep(3)
            code, _, err = nmcli("con", "up", HOME_CON, timeout=45)
            if code == 0:
                log("connecté au Wi-Fi de la maison :", ssid)
                return
            log("échec connexion", ssid, ":", err)
        log("Wi-Fi de la maison injoignable, retour au point d'accès")
        start_ap()
    finally:
        with lock:
            state["busy"] = False


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/hello":
            return self._send(200, {"role": "cam", "ap": state["ap"], "ssid": ap_ssid()})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/pair":
            return self._send(404, {"error": "not found"})
        if self.headers.get("X-Pair-Key") != PAIR_KEY:
            return self._send(403, {"error": "clé"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            ssid, password = str(body["ssid"]), str(body.get("password", ""))
        except (ValueError, KeyError, TypeError):
            return self._send(400, {"error": "ssid manquant"})
        if not ssid:
            return self._send(400, {"error": "ssid vide"})
        with lock:
            if state["busy"]:
                return self._send(409, {"error": "occupé"})
        # On répond d'abord : couper le point d'accès coupe aussi le hub.
        self._send(200, {"ok": True})
        log("Wi-Fi reçu du hub :", ssid)
        threading.Thread(target=join_home, args=(ssid, password), daemon=True).start()

    def log_message(self, *_):
        pass


def watch():
    while True:
        time.sleep(5)
        with lock:
            if state["busy"]:
                continue
        if state["ap"]:
            if time.time() - state["ap_since"] > AP_RETRY_HOME and saved_wifi():
                if not try_saved():
                    start_ap()
            continue
        if online():
            state["offline_since"] = None
            continue
        now = time.time()
        if state["offline_since"] is None:
            state["offline_since"] = now
        elif now - state["offline_since"] > OFFLINE_GRACE:
            state["offline_since"] = None
            start_ap()


if __name__ == "__main__":
    # Point d'accès resté d'un arrêt brutal : on le ferme pour laisser NetworkManager essayer la maison.
    if AP_CON in [l.rpartition(":")[0] for l in nmcli("-t", "-f", "NAME,TYPE", "con", "show", "--active")[1].splitlines()]:
        stop_ap()
    threading.Thread(target=watch, daemon=True).start()
    log("en écoute sur le port", PORT, "| point d'accès si hors ligne :", ap_ssid())
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
