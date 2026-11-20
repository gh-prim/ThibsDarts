"""Calibration guidée du vidéoprojecteur, pilotée depuis l'app iOS (Profil > Projecteur).

Même méthode que la page /calib : un point de la cible à la fois, le projecteur dessine le morceau
de fils autour du point, on le fait glisser (pavé tactile de l'iPhone) jusqu'aux vrais fils, on valide.
Homographie aux moindres carrés sur les points de la cible ; les anneaux (double, triple, bord de
cible, surround) donnent leur rayon réel par l'homographie inverse.

L'état vit ici (un seul calibrage à la fois) ; l'iPhone envoie des actions et lit l'état.
"""

import math
import threading

DOUT = 170.0
CAL = [(0.0, DOUT), (DOUT, 0.0), (0.0, -DOUT), (-DOUT, 0.0)]
ORDER = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
NOM = {"dIn": 162.0, "tOut": 107.0, "tIn": 99.0, "board": 225.5, "sur": 380.0}
RING_TXT = {
    "dIn": ("Double, fil intérieur", "Bord intérieur de la bande des doubles"),
    "tOut": ("Triple, fil extérieur", "Bord extérieur de la bande des triples"),
    "tIn": ("Triple, fil intérieur", "Bord intérieur de la bande des triples"),
    "board": ("Bord de la cible", "Limite entre la cible noire et le surround gris"),
    "sur": ("Bord du surround", "Bord extérieur du surround gris"),
}
DEF_PROJ = {"x": -700.0, "y": -530.0, "z": 1550.0}


def _targets():
    out = []
    for i in (0, 5, 10, 15, 2, 7, 12, 17):
        a = math.radians(i * 18 + 9)
        n0, n1 = ORDER[i], ORDER[(i + 1) % 20]
        out.append({"id": f"{n0}-{n1}", "ring": None, "mm": (math.sin(a) * DOUT, math.cos(a) * DOUT),
                    "where": f"Entre le {n0} et le {n1}", "hint": "Superpose les traits cyan au double et au fil de séparation"})
    out.append({"id": "bull", "ring": None, "mm": (0.0, 0.0), "where": "Centre du bull", "hint": "Superpose les deux cercles cyan au bull"})
    for ring, nums in (("dIn", (20, 3)), ("tOut", (6, 11)), ("tIn", (20, 3)), ("board", (20, 6, 3, 11)), ("sur", (20, 6, 3, 11))):
        for n in nums:
            a = math.radians(ORDER.index(n) * 18)
            out.append({"id": f"{ring}-{n}", "ring": ring, "mm": (math.sin(a) * NOM[ring], math.cos(a) * NOM[ring]),
                        "where": f"{RING_TXT[ring][0]}, face au {n}", "hint": RING_TXT[ring][1]})
    return out


TARGETS = _targets()
BY_ID = {t["id"]: t for t in TARGETS}


def fit(src, dst):
    """Homographie src -> dst aux moindres carrés (4 points ou plus), coordonnées normalisées."""
    n = len(src)
    mx = sum(p[0] for p in dst) / n
    my = sum(p[1] for p in dst) / n
    sd = math.sqrt(sum((p[0] - mx) ** 2 + (p[1] - my) ** 2 for p in dst) / n) or 1.0
    sd = 1.0 / sd
    ms = sum(abs(c) for p in src for c in p) / (2 * n) or 1.0
    sx = 1.0 / ms
    M = [[0.0] * 9 for _ in range(8)]
    for (X, Y), (U, V) in zip(src, dst):
        x, y, u, v = X * sx, Y * sx, (U - mx) * sd, (V - my) * sd
        for r in ((x, y, 1, 0, 0, 0, -u * x, -u * y, u), (0, 0, 0, x, y, 1, -v * x, -v * y, v)):
            for a in range(8):
                for b in range(9):
                    M[a][b] += r[a] * r[b]
    for c in range(8):
        p = max(range(c, 8), key=lambda r: abs(M[r][c]))
        M[c], M[p] = M[p], M[c]
        for r in range(8):
            if r != c and M[c][c]:
                f = M[r][c] / M[c][c]
                for k in range(c, 9):
                    M[r][k] -= f * M[c][k]
    h = [M[i][8] / M[i][i] if M[i][i] else 0.0 for i in range(8)]

    def apply(X, Y):
        x, y = X * sx, Y * sx
        w = h[6] * x + h[7] * y + 1
        return ((h[0] * x + h[1] * y + h[2]) / w / sd + mx, (h[3] * x + h[4] * y + h[5]) / w / sd + my)
    return apply


