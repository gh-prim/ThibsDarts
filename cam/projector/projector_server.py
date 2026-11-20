"""Vidéoprojecteur du Pi 5 : sert la page projetée (port 8082) et la relie au MQTT.
Tourne dans le service caméras (vision/server.py appelle start()), ou seul : python3 projector_server.py.

La page projector.html tourne en plein écran sur la sortie HDMI (Chromium sous cage, service
thibsdarts-kiosk). Elle reçoit ici, en flux SSE (/events), les fléchettes, retraits et état du hub.
La calibration (où tombe la cible dans l'image du projecteur) se règle depuis /calib et reste dans
/data/thibsdarts/projector.json.

Pendant une animation, la page prévient (POST /light) : on publie thibsdarts/projector/light pour que
la détection mette les caméras en pause. Entre deux animations l'image projetée ne change pas.
"""

import json
import os
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "simulator"))
from dartlink import (  # noqa: E402
    DART_TOPIC, MQTT_HOST, MQTT_PORT, STATE_TOPIC, TAKEOUT_TOPIC, TURN_TOPIC, new_client,
)

PORT = int(os.environ.get("PROJECTOR_HTTP_PORT", "8082"))
DATA_DIR = os.environ.get("DARTOS_DATA", "/data/thibsdarts")
CALIB_FILE = os.path.join(DATA_DIR, "projector.json")
LIGHT_TOPIC = "thibsdarts/projector/light"
HUB_PROJECTOR_TOPIC = "thibsdarts/hub/projector"
HERE = os.path.dirname(os.path.abspath(__file__))
SEGMENTS = {"T20": (20, 3), "D16": (16, 2), "S5": (5, 1), "DB": (25, 2), "SB": (25, 1), "MISS": (0, 0)}
# Une animation ne met jamais les caméras en pause plus longtemps que ça.
MAX_BUSY_MS = 8000
FILES = {
    "/": ("projector.html", "text/html; charset=utf-8"),
    "/calib": ("calib.html", "text/html; charset=utf-8"),
    "/fx.js": ("fx.js", "text/javascript; charset=utf-8"),
}


class Hub:
    """Clients SSE branchés et dernier état connu (renvoyé à chaque nouvelle page)."""

    def __init__(self):
        self.lock = threading.Lock()
        self.clients = []
        self.last = {}
        self.client = None
        self.screen = [1280, 720]  # taille de la page projetée, envoyée par elle au chargement

    def send(self, kind, data, keep=False):
        msg = f"event: {kind}\ndata: {json.dumps(data)}\n\n".encode()
        with self.lock:
            if keep:
                self.last[kind] = msg
            for q in list(self.clients):
                q.put(msg)

    def subscribe(self):
        q = queue.Queue()
        with self.lock:
            self.clients.append(q)
            for msg in self.last.values():
                q.put(msg)
        return q

    def unsubscribe(self, q):
        with self.lock:
            if q in self.clients:
                self.clients.remove(q)


hub = Hub()


def load_calib():
    try:
        with open(CALIB_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_calib(data):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = CALIB_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, CALIB_FILE)


from guide import Guide  # noqa: E402

