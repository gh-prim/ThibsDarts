"""Service caméras du Pi 5 : possède les caméras, sert l'aperçu en MJPEG sur HTTP (port 8081)
et publie le statut retenu thibsdarts/cam/status. La détection lira plus tard les mêmes images.

Les caméras sont cherchées dans /dev/v4l toutes les quelques secondes : on peut les débrancher
et les rebrancher sur n'importe quel port. Elles sont reconnues à leur vue (identity.py), pas
à leur port. Une caméra ne reste ouverte que si quelqu'un la regarde (ou le temps de la reconnaître).
"""

import glob
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

import identity

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "simulator"))
from dartlink import MQTT_HOST, MQTT_PORT, STATUS_TOPIC, VERSION, new_client  # noqa: E402

PORT = int(os.environ.get("CAM_HTTP_PORT", "8081"))
DATA_DIR = os.environ.get("DARTOS_DATA", "/data/thibsdarts")
IDLE = 10
PREVIEW_SIZE = (640, 360)
PREVIEW_FPS = 12
# Une vue est reprise pour la reconnaissance au branchement, puis toutes les 30 s pendant l'aperçu.
VIEW_EVERY = 30
MOTION_TOPIC = "thibsdarts/cam/motion"
CMD_TOPIC = "thibsdarts/cam/cmd"
# DARTOS_DRY_POWER=1 : on note la demande d'extinction sans éteindre (tests).
DRY_POWER = os.environ.get("DARTOS_DRY_POWER") == "1"
PRESET_NAMES = ["Haut", "Bas gauche", "Bas droite", "Gauche", "Droite"]


class Camera:
    def __init__(self, cid, path):
        self.id, self.path = cid, path
        self.jpeg = None
        self.seq = 0
        self.fps = 0.0
        self.size = None
        self.error = None
        self.last_use = 0.0
        self.probe_until = 0.0
        self.motion = 0.0
        self.view = None  # (image grise, features) pour la reconnaissance
        self.view_time = 0.0
        self.label = None
        self.match = 0
        self.cond = threading.Condition()
        self.thread = None

    @property
    def plugged(self):
        return os.path.exists(self.path)

    @property
    def streaming(self):
        return self.thread is not None and self.thread.is_alive()

    def _start(self):
        if not self.streaming:
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()

    def touch(self):
        """Un client regarde : démarre la capture si besoin."""
        with self.cond:
            self.last_use = time.monotonic()
            self._start()

    def probe(self):
        """Ouvre la caméra quelques secondes, le temps de prendre une vue pour la reconnaître."""
        with self.cond:
            self.view_time = 0.0
            self.probe_until = time.monotonic() + 4
            self._start()

    def wait_frame(self, after, timeout=3.0):
        with self.cond:
            self.cond.wait_for(lambda: self.seq != after and self.jpeg is not None, timeout)
            return self.seq, self.jpeg

    def wait_view(self, timeout=6.0):
        with self.cond:
            self.cond.wait_for(lambda: self.view is not None and self.view_time > 0, timeout)
            return self.view

    def _run(self):
        cap = cv2.VideoCapture(self.path, cv2.CAP_V4L2)
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        cap.set(cv2.CAP_PROP_FPS, 30)
        if not cap.isOpened():
            self.error = "ouverture impossible"
            return
        self.error = None
        frames, opened, t0, last_preview, prev = 0, 0, time.monotonic(), 0.0, None
        try:
            while True:
                now = time.monotonic()
                if now - self.last_use >= IDLE and now >= self.probe_until:
                    break
                ok, frame = cap.read()
                if not ok:
                    self.error = "lecture impossible"
                    break
                now = time.monotonic()
                frames += 1
                opened += 1
                if now - t0 >= 1:
                    self.fps, frames, t0 = frames / (now - t0), 0, now
                self.size = (frame.shape[1], frame.shape[0])
                if now - last_preview < 1 / PREVIEW_FPS:
                    continue
                last_preview = now
                small = cv2.resize(frame, PREVIEW_SIZE, interpolation=cv2.INTER_AREA)
                prev = self._update_motion(small, prev)
                # Vue pour la reconnaissance, une fois l'exposition stabilisée.
                if opened > 20 and now - self.view_time > VIEW_EVERY and not self.moving:
                    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
                    with self.cond:
                        self.view, self.view_time = (gray, identity.features(gray)), now
                        self.cond.notify_all()
                    registry.reassign()
                ok, buf = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 70])
                if ok:
                    with self.cond:
                        self.jpeg = buf.tobytes()
                        self.seq += 1
                        self.cond.notify_all()
        finally:
            cap.release()
            self.fps, self.size = 0.0, None
            self._set_motion(0.0)

    def _update_motion(self, small, prev):
        """Part de l'image qui a bougé depuis l'aperçu précédent (main passée devant, par exemple)."""
        gray = cv2.GaussianBlur(cv2.cvtColor(cv2.resize(small, (160, 90)), cv2.COLOR_BGR2GRAY), (5, 5), 0)
        if prev is not None:
            moved = cv2.threshold(cv2.absdiff(gray, prev), 25, 255, cv2.THRESH_BINARY)[1]
            self._set_motion(cv2.countNonZero(moved) / moved.size)
        return gray

    @property
    def moving(self):
        return self.motion > 0.03

    def _set_motion(self, value):
        was = self.moving
        self.motion = value
        if was != self.moving:
            registry.publish_motion()

    def status(self):
        return {
            "id": self.id,
            "label": self.label,
            "recognized": self.label is not None,
            "match": self.match,
            "motion": round(self.motion, 3),
            "moving": self.moving,
            "online": self.plugged and self.error is None,
            "streaming": self.streaming,
            "fps": round(self.fps, 1),
            "width": self.size[0] if self.size else None,
            "height": self.size[1] if self.size else None,
            "error": self.error,
        }


