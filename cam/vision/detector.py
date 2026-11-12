"""Détection des fléchettes avec les 3 caméras.

Calibration : pour chaque caméra, le propriétaire clique 5 points connus de la cible (le centre et
4 croisements du bord extérieur du double). On en tire l'homographie image -> cible (en mm) et une
pose approximative de la caméra (pour savoir de quel côté est la pointe d'une fléchette).

Détection : chaque caméra garde une image de fond. Quand quelque chose a bougé puis que tout est
de nouveau immobile, on compare chaque vue à son fond : une petite tache allongée est une fléchette.
Chaque caméra donne la pointe et la droite de la fléchette sur la cible ; les droites des
différentes caméras se croisent à la pointe (plus précis que la pointe vue par une seule caméra).
Une cible redevenue comme au début du tour : fléchettes retirées.
"""

import json
import math
import os
import time

import cv2
import numpy as np

# Rayon du bord extérieur du double, en mm (dartlink.R_DOUBLE_OUT) : il fixe l'échelle.
R_EDGE = 170.0
# Rayons officiels des bords des bandes. La cible de la maison peut différer : la calibration les mesure.
STANDARD_RINGS = {"double_in": 162.0, "triple_out": 107.0, "triple_in": 99.0}
RING_LABELS = [("double_out", "extérieur du double"), ("double_in", "intérieur du double"),
               ("triple_out", "extérieur du triple"), ("triple_in", "intérieur du triple")]
# Repères : les fils entre 20/1, 6/10, 3/19 et 11/14 (angle depuis le haut, sens horaire).
CALIB_ANGLES = [(9, "20 et 1"), (99, "6 et 10"), (189, "3 et 19"), (279, "11 et 14")]
# Points à cliquer, dans l'ordre : le centre et l'extérieur du double aux 4 repères (la cible se place),
# puis à chaque repère l'intérieur du double et les 2 bords du triple (l'épaisseur des bandes).
LEGACY_SPEC = [("center", 0)] + [("double_out", a) for a, _ in CALIB_ANGLES]
CALIB_SPEC = LEGACY_SPEC + [(key, a) for a, _ in CALIB_ANGLES for key, _ in RING_LABELS[1:]]
_LABELS, _WIRES = dict(RING_LABELS), dict(CALIB_ANGLES)
CALIB_HELP = ["centre (bull)"] + [f"{_LABELS[k]} entre {_WIRES[a]}" for k, a in CALIB_SPEC[1:]]


def spec_point(key, angle, rings):
    r = 0.0 if key == "center" else R_EDGE if key == "double_out" else rings[key]
    a = math.radians(angle)
    return (r * math.sin(a), -r * math.cos(a))


# Direction de chaque caméra vue du centre de la cible (x vers la droite, y vers le bas).
PRESET_DIRS = {
    "Bas": (0.0, 1.0),
    "Haut gauche": (-math.sqrt(3) / 2, -0.5),
    "Haut droite": (math.sqrt(3) / 2, -0.5),
}

SMALL = (320, 180)
DIFF_MIN = 28          # écart de gris pour dire qu'un pixel a changé
CHANGE_MIN = 0.0006    # part de l'image (petite) changée pour lancer une analyse
MOTION_MAX = 0.0008    # au-dessus : ça bouge encore
STABLE_TICKS = 3       # images immobiles avant l'analyse
BIG_CHANGE = 0.05      # main ou bras devant la caméra
EMPTY_MAX = 0.004      # cible "vide" : presque pareille qu'au début du tour
DART_MIN_AREA = 120    # pixels pleine résolution
DART_MAX_AREA = 40000
BOARD_LIMIT = 230.0    # au-delà, la tache n'est pas sur la cible (mm)