# Calibration guidée pilotée depuis l'app iOS (via le hub : /api/projector/guide).
guide = Guide(hub, load_calib, save_calib)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)) or body is None:
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return None

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in FILES:
            name, ctype = FILES[path]
            with open(os.path.join(HERE, name), "rb") as f:
                return self._send(200, f.read(), ctype)
        for prefix, ext, ctype in (("/heads/", ".png", "image/png"), ("/fonts/", ".woff2", "font/woff2")):
            name = path[len(prefix):]
            if path.startswith(prefix) and name.endswith(ext) and "/" not in name and not name.startswith("."):
                p = os.path.join(HERE, prefix.strip("/"), name)
                if os.path.exists(p):
                    with open(p, "rb") as f:
                        return self._send(200, f.read(), ctype)
        if path == "/calib.json":
            return self._send(200, dict(load_calib() or {}, screen=hub.screen))
        if path == "/guide":
            return self._send(200, guide.state())
        if path == "/events":
            return self._events()
        self._send(404, {"error": "inconnu"})

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._body()
        if body is None:
            return self._send(400, {"error": "json"})
        if path == "/calib.json":
            pts = body.get("points")
            if not (isinstance(pts, list) and len(pts) == 4 and all(isinstance(p, list) and len(p) == 2 for p in pts)):
                return self._send(400, {"error": "4 points [x, y] attendus"})
            data = {"points": [[float(x), float(y)] for x, y in pts], "pattern": bool(body.get("pattern"))}
            pairs = body.get("pairs")
            if isinstance(pairs, list) and all(
                isinstance(q, dict) and isinstance(q.get("mm"), list) and isinstance(q.get("px"), list)
                and len(q["mm"]) == 2 and len(q["px"]) == 2 for q in pairs
            ):
                # Correspondances relevées en calibration guidée (point de la cible en mm, pixel visé).
                data["pairs"] = [{"id": str(q.get("id", "")), "mm": [float(v) for v in q["mm"]],
                                  "px": [float(v) for v in q["px"]]} for q in pairs[:64]]
            rings = body.get("rings")
            if isinstance(rings, dict):
                # Rayons réels mesurés (mm) : fil intérieur du double, fils du triple, bord de cible, surround.
                ok = {k: float(v) for k, v in rings.items()
                      if k in ("dIn", "tOut", "tIn", "board", "sur") and isinstance(v, (int, float)) and 20 < v < 600}
                data["rings"] = ok
            pr = body.get("projector")
            if isinstance(pr, dict) and all(isinstance(pr.get(k), (int, float)) for k in "xyz"):
                data["projector"] = {k: float(pr[k]) for k in "xyz"}
            if body.get("save", True):
                save_calib(dict(data, pattern=False))  # au démarrage, jamais la mire
            hub.send("calib", data, keep=True)
            return self._send(200, data)
        if path == "/test":
            # Essai depuis /calib : une fléchette ou un 180 joués sur l'image seulement (rien n'est envoyé au hub).
            kind = str(body.get("kind", ""))
            if kind == "180":
                hub.send("test", {"kind": "180"})
            else:
                n, m = SEGMENTS.get(kind, (20, 3))
                hub.send("dart", {"number": n, "multiplier": m, "test": True})
            return self._send(200, {"ok": True})
        if path == "/guide":
            return self._send(200, guide.action(body))
        if path == "/pointer":
            # Pointeur de la calibration guidée, en pixels d'écran ; {"off": true} le retire.
            if body.get("grid"):
                data = {"grid": True}  # mire rectangulaire plein écran, pour placer le projecteur
            elif body.get("off") or not isinstance(body.get("x"), (int, float)):
                data = {"off": True}
            else:
                done = [p for p in body.get("done", []) if isinstance(p, list) and len(p) == 2][:64]
                shape = [[[float(v) for v in q] for q in pl if isinstance(q, list) and len(q) == 2][:80]
                         for pl in body.get("shape", []) if isinstance(pl, list)][:8]
                data = {"x": float(body["x"]), "y": float(body["y"]), "done": done, "shape": shape}
            hub.send("pointer", data, keep=True)
            return self._send(200, data)
        if path == "/screen":
            w, h = body.get("w"), body.get("h")
            if isinstance(w, (int, float)) and isinstance(h, (int, float)) and 100 < w < 10000 and 100 < h < 10000:
                hub.screen = [int(w), int(h)]
            return self._send(200, {"screen": hub.screen})
        if path == "/light":
            ms = max(0, min(int(body.get("ms", 0)), MAX_BUSY_MS))
            until = int(time.time() * 1000) + ms
            if hub.client:
                hub.client.publish(LIGHT_TOPIC, json.dumps({"until": until}), qos=0)
            return self._send(200, {"until": until})
        self._send(404, {"error": "inconnu"})

    def _events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        q = hub.subscribe()
        try:
            while True:
                try:
                    msg = q.get(timeout=15)
                except queue.Empty:
                    msg = b": ping\n\n"
                self.wfile.write(msg)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            hub.unsubscribe(q)


def start():
    """Lance le projecteur (MQTT + HTTP) dans des fils de fond. Appelé par le service caméras :
    une mise à jour OTA suffit, pas de nouveau service systemd à installer."""
    calib = load_calib()
    if calib:
        hub.send("calib", calib, keep=True)
    client = new_client("dartos-cam-projector")

    def on_connect(c, *_):
        for t in (DART_TOPIC, TAKEOUT_TOPIC, STATE_TOPIC, TURN_TOPIC, HUB_PROJECTOR_TOPIC):
            c.subscribe(t, qos=1)

    def on_message(c, userdata, msg):
        try:
            data = json.loads(msg.payload)
        except ValueError:
            return
        kind = {DART_TOPIC: "dart", TAKEOUT_TOPIC: "takeout", STATE_TOPIC: "state",
                TURN_TOPIC: "turn", HUB_PROJECTOR_TOPIC: "game"}.get(msg.topic)
        if kind:
            # L'état de la partie et du hub est gardé pour une page qui (re)démarre.
            hub.send(kind, data, keep=kind in ("state", "game"))

    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(1, 30)
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()
    hub.client = client
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"projecteur sur le port {PORT}", flush=True)
    return server


def main():
    start()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
