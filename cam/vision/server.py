"""Service caméras du Pi 5 : possède les 3 caméras, sert l'aperçu en MJPEG sur HTTP (port 8081)
et publie le statut retenu thibsdarts/cam/status. La détection lira plus tard les mêmes images.

Une caméra ne s'ouvre que si quelqu'un la regarde, et se ferme après IDLE secondes sans client.
"""

import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "simulator"))
from dartlink import MQTT_HOST, MQTT_PORT, STATUS_TOPIC, VERSION, new_client  # noqa: E402

PORT = int(os.environ.get("CAM_HTTP_PORT", "8081"))
IDLE = 10
PREVIEW_SIZE = (640, 360)
PREVIEW_FPS = 12

# Caméras repérées par leur prise USB (elles ont toutes le même numéro de série).
CAMS = {
    "A": "/dev/v4l/by-path/platform-xhci-hcd.0-usb-0:2:1.0-video-index0",
    "B": "/dev/v4l/by-path/platform-xhci-hcd.0-usb-0:1:1.0-video-index0",
    "C": "/dev/v4l/by-path/platform-xhci-hcd.1-usb-0:1:1.0-video-index0",
}


class Camera:
    def __init__(self, name, path):
        self.name, self.path = name, path
        self.jpeg = None
        self.seq = 0
        self.fps = 0.0
        self.size = None
        self.error = None
        self.last_use = 0.0
        self.cond = threading.Condition()
        self.thread = None

    @property
    def plugged(self):
        return os.path.exists(self.path)

    @property
    def streaming(self):
        return self.thread is not None and self.thread.is_alive()

    def touch(self):
        """Un client regarde : démarre la capture si besoin."""
        with self.cond:
            self.last_use = time.monotonic()
            if not self.streaming:
                self.thread = threading.Thread(target=self._run, daemon=True)
                self.thread.start()

    def wait_frame(self, after, timeout=3.0):
        with self.cond:
            self.cond.wait_for(lambda: self.seq != after and self.jpeg is not None, timeout)
            return self.seq, self.jpeg

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
        frames, t0, last_preview = 0, time.monotonic(), 0.0
        try:
            while time.monotonic() - self.last_use < IDLE:
                ok, frame = cap.read()
                if not ok:
                    self.error = "lecture impossible"
                    break
                now = time.monotonic()
                frames += 1
                if now - t0 >= 1:
                    self.fps, frames, t0 = frames / (now - t0), 0, now
                self.size = (frame.shape[1], frame.shape[0])
                if now - last_preview < 1 / PREVIEW_FPS:
                    continue
                last_preview = now
                small = cv2.resize(frame, PREVIEW_SIZE, interpolation=cv2.INTER_AREA)
                ok, buf = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 70])
                if ok:
                    with self.cond:
                        self.jpeg = buf.tobytes()
                        self.seq += 1
                        self.cond.notify_all()
        finally:
            cap.release()
            self.fps = 0.0

    def status(self):
        return {
            "name": self.name,
            "online": self.plugged and self.error is None,
            "streaming": self.streaming,
            "fps": round(self.fps, 1),
            "width": self.size[0] if self.size else None,
            "height": self.size[1] if self.size else None,
            "error": self.error,
        }


cameras = {k: Camera(k, p) for k, p in CAMS.items()}


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
            body = {"version": VERSION, "preview": base_url(), "cams": [c.status() for c in cameras.values()]}
            return self._send(200, json.dumps(body).encode())
        parts = path.strip("/").split("/")
        if len(parts) == 2 and parts[0] == "cam":
            name, _, ext = parts[1].partition(".")
            cam = cameras.get(name)
            if cam and ext == "jpg":
                return self._snapshot(cam)
            if cam and ext == "mjpg":
                return self._stream(cam)
        self._send(404, b'{"error": "introuvable"}')

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
            while True:
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


def status(state):
    return json.dumps({
        "state": state,
        "mode": "sim",
        "version": VERSION,
        "preview": base_url(),
        "cams": {k: c.plugged for k, c in cameras.items()},
    })


def main():
    client = new_client("dartos-cam-vision")
    client.will_set(STATUS_TOPIC, status("offline"), qos=1, retain=True)
    client.on_connect = lambda c, *_: c.publish(STATUS_TOPIC, status("online"), qos=1, retain=True)
    client.reconnect_delay_set(1, 30)
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"aperçu caméras sur {base_url()}", flush=True)
    try:
        server.serve_forever()
    finally:
        client.publish(STATUS_TOPIC, status("offline"), qos=1, retain=True).wait_for_publish(2)
        client.loop_stop()


if __name__ == "__main__":
    main()