class Calibration:
    def __init__(self, points, size=(1280, 720)):
        self.points = [tuple(map(float, p)) for p in points]
        self.size = tuple(int(v) for v in size)
        spec = {len(CALIB_SPEC): CALIB_SPEC, len(LEGACY_SPEC): LEGACY_SPEC}.get(len(self.points))
        if spec is None:
            raise ValueError("nombre de points")
        self.spec = spec
        img = np.float32(self.points)
        # Homographie et rayons des bandes ajustés ensemble. D'abord le centre et l'extérieur du double
        # (rayon connu) ; on mesure chaque bande (moyenne des repères), puis on refait l'homographie avec
        # tous les points et ces rayons, quelques fois.
        self.rings = dict(STANDARD_RINGS)
        sure = np.array([k in ("center", "double_out") for k, _ in spec])
        for i in range(6):
            board = np.float32([spec_point(k, a, self.rings) for k, a in spec])
            use = sure if i == 0 else np.ones(len(spec), bool)
            self.H, _ = cv2.findHomography(img[use], board[use], 0)
            if self.H is None:
                raise ValueError("points de calibration incohérents")
            # Moyenne pondérée : un repère loin de la caméra (beaucoup de mm par pixel) compte moins.
            radii = {}
            for (key, _), p in zip(spec, self.points):
                mm_per_px = np.linalg.norm(self.to_board((p[0], p[1] + 1)) - self.to_board(p)) + 1e-6
                radii.setdefault(key, []).append((float(np.linalg.norm(self.to_board(p))), 1 / mm_per_px ** 2))
            mean = {k: sum(r * w for r, w in v) / sum(w for _, w in v) for k, v in radii.items()}
            scale = R_EDGE / mean["double_out"]
            for key in STANDARD_RINGS:
                if key in mean:
                    self.rings[key] = float(mean[key] * scale)
        for key, std in STANDARD_RINGS.items():
            if abs(self.rings[key] - std) > 25:
                raise ValueError(f"bande {key} mal placée")
        self.board = board
        self.Hinv = np.linalg.inv(self.H)
        w, h = self.size
        f = math.hypot(w, h) / 2 / math.tan(math.radians(50))  # objectif 100° en diagonale
        self.K = np.float64([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1]])
        obj = np.float64([(x, y, 0) for x, y in board])
        ok, rvec, tvec = cv2.solvePnP(obj, np.float64(img), self.K, None, flags=cv2.SOLVEPNP_IPPE)
        self.rvec, self.tvec = (rvec, tvec) if ok else (None, None)
        self.cam_pos = None
        if ok:
            R, _ = cv2.Rodrigues(rvec)
            self.cam_pos = (-R.T @ tvec).ravel()

    def ring_radii(self):
        return (6.35, 15.9, self.rings["triple_in"], self.rings["triple_out"], self.rings["double_in"], R_EDGE)

    def to_board(self, pt):
        p = self.H @ np.float64([pt[0], pt[1], 1.0])
        return p[:2] / p[2]

    def to_image(self, xy):
        p = self.Hinv @ np.float64([xy[0], xy[1], 1.0])
        return p[:2] / p[2]

    def normal_dir(self, img_pt):
        """Direction, dans l'image, d'une fléchette plantée en img_pt (de la pointe vers l'empennage)."""
        if self.rvec is None:
            return np.float64([0, -1])
        x, y = self.to_board(img_pt)
        side = 1.0 if self.cam_pos[2] > 0 else -1.0
        pts = np.float64([(x, y, 0), (x, y, 40 * side)])
        proj, _ = cv2.projectPoints(pts, self.rvec, self.tvec, self.K, None)
        d = proj[1, 0] - proj[0, 0]
        n = np.linalg.norm(d)
        return d / n if n > 1e-6 else np.float64([0, -1])

    def error(self):
        """Écart moyen (px) entre les points cliqués et la cible reprojetée."""
        return float(np.mean([np.linalg.norm(self.to_image(b) - np.float64(p))
                              for p, b in zip(self.points, self.board)]))

    def to_json(self):
        return {"points": [list(p) for p in self.points], "size": list(self.size),
                "rings": {k: round(v, 1) for k, v in self.rings.items()}}