class Registry:
    """Caméras branchées (par chemin /dev/v4l), noms reconnus, MQTT."""

    def __init__(self):
        self.cams = {}
        self.lock = threading.RLock()
        self.refs = None
        self.client = None

    def ordered(self):
        with self.lock:
            return sorted(self.cams.values(), key=lambda c: c.id)

    def get(self, cid):
        with self.lock:
            return self.cams.get(cid)

    def scan(self):
        """Ajoute les caméras branchées, retire celles qui ont disparu."""
        # Le noyau crée deux liens par caméra (usb- et usbv2-) : un seul suffit.
        paths = sorted(p for p in glob.glob("/dev/v4l/by-path/*-usb-*-video-index0"))
        changed = False
        with self.lock:
            for p in paths:
                cid = camera_id(p)
                if cid not in self.cams:
                    cam = Camera(cid, p)
                    self.cams[cid] = cam
                    cam.probe()
                    changed = True
            for cid, cam in list(self.cams.items()):
                if not cam.plugged and not cam.streaming:
                    del self.cams[cid]
                    changed = True
        if changed:
            self.reassign()

    def reassign(self):
        with self.lock:
            views = {c.id: c.view[1] for c in self.cams.values() if c.view}
            result = identity.assign(views, self.refs.features()) if views and self.refs.refs else {}
            for c in self.cams.values():
                c.label, c.match = result.get(c.id, (None, 0))
        self.publish_status("online")

    def rename(self, cam, name):
        """Nomme la caméra d'après sa vue actuelle. Vide : oublie son nom."""
        view = cam.view if cam.view_time and time.monotonic() - cam.view_time < 5 else None
        if view is None:
            cam.probe()
            view = cam.wait_view()
        with self.lock:
            old = cam.label
            if old and old != name:
                self.refs.remove(old)
            if name and view is not None:
                self.refs.set(name, view[0])
        self.reassign()
        return view is not None or not name

    def status(self, state):
        return json.dumps({
            "state": state,
            "mode": "sim",
            "version": VERSION,
            "preview": base_url(),
            "cams": {c.id: c.label for c in self.ordered()},
            "health": health(),
        }, ensure_ascii=False)

    def publish_status(self, state):
        if self.client:
            self.client.publish(STATUS_TOPIC, self.status(state), qos=1, retain=True)

    def publish_motion(self):
        if self.client:
            self.client.publish(MOTION_TOPIC, json.dumps({c.id: c.moving for c in self.ordered()}), qos=0)


def health():
    """Température du Pi 5 et alertes d'alimentation (vcgencmd get_throttled)."""
    out = {}
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            out["temp"] = round(int(f.read()) / 1000, 1)
    except (OSError, ValueError):
        pass
    try:
        flags = int(subprocess.run(["vcgencmd", "get_throttled"], capture_output=True, text=True, timeout=2)
                    .stdout.strip().split("=")[1], 16)
        out["undervoltage"] = bool(flags & 0x1)
        out["throttled"] = bool(flags & 0x6)
        out["undervoltageSinceBoot"] = bool(flags & 0x10000)
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        pass
    return out


def camera_id(path):
    """Identifiant court de la prise (ex. "0-2"), pour les adresses de flux. Pas un nom de caméra."""
    m = re.search(r"xhci-hcd\.(\d+)-usb-0:([\d.]+):", path)
    return f"{m.group(1)}-{m.group(2)}" if m else re.sub(r"\W+", "-", os.path.basename(path))


