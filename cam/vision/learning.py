"""Apprendre des corrections, sans toucher à la calibration.

Chaque fléchette détectée devient un exemple (les mesures de chaque caméra, pas les images).
Sans correction, on suppose que le segment détecté était le bon. Quand le joueur corrige en
touchant l'endroit exact sur la cible du Pi 4, l'exemple reçoit la vraie position.

À partir des exemples corrigés, on calcule :
- un décalage sur le côté de l'axe, par caméra et par zone de la cible (6 zones de 60°), si au moins
  MIN_SAMPLES corrections vont dans le même sens, limité à MAX_OFFSET mm ;
- un poids par caméra : celle dont l'axe passe souvent loin de la vraie pointe compte moins.

Un nouveau modèle n'est gardé que s'il retrouve plus de segments justes que l'ancien sur tous les
exemples enregistrés (rejeu). Tout est dans adjustments.json, effaçable d'un coup.
"""

import json
import math
import os
import threading
import time

import numpy as np

MIN_SAMPLES = 5
MAX_OFFSET = 8.0     # mm
MAX_EXAMPLES = 1000
ZONES = 6
RECALIBRATE_MM = 10.0  # écart médian au-delà duquel on conseille de recalibrer une caméra


def zone_of(x, y):
    a = math.degrees(math.atan2(x, -y)) % 360
    return int(a // (360 / ZONES))


def lateral(o, truth):
    """Distance (mm) entre la vraie pointe et l'axe vu par la caméra (ou sa pointe si pas d'axe)."""
    t, p = np.float64(truth), np.float64(o["tip"])
    if o.get("dir") is None:
        return float(np.linalg.norm(t - p))
    d = np.float64(o["dir"])
    v = t - p
    return float(abs(v[0] * d[1] - v[1] * d[0]))


class Model:
    """Décalages par (caméra, zone) et poids par caméra."""

    def __init__(self, data=None):
        data = data or {}
        self.offsets = {cam: {int(z): tuple(v) for z, v in zs.items()} for cam, zs in data.get("offsets", {}).items()}
        self.weights = dict(data.get("weights", {}))

    @property
    def empty(self):
        return not any(self.offsets.values()) and all(abs(w - 1) < 1e-6 for w in self.weights.values())

    def apply(self, obs):
        out = []
        for o in obs:
            o2 = dict(o)
            cam = o["cam"]
            tip = np.float64(o["tip"])
            off = self.offsets.get(cam, {}).get(zone_of(*tip))
            if off:
                o2["tip"] = tip + np.float64(off[:2])
            o2["weight"] = self.weights.get(cam, 1.0)
            out.append(o2)
        return out

    def to_json(self):
        return {"offsets": {c: {str(z): [round(v[0], 2), round(v[1], 2), v[2]] for z, v in zs.items()}
                            for c, zs in self.offsets.items()},
                "weights": {c: round(w, 3) for c, w in self.weights.items()}}


def fit(examples):
    """Nouveau modèle à partir des exemples corrigés (avec vraie position)."""
    per = {}  # (cam, zone) -> résidus
    lat = {}  # cam -> écarts latéraux
    for e in examples:
        if e.get("truth") is None:
            continue
        t = np.float64(e["truth"])
        for o in e["obs"]:
            res = t - np.float64(o["tip"])
            if o.get("dir") is not None:
                # Seul l'écart sur le côté compte : en profondeur (le long de l'axe), la caméra est
                # toujours imprécise et la fusion ne s'en sert presque pas.
                d = np.float64(o["dir"])
                res = res - (res @ d) * d
            per.setdefault((o["cam"], zone_of(*o["tip"])), []).append(res)
            lat.setdefault(o["cam"], []).append(lateral(o, t))
    offsets = {}
    for (cam, z), rs in per.items():
        if len(rs) < MIN_SAMPLES:
            continue
        rs = np.float64(rs)
        med = np.median(rs, axis=0)
        spread = np.median(np.linalg.norm(rs - med, axis=1))
        n = float(np.linalg.norm(med))
        # Décalage seulement s'il est net (plus grand que la dispersion) et utile (> 1,5 mm).
        if n < 1.5 or spread > n * 1.5:
            continue
        if n > MAX_OFFSET:
            med = med / n * MAX_OFFSET
        offsets.setdefault(cam, {})[z] = (float(med[0]), float(med[1]), len(rs))
    weights = {}
    meds = {cam: float(np.median(v)) for cam, v in lat.items() if len(v) >= MIN_SAMPLES}
    if meds:
        ref = float(np.median(list(meds.values())))
        for cam, m in meds.items():
            weights[cam] = float(np.clip((max(ref, 1.0) / max(m, 1.0)) ** 2, 0.3, 1.0))
    return Model({"offsets": {c: {str(z): list(v) for z, v in zs.items()} for c, zs in offsets.items()},
                  "weights": weights})


def score(model, examples, fuse, segment):
    """(segments justes, erreur moyenne en mm sur les exemples corrigés) avec ce modèle."""
    good, errs = 0, []
    for e in examples:
        obs = [dict(o, tip=np.float64(o["tip"]), dir=None if o.get("dir") is None else np.float64(o["dir"]))
               for o in e["obs"]]
        if not obs:
            continue
        x, y = fuse(obs, model)
        if segment(x, y) == e["truth_seg"]:
            good += 1
        if e.get("truth") is not None:
            errs.append(math.hypot(x - e["truth"][0], y - e["truth"][1]))
    return good, (sum(errs) / len(errs) if errs else 0.0)


class Learner:
    """Exemples (examples.jsonl) et modèle retenu (adjustments.json) dans le dossier de données."""

    def __init__(self, data_dir, fuse, segment):
        self.examples_file = os.path.join(data_dir, "examples.jsonl")
        self.model_file = os.path.join(data_dir, "adjustments.json")
        self.fuse, self.segment = fuse, segment
        self.lock = threading.Lock()
        self.examples = []
        try:
            with open(self.examples_file) as f:
                self.examples = [json.loads(line) for line in f if line.strip()][-MAX_EXAMPLES:]
        except (OSError, ValueError):
            pass
        self.model = Model()
        self.history = {}
        try:
            with open(self.model_file) as f:
                saved = json.load(f)
            self.model = Model(saved.get("model"))
            self.history = saved.get("last", {})
        except (OSError, ValueError, AttributeError):
            pass

    @staticmethod
    def _obs_json(obs):
        return [{"cam": o["cam"], "tip": [round(float(v), 2) for v in o["tip"]],
                 "dir": None if o.get("dir") is None else [round(float(v), 4) for v in o["dir"]]} for o in obs]

    def add(self, dart_id, obs, x, y):
        """Nouvelle fléchette détectée : exemple supposé juste tant qu'il n'est pas corrigé."""
        e = {"id": dart_id, "ts": int(time.time()), "obs": self._obs_json(obs), "fused": [round(x, 2), round(y, 2)],
             "truth": None, "truth_seg": self.segment(x, y), "corrected": False}
        with self.lock:
            self.examples.append(e)
            if len(self.examples) > MAX_EXAMPLES + 200:
                self.examples = self.examples[-MAX_EXAMPLES:]
                self._save_examples()
            else:
                # Ajout en fin de fichier : pas de réécriture à chaque fléchette (carte SD).
                with open(self.examples_file, "a") as f:
                    f.write(json.dumps(e, ensure_ascii=False) + "\n")

    def correct(self, dart_id, segment, x=None, y=None):
        """Correction du joueur : vrai segment, et vraie position s'il l'a touchée sur la cible."""
        with self.lock:
            e = next((e for e in reversed(self.examples) if e["id"] == dart_id), None)
            if e is None:
                return None
            e["truth_seg"] = segment
            e["truth"] = [float(x), float(y)] if x is not None and y is not None else None
            e["corrected"] = True
            self._save_examples()
            return self._refit()

    def reset(self):
        with self.lock:
            self.model = Model()
            self.history = {"reset": int(time.time())}
            self._save_model()

    def _refit(self):
        candidate = fit(self.examples)
        old = score(self.model, self.examples, self.fuse, self.segment)
        new = score(candidate, self.examples, self.fuse, self.segment)
        kept = new[0] > old[0] or (new[0] == old[0] and new[1] < old[1] - 0.2)
        if kept:
            self.model = candidate
        self.history = {"ts": int(time.time()), "kept": kept, "old_good": old[0], "new_good": new[0],
                        "old_err": round(old[1], 1), "new_err": round(new[1], 1), "examples": len(self.examples)}
        self._save_model()
        return self.history

    def stats(self):
        """Faits par caméra : corrections, écart médian à la vraie pointe, poids, zones ajustées."""
        with self.lock:
            corrected = [e for e in self.examples if e.get("truth") is not None]
            per = {}
            for e in corrected:
                for o in e["obs"]:
                    per.setdefault(o["cam"], []).append(lateral(o, e["truth"]))
            cams = {}
            for cam in set(per) | set(self.model.weights) | set(self.model.offsets):
                v = per.get(cam, [])
                med = float(np.median(v)) if v else None
                cams[cam] = {
                    "corrections": len(v),
                    "median_mm": round(med, 1) if med is not None else None,
                    "weight": round(self.model.weights.get(cam, 1.0), 2),
                    "zones": len(self.model.offsets.get(cam, {})),
                    "recalibrate": med is not None and len(v) >= MIN_SAMPLES and med > RECALIBRATE_MM,
                }
            return {"examples": len(self.examples), "corrected": sum(e["corrected"] for e in self.examples),
                    "with_position": len(corrected), "cams": cams, "model": self.model.to_json(),
                    "last": self.history}

    def _save_examples(self):
        tmp = self.examples_file + ".tmp"
        with open(tmp, "w") as f:
            for e in self.examples:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        os.replace(tmp, self.examples_file)

    def _save_model(self):
        tmp = self.model_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"model": self.model.to_json(), "last": self.history}, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.model_file)
