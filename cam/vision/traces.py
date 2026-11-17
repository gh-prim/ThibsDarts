"""Trace des dernières fléchettes : ce que chaque caméra a capté, pour l'écran Corriger du Pi 4.

Pour chaque fléchette : les images avant / après de chaque caméra (JPEG, gris), le masque de la tache
retenue et les mesures (pointe, axe, taille). Les 30 dernières sont gardées dans <données>/traces/.
L'écriture se fait dans un fil à part : la détection n'attend pas le disque.
L'overlay n'est dessiné qu'à la demande (GET /trace/<id>/<caméra>.jpg), jamais pendant le jeu.
"""

import json
import os
import queue
import re
import shutil
import threading
import time

import cv2
import numpy as np

import detector

KEEP = 30
# Une couleur par caméra (BGR), la même que sur le Pi 4.
CAM_COLORS = {"Bas": (255, 200, 40), "Haut gauche": (200, 80, 255), "Haut droite": (80, 220, 80)}
OTHER_COLOR = (180, 180, 180)
FINAL_COLOR = (255, 255, 255)


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "camera"


def _r(v, n=1):
    return [round(float(x), n) for x in v]


class TraceStore:
    def __init__(self, data_dir, segment):
        self.dir = os.path.join(data_dir, "traces")
        self.segment = segment  # (x, y) -> "T20"
        self.q = queue.Queue(maxsize=8)
        os.makedirs(self.dir, exist_ok=True)
        threading.Thread(target=self._writer, daemon=True).start()

    def save(self, dart_id, info):
        """Appelé par la détection : met la trace en file, sans bloquer."""
        try:
            self.q.put_nowait((dart_id, info))
        except queue.Full:
            pass

    def _writer(self):
        while True:
            dart_id, info = self.q.get()
            try:
                self._write(dart_id, info)
                self._prune()
            except (OSError, cv2.error, ValueError) as e:
                print(f"trace {dart_id} : {e}", flush=True)

    def _write(self, dart_id, info):
        d = os.path.join(self.dir, dart_id)
        os.makedirs(d, exist_ok=True)
        obs = {o["cam"]: o for o in info["obs"]}
        cams = {}
        for name, (before, after) in info["frames"].items():
            s = slug(name)
            cv2.imwrite(os.path.join(d, f"{s}-avant.jpg"), before, [cv2.IMWRITE_JPEG_QUALITY, 90])
            cv2.imwrite(os.path.join(d, f"{s}-apres.jpg"), after, [cv2.IMWRITE_JPEG_QUALITY, 90])
            o = obs.get(name)
            c = {"seen": o is not None, "change": round(float(info["change"].get(name, 0)), 4)}
            if o is None and info.get("why", {}).get(name):
                c["why"] = info["why"][name]
            if o is not None:
                cv2.imwrite(os.path.join(d, f"{s}-masque.png"), o["mask"])
                c.update({
                    "tip": _r(o["tip"]),
                    "segment": self.segment(*o["tip"]),
                    "dir": None if o.get("dir") is None else _r(o["dir"], 4),
                    "tip_img": _r(o["tip_img"]),
                    "tail_img": _r(o["tail_img"]),
                    "area": int(o["area"]),
                    "length": round(float(o["length"]), 1),
                    "bbox": [int(v) for v in o["bbox"]],
                })
            cams[name] = c
        trace = {
            "id": dart_id,
            "ts": int(time.time() * 1000),
            "x": round(info["x"], 1),
            "y": round(info["y"], 1),
            "segment": self.segment(info["x"], info["y"]),
            "raw": _r(info.get("raw", (info["x"], info["y"]))),
            "cams": cams,
        }
        with open(os.path.join(d, "trace.json"), "w") as f:
            json.dump(trace, f, ensure_ascii=False)

    def _prune(self):
        dirs = sorted((e for e in os.scandir(self.dir) if e.is_dir()), key=lambda e: e.stat().st_mtime)
        for e in dirs[:-KEEP]:
            shutil.rmtree(e.path, ignore_errors=True)

    def _path(self, dart_id):
        if not re.fullmatch(r"[0-9a-f-]{8,40}", dart_id or ""):
            return None
        d = os.path.join(self.dir, dart_id)
        return d if os.path.isdir(d) else None

    def get(self, dart_id):
        d = self._path(dart_id)
        if d is None:
            return None
        try:
            with open(os.path.join(d, "trace.json")) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def list(self):
        out = []
        for e in sorted(os.scandir(self.dir), key=lambda e: e.stat().st_mtime, reverse=True):
            t = self.get(e.name) if e.is_dir() else None
            if t:
                out.append({"id": t["id"], "ts": t["ts"], "segment": t["segment"]})
        return out

    def image(self, dart_id, cam, cal, view="apres", overlay=True, zoom=False):
        """JPEG de la caméra pour cette fléchette, avec l'overlay dessiné maintenant."""
        d = self._path(dart_id)
        trace = self.get(dart_id)
        if d is None or trace is None or cam not in trace["cams"]:
            return None
        s = slug(cam)
        gray = cv2.imread(os.path.join(d, f"{s}-{'avant' if view == 'avant' else 'apres'}.jpg"), cv2.IMREAD_GRAYSCALE)
        if gray is None:
            return None
        img = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
        c = trace["cams"][cam]
        focus = None
        if overlay:
            if cal is not None:
                detector.draw_board(img, cal, color=(0, 200, 255), points=False)
            if c["seen"]:
                mask = cv2.imread(os.path.join(d, f"{s}-masque.png"), cv2.IMREAD_GRAYSCALE)
                x, y, w, h = c["bbox"]
                if mask is not None and mask.shape == (h, w):
                    roi = img[y:y + h, x:x + w]
                    tint = np.zeros_like(roi)
                    tint[:] = (0, 120, 255)
                    sel = mask > 0
                    roi[sel] = (roi[sel] * 0.45 + tint[sel] * 0.55).astype(np.uint8)
                color = CAM_COLORS.get(cam, OTHER_COLOR)
                tip, tail = np.int32(c["tip_img"]), np.int32(c["tail_img"])
                cv2.line(img, tuple(tip), tuple(tail), color, 2, cv2.LINE_AA)
                cv2.circle(img, tuple(tip), 6, (0, 0, 255), 2, cv2.LINE_AA)
                focus = c["tip_img"]
            if cal is not None:
                # Pointes vues par les autres caméras et point retenu, ramenés dans cette image.
                for other, oc in trace["cams"].items():
                    if other != cam and oc["seen"]:
                        p = np.int32(cal.to_image(oc["tip"]))
                        cv2.drawMarker(img, tuple(p), CAM_COLORS.get(other, OTHER_COLOR), cv2.MARKER_TILTED_CROSS, 14, 2)
                p = cal.to_image((trace["x"], trace["y"]))
                cv2.drawMarker(img, tuple(np.int32(p)), FINAL_COLOR, cv2.MARKER_CROSS, 22, 2)
                if focus is None:
                    focus = p
        elif c["seen"]:
            focus = c["tip_img"]
        if zoom:
            h, w = img.shape[:2]
            cw, ch = w // 4, h // 4
            fx, fy = (focus if focus is not None else (w / 2, h / 2))
            x0 = int(min(max(fx - cw / 2, 0), w - cw))
            y0 = int(min(max(fy - ch / 2, 0), h - ch))
            img = cv2.resize(img[y0:y0 + ch, x0:x0 + cw], (cw * 3, ch * 3), interpolation=cv2.INTER_NEAREST)
        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 88])
        return buf.tobytes() if ok else None