registry = Registry()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/status":
            body = {
                "version": VERSION,
                "preview": base_url(),
                "presets": PRESET_NAMES,
                "known": registry.refs.names,
                "cams": [c.status() for c in registry.ordered()],
            }
            return self._send(200, json.dumps(body, ensure_ascii=False).encode())
        parts = path.strip("/").split("/")
        if len(parts) == 2 and parts[0] == "cam":
            cid, _, ext = parts[1].partition(".")
            cam = registry.get(cid)
            if cam and ext == "jpg":
                return self._snapshot(cam)
            if cam and ext == "mjpg":
                return self._stream(cam)
        self._send(404, b'{"error": "introuvable"}')

    def do_POST(self):
        # POST /cam/<id>/name {"name": "Haut"} : la caméra garde ce nom même changée de port.
        parts = self.path.split("?")[0].strip("/").split("/")
        cam = registry.get(parts[1]) if len(parts) == 3 and parts[0] == "cam" and parts[2] == "name" else None
        if cam is None:
            return self._send(404, b'{"error": "introuvable"}')
        try:
            length = int(self.headers.get("Content-Length", "0"))
            name = str(json.loads(self.rfile.read(length) or b"{}").get("name") or "").strip()[:24]
        except ValueError:
            return self._send(400, b'{"error": "nom"}')
        if not registry.rename(cam, name):
            return self._send(503, b'{"error": "camera"}')
        self._send(200, json.dumps(cam.status(), ensure_ascii=False).encode())

    def _snapshot(self, cam):
        if not cam.plugged:
            return self._send(503, b'{"error": "camera"}')
        cam.touch()
        _, jpeg = cam.wait_frame(cam.seq, timeout=8)
        if jpeg is None:
            return self._send(503, b'{"error": "camera"}')
        self._send(200, jpeg, "image/jpeg")

    def _stream(self, cam):
        if not cam.plugged:
            return self._send(503, b'{"error": "camera"}')
        self.send_response(200)
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        seq = -1
        try:
            while cam.plugged:
                cam.touch()
                new, jpeg = cam.wait_frame(seq)
                if new == seq or jpeg is None:
                    if not cam.streaming and cam.error:
                        break
                    continue
                seq = new
                self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(jpeg))
                self.wfile.write(jpeg + b"\r\n")
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass


def local_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect((MQTT_HOST, MQTT_PORT))
            return s.getsockname()[0]
    except OSError:
        return socket.gethostname()


def base_url():
    return f"http://{local_ip()}:{PORT}"


def main():
    registry.refs = identity.RefStore(DATA_DIR)
    client = new_client("dartos-cam-vision")
    client.will_set(STATUS_TOPIC, registry.status("offline"), qos=1, retain=True)
    def on_connect(c, *_):
        c.subscribe(CMD_TOPIC, qos=1)
        registry.publish_status("online")

    def on_power(c, userdata, msg):
        # Le hub s'éteint ou redémarre : le Pi 5 fait pareil.
        try:
            action = json.loads(msg.payload).get("action")
        except (ValueError, AttributeError):
            return
        if msg.retain:
            return
        # Mise à jour et reset usine : dans leur propre unité systemd, pour survivre à l'arrêt de ce service.
        if action in ("update", "factory-reset"):
            cmd = (["/usr/local/sbin/thibsdarts-update", "--force"] if action == "update"
                   else ["/usr/local/sbin/thibsdarts-factory-reset"])
            print(f"demande du hub : {action}{' (essai)' if DRY_POWER else ''}", flush=True)
            if action == "factory-reset":
                registry.publish_status("offline")
            if not DRY_POWER:
                subprocess.Popen(["sudo", "-n", "systemd-run", "--collect", f"--unit=thibsdarts-{action}-now", *cmd])
            return
        if action not in ("poweroff", "reboot"):
            return
        print(f"demande du hub : {action}{' (essai, rien ne s’éteint)' if DRY_POWER else ''}", flush=True)
        registry.publish_status("offline")
        if not DRY_POWER:
            subprocess.Popen(["sudo", "-n", "systemctl", action])

    client.on_connect = on_connect
    client.message_callback_add(CMD_TOPIC, on_power)
    client.reconnect_delay_set(1, 30)
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()
    registry.client = client

    def watch():
        n = 0
        while True:
            registry.scan()
            n += 1
            if n % 10 == 0:
                registry.publish_status("online")  # température à jour toutes les 30 s
            time.sleep(3)

    threading.Thread(target=watch, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"aperçu caméras sur {base_url()}", flush=True)
    try:
        server.serve_forever()
    finally:
        registry.publish_status("offline")
        client.loop_stop()


if __name__ == "__main__":
    main()