class Guide:
    def __init__(self, hub, load, save):
        self.hub, self.load, self.save = hub, load, save
        self.lock = threading.Lock()
        self.tab = "frame"
        self.cur = 0
        self.ptr = [640.0, 360.0]
        self.pairs = {}
        self.skipped = set()
        self.base = None
        self.proj = dict(DEF_PROJ)
        self.loaded = False
        self.shape = []

    # ---------- modèle ----------
    def _screen(self):
        return self.hub.screen

    def _def_points(self):
        W, H = self._screen()
        s = 514 / 451
        return [(W / 2 + x * s, H / 2 - y * s) for x, y in CAL]

    def _fixed(self):
        return [i for i in self.pairs if not BY_ID[i]["ring"]]

    def _model(self):
        ids = self._fixed()
        if len(ids) >= 4:
            return fit([self.pairs[i]["mm"] for i in ids], [self.pairs[i]["px"] for i in ids])
        return fit(CAL, self.base or self._def_points())

    def _rings(self):
        ids = self._fixed()
        if len(ids) < 4:
            return {}
        inv = fit([(p[0] / 4, p[1] / 4) for p in (self.pairs[i]["px"] for i in ids)], [self.pairs[i]["mm"] for i in ids])
        acc = {}
        for i, p in self.pairs.items():
            r = BY_ID[i]["ring"]
            if r:
                x, y = inv(p["px"][0] / 4, p["px"][1] / 4)
                acc.setdefault(r, []).append(math.hypot(x, y))
        return {k: round(sum(v) / len(v), 1) for k, v in acc.items()}

    def _shape(self, t):
        m = self._model()
        o = m(*t["mm"])
        ang = math.atan2(t["mm"][0], t["mm"][1])
        D = math.pi / 180

        def line(r0, r1, a):
            return [(math.sin(a) * r, math.cos(a) * r) for r in (r0, r1)]

        def arc(r, a0, a1):
            return [(math.sin(a0 + (a1 - a0) * k / 24) * r, math.cos(a0 + (a1 - a0) * k / 24) * r) for k in range(25)]
        if t["id"] == "bull":
            polys = [arc(6.35, 0, 2 * math.pi), arc(15.9, 0, 2 * math.pi)]
        elif not t["ring"]:
            polys = [line(100, 172, ang), arc(170, ang - 14 * D, ang + 14 * D), arc(162, ang - 14 * D, ang + 14 * D)]
        else:
            r = math.hypot(*t["mm"])
            w = (22 if r > 200 else 14) * D
            polys = [arc(r, ang - w, ang + w)]
            if r < 172:
                polys += [line(r - 18, r + 18, ang - 9 * D), line(r - 18, r + 18, ang + 9 * D)]
        out = []
        for pl in polys:
            pts = []
            for q in pl:
                x, y = m(*q)
                pts.append([round(x - o[0], 1), round(y - o[1], 1)])
            out.append(pts)
        return out

    # ---------- projecteur ----------
    def _pointer(self):
        if self.tab == "frame":
            self.hub.send("pointer", {"grid": True}, keep=True)
        elif self.tab == "points":
            t = TARGETS[self.cur]
            done = [list(p["px"]) for i, p in self.pairs.items() if i != t["id"]]
            self.hub.send("pointer", {"x": self.ptr[0], "y": self.ptr[1], "shape": self.shape, "done": done}, keep=True)
        else:
            self.hub.send("pointer", {"off": True}, keep=True)

    def _store(self, pattern):
        m = self._model()
        points = [list(m(*p)) for p in CAL]
        data = {"points": points, "pattern": bool(pattern), "projector": self.proj,
                "pairs": [{"id": i, "mm": list(p["mm"]), "px": list(p["px"])} for i, p in self.pairs.items()],
                "rings": self._rings()}
        self.base = [tuple(p) for p in points]
        self.save(dict(data, pattern=False))
        self.hub.send("calib", data, keep=True)

    def _goto(self, i):
        self.cur = max(0, min(len(TARGETS) - 1, i))
        t = TARGETS[self.cur]
        self.ptr = list(self.pairs[t["id"]]["px"]) if t["id"] in self.pairs else list(self._model()(*t["mm"]))
        self.shape = self._shape(t)

    def _ensure(self):
        if self.loaded:
            return
        self.loaded = True
        d = self.load() or {}
        if d.get("points"):
            self.base = [tuple(p) for p in d["points"]]
        if isinstance(d.get("projector"), dict):
            self.proj = d["projector"]
        for p in d.get("pairs") or []:
            if p.get("id") in BY_ID:
                self.pairs[p["id"]] = {"mm": tuple(BY_ID[p["id"]]["mm"]), "px": tuple(p["px"])}
        first = next((i for i, t in enumerate(TARGETS) if t["id"] not in self.pairs), 0)
        self._goto(first)

    # ---------- API ----------
    def state(self):
        with self.lock:
            self._ensure()
            return self._state()

    def _state(self):
        t = TARGETS[self.cur]
        ids = self._fixed()
        err = None
        if len(ids) >= 5:
            m = self._model()
            e = [math.hypot(m(*self.pairs[i]["mm"])[0] - self.pairs[i]["px"][0], m(*self.pairs[i]["mm"])[1] - self.pairs[i]["px"][1]) for i in ids]
            err = {"mean": round(sum(e) / len(e), 1), "max": round(max(e), 1)}
        return {
            "tab": self.tab, "index": self.cur, "count": len(TARGETS), "ptr": [round(v, 1) for v in self.ptr],
            "target": {"id": t["id"], "where": t["where"], "hint": t["hint"], "mm": list(t["mm"]), "ring": t["ring"]},
            "done": list(self.pairs), "skipped": sorted(self.skipped), "fixed": len(ids),
            "status": ["done" if t["id"] in self.pairs else "skip" if t["id"] in self.skipped else "" for t in TARGETS],
            "error": err, "rings": {RING_TXT[k][0]: v for k, v in self._rings().items()},
        }

    def action(self, b):
        with self.lock:
            self._ensure()
            a = b.get("action")
            msg = None
            if a == "tab" and b.get("tab") in ("frame", "points", "check"):
                self.tab = b["tab"]
                if self.tab == "points":
                    self._goto(self.cur)
                if self.tab == "check":
                    self._store(True)
            elif a == "move":
                W, H = self._screen()
                dx, dy = float(b.get("dx", 0)), float(b.get("dy", 0))
                self.ptr = [max(0.0, min(W, self.ptr[0] + dx)), max(0.0, min(H, self.ptr[1] + dy))]
            elif a == "goto":
                self._goto(int(b.get("index", 0)))
            elif a == "ok":
                t = TARGETS[self.cur]
                W, H = self._screen()
                if t["ring"] and len(self._fixed()) < 4:
                    msg = "4 points de la cible avant les anneaux"
                elif not (0.5 < self.ptr[0] < W - 0.5 and 0.5 < self.ptr[1] < H - 0.5):
                    msg = "Point hors de l'image : passe-le"
                else:
                    self.pairs[t["id"]] = {"mm": tuple(t["mm"]), "px": tuple(self.ptr)}
                    self.skipped.discard(t["id"])
                    msg = self._next()
            elif a == "skip":
                t = TARGETS[self.cur]
                self.pairs.pop(t["id"], None)
                self.skipped.add(t["id"])
                msg = self._next()
            elif a == "redo":
                self.pairs, self.skipped = {}, set()
                self.tab = "points"
                self._goto(0)
            elif a == "reset":
                self.pairs, self.skipped = {}, set()
                self.base, self.proj = None, dict(DEF_PROJ)
                self._store(self.tab == "check")
                self._goto(0)
            elif a == "leave":
                self.tab = "check"
                self.hub.send("pointer", {"off": True}, keep=True)
                return self._state()
            self._pointer()
            st = self._state()
            if msg:
                st["message"] = msg
            return st

    def _next(self):
        if len(self._fixed()) >= 4:
            self._store(False)
        todo = next((i for i, t in enumerate(TARGETS) if i > self.cur and t["id"] not in self.pairs and t["id"] not in self.skipped), None)
        if todo is not None:
            self._goto(todo)
            return None
        if len(self._fixed()) >= 4:
            self.tab = "check"
            self._store(True)
            return None
        self._goto(next((i for i, t in enumerate(TARGETS) if t["id"] not in self.pairs), 0))
        return "4 points minimum"