class CalibStore:
    """Calibrations par nom de caméra ("Bas"...), dans <dossier>/calibration.json."""

    def __init__(self, data_dir):
        self.file = os.path.join(data_dir, "calibration.json")
        self.cals = {}
        try:
            with open(self.file) as f:
                for name, c in json.load(f).items():
                    try:
                        self.cals[name] = Calibration(c["points"], c.get("size", (1280, 720)))
                    except (KeyError, ValueError, TypeError):
                        pass
        except (OSError, ValueError, AttributeError):
            pass

    def get(self, name):
        return self.cals.get(name) if name else None

    def rings(self):
        """Rayons des bandes de la cible : moyenne des caméras qui les ont mesurés."""
        measured = [c.rings for c in self.cals.values() if c.spec is CALIB_SPEC]
        if not measured:
            return dict(STANDARD_RINGS)
        return {k: float(np.mean([m[k] for m in measured])) for k in STANDARD_RINGS}

    def set(self, name, cal):
        if cal is None:
            self.cals.pop(name, None)
        else:
            self.cals[name] = cal
        tmp = self.file + ".tmp"
        os.makedirs(os.path.dirname(self.file), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump({n: c.to_json() for n, c in self.cals.items()}, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.file)


def draw_board(img, cal, color=(0, 255, 255)):
    """Dessine les anneaux et les secteurs de la cible vus par la caméra (pour vérifier la calibration)."""
    sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
    for r in cal.ring_radii():
        pts = [cal.to_image((r * math.sin(t), -r * math.cos(t))) for t in np.linspace(0, 2 * math.pi, 120)]
        cv2.polylines(img, [np.int32(pts)], True, color, 1, cv2.LINE_AA)
    for i in range(20):
        a = math.radians(i * 18 + 9)
        p1 = cal.to_image((15.9 * math.sin(a), -15.9 * math.cos(a)))
        p2 = cal.to_image((170 * math.sin(a), -170 * math.cos(a)))
        cv2.line(img, tuple(np.int32(p1)), tuple(np.int32(p2)), color, 1, cv2.LINE_AA)
        a = math.radians(i * 18)
        t = cal.to_image((190 * math.sin(a), -190 * math.cos(a)))
        cv2.putText(img, str(sectors[i]), (int(t[0]) - 8, int(t[1]) + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                    color, 1, cv2.LINE_AA)
    for i, p in enumerate(cal.points):
        cv2.circle(img, (int(p[0]), int(p[1])), 5, (255, 0, 255), 2)
    return img


def small_gray(gray):
    return cv2.GaussianBlur(cv2.resize(gray, SMALL, interpolation=cv2.INTER_AREA), (5, 5), 0)


def changed(a, b, level=DIFF_MIN):
    return cv2.countNonZero(cv2.threshold(cv2.absdiff(a, b), level, 255, cv2.THRESH_BINARY)[1]) / a.size


def find_dart(bg, cur, cal):
    """Nouvelle fléchette entre deux images grises pleine résolution. None si rien de net."""
    d = cv2.absdiff(cv2.GaussianBlur(cur, (5, 5), 0), cv2.GaussianBlur(bg, (5, 5), 0))
    mask = cv2.threshold(d, DIFF_MIN, 255, cv2.THRESH_BINARY)[1]
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    best = None
    for i in range(1, n):
        area = stats[i, cv2.CC_STAT_AREA]
        if DART_MIN_AREA <= area <= DART_MAX_AREA and (best is None or area > stats[best, cv2.CC_STAT_AREA]):
            best = i
    if best is None:
        return None
    ys, xs = np.nonzero(labels == best)
    pts = np.float32(np.column_stack([xs, ys]))
    vx, vy, x0, y0 = cv2.fitLine(pts, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
    v, p0 = np.float64([vx, vy]), np.float64([x0, y0])
    # Le fût, fin, se coupe souvent en morceaux : on garde ceux qui sont dans l'axe de la fléchette.
    span = max(stats[best, cv2.CC_STAT_WIDTH], stats[best, cv2.CC_STAT_HEIGHT])
    keep = [best]
    for i in range(1, n):
        if i == best or stats[i, cv2.CC_STAT_AREA] < 15:
            continue
        c = np.float64(centroids[i]) - p0
        if abs(c[0] * v[1] - c[1] * v[0]) < 8 and abs(c @ v) < span * 3 + 60:
            keep.append(i)
    if len(keep) > 1:
        ys, xs = np.nonzero(np.isin(labels, keep))
        pts = np.float32(np.column_stack([xs, ys]))
        vx, vy, x0, y0 = cv2.fitLine(pts, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
        v, p0 = np.float64([vx, vy]), np.float64([x0, y0])
    proj = (pts - p0) @ v
    e1, e2 = p0 + v * proj.min(), p0 + v * proj.max()
    length = float(proj.max() - proj.min())
    if length < 12:
        return None
    # La pointe est le bout d'où part l'empennage (vers le joueur, donc vers la caméra).
    mid = (e1 + e2) / 2
    up = cal.normal_dir(mid)
    tip, tail = (e1, e2) if (e2 - e1) @ up > 0 else (e2, e1)
    tip_mm = cal.to_board(tip)
    if np.linalg.norm(tip_mm) > BOARD_LIMIT:
        return None
    step = (tail - tip) / max(np.linalg.norm(tail - tip), 1e-6) * min(25.0, length / 2)
    other = cal.to_board(tip + step)
    direction = other - tip_mm
    nd = np.linalg.norm(direction)
    return {
        "tip": tip_mm,
        "dir": direction / nd if nd > 1e-6 else None,
        "tip_img": tip,
        "area": int(stats[best, cv2.CC_STAT_AREA]),
        "length": length,
    }


def fuse(obs):
    """Position de la pointe (mm) à partir des observations de plusieurs caméras."""
    tips = np.float64([o["tip"] for o in obs])
    if len(obs) == 1:
        return tips[0]
    A, b = np.zeros((2, 2)), np.zeros(2)
    for o in obs:
        if o["dir"] is None:
            continue
        d = o["dir"].reshape(2, 1)
        P = np.eye(2) - d @ d.T
        A += P
        b += P @ o["tip"]
    # Un peu de poids aux pointes : évite l'instabilité si les droites sont presque parallèles.
    w = 0.05
    A += w * len(obs) * np.eye(2)
    b += w * tips.sum(axis=0)
    x = np.linalg.solve(A, b)
    if np.min(np.linalg.norm(tips - x, axis=1)) > 40:
        return np.median(tips, axis=0)
    return x


class Detector:
    """Machine à états des lancers. step() reçoit à chaque tour les images grises des caméras calibrées."""

    def __init__(self, on_dart, on_takeout, log=print):
        self.on_dart, self.on_takeout, self.log = on_dart, on_takeout, log
        self.reset()

    def reset(self):
        self.bg, self.bg_small, self.empty_small, self.prev = {}, {}, {}, {}
        self.darts = 0
        self.stable = 0
        self.quiet_since = time.monotonic()
        self.last = None

    def forget(self, name):
        for d in (self.bg, self.bg_small, self.empty_small, self.prev):
            d.pop(name, None)

    def step(self, frames, cals):
        """frames : {nom: image grise pleine résolution}, cals : {nom: Calibration}."""
        smalls = {n: small_gray(g) for n, g in frames.items()}
        for n in list(self.bg):
            if n not in frames:
                self.forget(n)
        new = [n for n in frames if n not in self.bg]
        for n in new:
            self.bg[n], self.bg_small[n], self.prev[n] = frames[n], smalls[n], smalls[n]
            if self.darts == 0:
                self.empty_small[n] = smalls[n]
        motion = max((changed(smalls[n], self.prev[n], 15) for n in frames if n not in new), default=0)
        for n in frames:
            self.prev[n] = smalls[n]
        if motion > MOTION_MAX:
            self.stable = 0
            return
        self.stable += 1
        if self.stable < STABLE_TICKS:
            return
        change = {n: changed(smalls[n], self.bg_small[n]) for n in frames}
        if max(change.values(), default=0) < CHANGE_MIN:
            # Rien de neuf : on suit doucement la lumière.
            if time.monotonic() - self.quiet_since > 5:
                self._rebase(frames, smalls, empty=self.darts == 0)
            return
        self.quiet_since = time.monotonic()
        # Cible redevenue comme au début du tour : fléchettes retirées.
        empty = max((changed(smalls[n], self.empty_small[n]) for n in frames if n in self.empty_small), default=1)
        if self.darts and empty < EMPTY_MAX and empty < 0.5 * max(change.values()):
            self.log(f"fléchettes retirées (écart {empty:.4f})")
            self.darts = 0
            self.on_takeout()
            self._rebase(frames, smalls, empty=True)
            return
        if max(change.values()) > BIG_CHANGE:
            # Main ou objet resté devant une caméra : on repart de cette image, sans rien compter.
            self.log(f"gros changement ignoré ({max(change.values()):.3f}, écart vide {empty:.4f})")
            self._rebase(frames, smalls, empty=self.darts == 0)
            return
        obs = []
        for n, g in frames.items():
            cal = cals.get(n)
            if cal is None or change[n] < CHANGE_MIN / 3:
                continue
            o = find_dart(self.bg[n], g, cal)
            if o:
                o["cam"] = n
                obs.append(o)
        self._rebase(frames, smalls, empty=self.darts == 0 and not obs)
        if not obs:
            self.log(f"changement sans fléchette ({', '.join(f'{n} {c:.4f}' for n, c in change.items())})")
            return
        x, y = fuse(obs)
        self.darts += 1
        self.last = {"x": float(x), "y": float(y), "cams": {o["cam"]: [round(float(v), 1) for v in o["tip"]]
                                                           for o in obs}, "ts": time.time()}
        self.on_dart(float(x), float(y), self.last)

    def _rebase(self, frames, smalls, empty=False):
        for n in frames:
            self.bg[n], self.bg_small[n] = frames[n], smalls[n]
            if empty:
                self.empty_small[n] = smalls[n]
        self.quiet_since = time.monotonic()
