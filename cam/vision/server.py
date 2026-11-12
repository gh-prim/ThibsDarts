"""Service caméras du Pi 5 : possède les caméras, sert l'aperçu en MJPEG sur HTTP (port 8081)
et publie le statut retenu thibsdarts/cam/status. Pendant une partie, les caméras calibrées restent
ouvertes et detector.py y cherche les fléchettes (publiées sur thibsdarts/cam/dart).

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

import detector
import identity

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "simulator"))
from dartlink import (  # noqa: E402
    DART_TOPIC, MQTT_HOST, MQTT_PORT, STATE_TOPIC, STATUS_TOPIC, TAKEOUT_TOPIC, VERSION,
    dart_at, dart_message, new_client, segment_name,
)

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
# Une caméra en bas (6 h), les deux autres à un tiers du tour de chaque côté (10 h et 2 h).
PRESET_NAMES = ["Bas", "Haut gauche", "Haut droite"]
DETECT_FPS = 10
# Mode test de la page /calib : détection active sans partie, pendant 10 min.
TEST_DURATION = 600


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
        self.frame = None  # dernière image pleine résolution (BGR)
        self.frame_seq = 0
        self.opened = 0
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
                self.frame, self.frame_seq, self.opened = frame, self.frame_seq + 1, opened
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
            self.fps, self.size, self.frame, self.opened = 0.0, None, None, 0
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

    @property
    def ready(self):
        """Image pleine résolution disponible, exposition stabilisée."""
        return self.frame is not None and self.opened > 30

    def status(self):
        return {
            "id": self.id,
            "label": self.label,
            "calibrated": registry.calibs.get(self.label) is not None,
            "calib": registry.calibs.get(self.label).to_json() if registry.calibs.get(self.label) else None,
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
        self.calibs = None
        self.client = None
        self.playing = False
        self.test_until = 0.0
        self.events = []  # dernières fléchettes et retraits, pour la page /calib
        self.detector = detector.Detector(self.on_dart, self.on_takeout, log=lambda m: print(m, flush=True))

    @property
    def mode(self):
        return "vision" if self.calibs and self.calibs.cals else "sim"

    @property
    def detecting(self):
        return self.mode == "vision" and (self.playing or time.monotonic() < self.test_until)

    def on_dart(self, x, y, info):
        n, m = dart_at(x, y, self.calibs.rings())
        print(f"fléchette {segment_name(n, m)} ({x:.1f}, {y:.1f}) vue par {', '.join(info['cams'])}", flush=True)
        self._event({"type": "dart", "segment": segment_name(n, m), "x": round(x, 1), "y": round(y, 1),
                     "cams": info["cams"]})
        if self.client:
            self.client.publish(DART_TOPIC, dart_message(n, m, x, y, source="vision"), qos=1)

    def on_takeout(self):
        self._event({"type": "takeout"})
        if self.client:
            self.client.publish(TAKEOUT_TOPIC, json.dumps({"ts": int(time.time() * 1000)}), qos=1)

    def _event(self, e):
        e["ts"] = int(time.time() * 1000)
        self.events = (self.events + [e])[-20:]

    def detect_loop(self):
        """Lit les caméras calibrées à DETECT_FPS images/s et les passe au détecteur."""
        was = False
        while True:
            time.sleep(1 / DETECT_FPS)
            if not self.detecting:
                if was:
                    self.detector.reset()
                was = False
                continue
            if not was:
                self.detector.reset()
                was = True
            frames, cals = {}, {}
            for cam in self.ordered():
                cal = self.calibs.get(cam.label)
                if cal is None or not cam.plugged:
                    continue
                cam.touch()
                frame = cam.frame
                if not cam.ready or frame is None:
                    continue
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                if (gray.shape[1], gray.shape[0]) != cal.size:
                    gray = cv2.resize(gray, cal.size)
                frames[cam.label], cals[cam.label] = gray, cal
            if frames:
                try:
                    self.detector.step(frames, cals)
                except cv2.error as e:
                    print(f"détection : {e}", flush=True)

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
            "mode": self.mode,
            "detecting": self.detecting,
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
        if path in ("/", "/calib"):
            with open(os.path.join(os.path.dirname(__file__), "calib.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if path == "/detect":
            return self._send(200, json.dumps(detect_status(), ensure_ascii=False).encode())
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
        if len(parts) == 3 and parts[0] == "cam" and parts[2] in ("full.jpg", "calib.jpg"):
            cam = registry.get(parts[1])
            if cam:
                return self._full(cam, overlay=parts[2] == "calib.jpg")
        self._send(404, b'{"error": "introuvable"}')

    def _body(self):
        body = json.loads(read_body(self) or b"{}")
        if not isinstance(body, dict):
            raise ValueError
        return body

    def do_POST(self):
        parts = self.path.split("?")[0].strip("/").split("/")
        # POST /detect {"test": true} : détection active 10 min sans partie (page /calib).
        if parts == ["detect"]:
            try:
                on = bool(self._body().get("test"))
            except ValueError:
                return self._send(400, b'{"error": "json"}')
            registry.test_until = time.monotonic() + TEST_DURATION if on else 0.0
            registry.publish_status("online")
            return self._send(200, json.dumps(detect_status(), ensure_ascii=False).encode())
        cam = registry.get(parts[1]) if len(parts) == 3 and parts[0] == "cam" else None
        # POST /cam/<id>/calib {"points": [[x, y] x 5]} (pleine résolution), [] : oublie la calibration.
        if cam is not None and parts[2] == "calib":
            return self._calib(cam)
        # POST /cam/<id>/name {"name": "Haut"} : la caméra garde ce nom même changée de port.
        if cam is None or parts[2] != "name":
            return self._send(404, b'{"error": "introuvable"}')
        try:
            name = str(self._body().get("name") or "").strip()[:24]
        except ValueError:
            return self._send(400, b'{"error": "nom"}')
        if not registry.rename(cam, name):
            return self._send(503, b'{"error": "camera"}')
        self._send(200, json.dumps(cam.status(), ensure_ascii=False).encode())

    def _calib(self, cam):
        if not cam.label:
            return self._send(409, json.dumps({"error": "nomme d'abord la caméra"}, ensure_ascii=False).encode())
        try:
            points = self._body().get("points") or []
            size = cam.size or (1280, 720)
            cal = detector.Calibration(points, size) if points else None
        except (ValueError, TypeError, cv2.error):
            return self._send(400, json.dumps({"error": "points incohérents (5 ou 8 points, sur les bonnes bandes)"},
                                              ensure_ascii=False).encode())
        registry.calibs.set(cam.label, cal)
        registry.detector.forget(cam.label)
        registry.publish_status("online")
        body = cam.status()
        body["error_px"] = round(cal.error(), 1) if cal else None
        self._send(200, json.dumps(body, ensure_ascii=False).encode())

    def _full(self, cam, overlay):
        """Image pleine résolution, avec la cible calibrée dessinée par-dessus si overlay."""
        if not cam.plugged:
            return self._send(503, b'{"error": "camera"}')
        cam.touch()
        deadline = time.monotonic() + 8
        while not cam.ready and time.monotonic() < deadline:
            time.sleep(0.1)
        frame = cam.frame
        if frame is None:
            return self._send(503, b'{"error": "camera"}')
        img = frame.copy()
        cal = registry.calibs.get(cam.label)
        if overlay and cal is not None:
            detector.draw_board(img, cal)
        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 88])
        if not ok:
            return self._send(503, b'{"error": "camera"}')
        self._send(200, buf.tobytes(), "image/jpeg")

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


def detect_status():
    return {
        "mode": registry.mode,
        "detecting": registry.detecting,
        "playing": registry.playing,
        "test": max(0, int(registry.test_until - time.monotonic())),
        "darts": registry.detector.darts,
        "events": registry.events,
        "points": detector.CALIB_HELP,
        "spec": detector.CALIB_SPEC,
        "legacy": detector.LEGACY_SPEC,
        "rings": registry.calibs.rings(),
        "rings_standard": detector.STANDARD_RINGS,
        "cams": [c.status() for c in registry.ordered()],
    }


def read_body(handler):
    """Corps d'une requête, avec Content-Length ou en "chunked" (le HttpClient de Dart, par défaut)."""
    if "chunked" in handler.headers.get("Transfer-Encoding", "").lower():
        data = b""
        while True:
            size = int(handler.rfile.readline().split(b";")[0].strip() or b"0", 16)
            if size == 0:
                handler.rfile.readline()
                return data
            data += handler.rfile.read(size)
            handler.rfile.readline()
    return handler.rfile.read(int(handler.headers.get("Content-Length", 0) or 0))


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
    registry.calibs = detector.CalibStore(DATA_DIR)
    client = new_client("dartos-cam-vision")
    client.will_set(STATUS_TOPIC, registry.status("offline"), qos=1, retain=True)
    def on_connect(c, *_):
        c.subscribe(CMD_TOPIC, qos=1)
        c.subscribe(STATE_TOPIC, qos=1)
        registry.publish_status("online")

    def on_state(c, userdata, msg):
        try:
            on = bool(json.loads(msg.payload).get("playing"))
        except (ValueError, AttributeError):
            on = False
        if on != registry.playing:
            print(f"hub : partie {'en cours' if on else 'arrêtée'}", flush=True)
            registry.playing = on
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
    client.message_callback_add(STATE_TOPIC, on_state)
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
    threading.Thread(target=registry.detect_loop, daemon=True).start()
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
