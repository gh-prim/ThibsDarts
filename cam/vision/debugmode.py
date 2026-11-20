"""Mode Debug : chaque décision de la détection (fléchette comptée, tache ignorée, changement sans
fléchette, gros changement, retrait) garde ses photos pour qu'on puisse les relire après coup.

Réglages dans <données>/debug.json, gardés après un redémarrage ou un déploiement :
  on        : captures actives
  projector : vidéoprojecteur allumé (False : image noire, pour tester la détection sans lui)

Captures dans <données>/debug/<AAAAMMJJ-HHMMSS-mmm>-<type>/ :
  <caméra>-avant.jpg, <caméra>-apres.jpg, <caméra>-diff.jpg (écart x4), info.json
"Signaler" (bouton du hub) écrit un dossier ...-SIGNALE avec les images du moment.
Les 400 dernières captures sont gardées. Écriture dans un fil à part : la détection n'attend pas.

MQTT : thibsdarts/debug/set {on?, projector?} (hub -> Pi 5), thibsdarts/debug/state retenu (Pi 5 -> tous),
thibsdarts/debug/mark {} (hub -> Pi 5), thibsdarts/debug/event {ts, kind, text, dir} (Pi 5 -> hub).
"""

import json
import os
import queue
import re
import threading
import time

import cv2

SET_TOPIC = "thibsdarts/debug/set"
STATE_TOPIC = "thibsdarts/debug/state"
MARK_TOPIC = "thibsdarts/debug/mark"
EVENT_TOPIC = "thibsdarts/debug/event"
KEEP = 400


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "x"


def kind_of(text):
    t = text.lower()
    for key, kind in (("tache ignorée", "ignore"), ("sans fléchette", "rien"), ("gros changement", "gros"),
                      ("retirée", "retrait"), ("nouveau tour", "tour"), ("fléchette", "flechette")):
        if key in t:
            return kind
    return "autre"


class DebugMode:
    def __init__(self, data_dir):
        self.file = os.path.join(data_dir, "debug.json")
        self.dir = os.path.join(data_dir, "debug")
        self.on, self.projector = False, True
        self.client = None
        try:
            with open(self.file) as f:
                d = json.load(f)
            self.on, self.projector = bool(d.get("on")), bool(d.get("projector", True))
        except (OSError, ValueError, AttributeError):
            pass
        self.q = queue.Queue(maxsize=16)
        threading.Thread(target=self._writer, daemon=True).start()

    # ---------- réglages ----------
    def state(self):
        return {"on": self.on, "projector": self.projector}

    def set(self, d):
        if "on" in d:
            self.on = bool(d["on"])
        if "projector" in d:
            self.projector = bool(d["projector"])
        tmp = self.file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.state(), f)
        os.replace(tmp, self.file)
        print(f"debug : {'actif' if self.on else 'arrêté'}, projecteur {'allumé' if self.projector else 'éteint'}",
              flush=True)
        self.publish_state()

    def publish_state(self):
        if self.client:
            self.client.publish(STATE_TOPIC, json.dumps(self.state()), qos=1, retain=True)

    # ---------- captures ----------
    def capture(self, text, frames, extra=None, kind=None):
        """frames : {caméra: (avant, après)} en gris pleine résolution, ou {caméra: image} (Signaler)."""
        if not self.on:
            return
        kind = kind or kind_of(text)
        now = time.time()
        name = time.strftime("%Y%m%d-%H%M%S", time.localtime(now)) + f"-{int(now * 1000) % 1000:03d}-{kind}"
        try:
            self.q.put_nowait((name, text, frames, extra or {}))
        except queue.Full:
            print("debug : capture perdue (disque trop lent)", flush=True)
            return
        if self.client:
            self.client.publish(EVENT_TOPIC, json.dumps({"ts": int(now * 1000), "kind": kind, "text": text,
                                                         "dir": name}, ensure_ascii=False), qos=0)

    def _writer(self):
        while True:
            name, text, frames, extra = self.q.get()
            try:
                self._write(name, text, frames, extra)
                self._prune()
            except (OSError, cv2.error, ValueError, TypeError) as e:
                print(f"debug {name} : {e}", flush=True)

    def _write(self, name, text, frames, extra):
        d = os.path.join(self.dir, name)
        os.makedirs(d, exist_ok=True)
        q = [cv2.IMWRITE_JPEG_QUALITY, 88]
        for cam, imgs in frames.items():
            s = slug(cam)
            if isinstance(imgs, tuple):
                before, after = imgs
                cv2.imwrite(os.path.join(d, f"{s}-avant.jpg"), before, q)
                cv2.imwrite(os.path.join(d, f"{s}-apres.jpg"), after, q)
                diff = cv2.convertScaleAbs(cv2.absdiff(after, before), alpha=4)
                cv2.imwrite(os.path.join(d, f"{s}-diff.jpg"), diff, q)
            else:
                cv2.imwrite(os.path.join(d, f"{s}.jpg"), imgs, q)
        info = dict(extra, text=text, ts=time.strftime("%Y-%m-%d %H:%M:%S"), projector=self.projector)
        with open(os.path.join(d, "info.json"), "w") as f:
            json.dump(info, f, ensure_ascii=False, indent=1, default=str)

    def _prune(self):
        names = sorted(os.listdir(self.dir))
        for n in names[:-KEEP]:
            p = os.path.join(self.dir, n)
            for f in os.listdir(p):
                os.remove(os.path.join(p, f))
            os.rmdir(p)
