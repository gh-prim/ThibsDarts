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
from concurrent.futures import ThreadPoolExecutor

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
# Immobilité jugée sur une durée, pas sur un nombre d'images : la même attente quelle que soit la cadence.
# Chaque image est comparée à la précédente (main, fléchette en vol) et à la première image calme
# (vibration lente d'une fléchette qui s'amortit, invisible d'une image à la suivante à 30 images/s).
CALM_S = int(os.environ.get("VISION_CALM_MS", "150")) / 1000
CALM_FRAMES = 2        # au moins ça d'images calmes, même si la durée est atteinte
# Décision anticipée : la pointe est plantée dès l'impact, seul l'empennage vibre (jusqu'à 0,8 s).
# On analyse chaque image pendant la vibration et on compte la fléchette dès que la position trouvée
# ne bouge plus sur EARLY_N images de suite (à EARLY_MM près). L'image calme sert ensuite de fond.
EARLY = os.environ.get("VISION_EARLY", "1") != "0"
EARLY_N = int(os.environ.get("VISION_EARLY_N", "3"))
EARLY_MM = float(os.environ.get("VISION_EARLY_MM", "3"))
EARLY_AFTER = 0.05     # s après le 1er mouvement : fléchette arrivée, plus en vol
EARLY_MOTION_MAX = 0.05  # au-dessus : une main, pas une fléchette qui vibre
SETTLE_MM = 25.0       # tache vue au calme à moins de ça de la fléchette comptée en avance : la même
BIG_CHANGE = 0.05      # main ou bras devant la caméra
EMPTY_MAX = 0.004      # cible "vide" : presque pareille qu'au début du tour
DART_MIN_AREA = 120    # pixels pleine résolution
PIECE_GAP = 60.0  # trou max (px) entre deux morceaux d'une même fléchette, le long de son axe
DART_MAX_AREA = 40000
BOARD_LIMIT = 300.0    # au-delà, la tache n'est pas sur la cible ni le surround (mm) : en deçà, une fléchette hors du double = MISS
SHADOWS = os.environ.get("VISION_SHADOWS", "1") != "0"  # retrait des ombres vues à plat par plusieurs caméras


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


def draw_board(img, cal, color=(0, 255, 255), points=True):
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
    for p in cal.points if points else ():
        cv2.circle(img, (int(p[0]), int(p[1])), 5, (255, 0, 255), 2)
    return img


def small_gray(gray):
    return cv2.GaussianBlur(cv2.resize(gray, SMALL, interpolation=cv2.INTER_AREA), (5, 5), 0)


def changed(a, b, level=DIFF_MIN):
    return cv2.countNonZero(cv2.threshold(cv2.absdiff(a, b), level, 255, cv2.THRESH_BINARY)[1]) / a.size


def changed_light(a, b, level=DIFF_MIN):
    """Comme changed, sans compter un changement de lumière d'ensemble (lampe allumée, soir qui tombe)."""
    shift = float(np.mean(a)) - float(np.mean(b))
    b2 = np.clip(b.astype(np.float32) + shift, 0, 255).astype(np.uint8)
    return changed(a, b2, level)


def match_light(ref, img):
    """img recalée sur la luminosité de ref (gain et décalage d'ensemble) : exposition de la caméra
    qui a bougé, ou éclairage du projecteur pas encore revenu. Une fléchette ou une main restent."""
    r, i = ref.astype(np.float32), img.astype(np.float32)
    si = float(i.std())
    a = float(r.std()) / si if si > 1 else 1.0
    a = min(1.6, max(0.6, a))
    return np.clip(a * (i - float(i.mean())) + float(r.mean()), 0, 255).astype(np.uint8)


def diff_mask(bg, cur):
    """Pixels changés entre deux images grises pleine résolution (255), nettoyés."""
    d = cv2.absdiff(cv2.GaussianBlur(cur, (5, 5), 0), cv2.GaussianBlur(bg, (5, 5), 0))
    mask = cv2.threshold(d, DIFF_MIN, 255, cv2.THRESH_BINARY)[1]
    return cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))


# Grille "vue de face" de la cible pour comparer les caméras : 1 px = 1 mm, centre au milieu.
PLANE_R = 240
PLANE_T = np.float64([[1, 0, PLANE_R], [0, 1, PLANE_R], [0, 0, 1]])
SHADOW_GROW_MM = 7  # tolérance de calibration entre caméras


def on_plane(masks, cals):
    """Ce qui a changé À PLAT sur la cible : vu au même endroit (en mm) par au moins 2 caméras.
    L'ombre d'une fléchette (vidéoprojecteur) est collée à la cible : toutes les caméras la voient au
    même endroit. La fléchette, elle, dépasse de la cible : chaque caméra la voit partir dans une
    direction différente, et seule sa pointe coïncide. Renvoie {caméra: masque image à retirer}."""
    names = [n for n in masks if n in cals]
    if len(names) < 2:
        return {}
    size = 2 * PLANE_R
    k = np.ones((SHADOW_GROW_MM, SHADOW_GROW_MM), np.uint8)
    warped = {}
    for n in names:
        M = PLANE_T @ cals[n].H
        warped[n] = cv2.dilate(cv2.warpPerspective(masks[n], M, (size, size), flags=cv2.INTER_NEAREST), k)
    count = sum((w > 0).astype(np.uint8) for w in warped.values())
    common = cv2.dilate(((count >= 2) * 255).astype(np.uint8), k)
    out = {}
    for n in names:
        h, w = masks[n].shape
        M = PLANE_T @ cals[n].H
        out[n] = cv2.warpPerspective(common, np.linalg.inv(M), (w, h), flags=cv2.INTER_NEAREST)
    return out


def find_dart(bg, cur, cal, why=None, remove=None):
    """Nouvelle fléchette entre deux images grises pleine résolution. None si rien de net.
    why : liste qui reçoit la raison du refus (montrée dans la trace).
    remove : masque des pixels à ignorer (ombre portée, vue à plat par plusieurs caméras)."""
    mask = diff_mask(bg, cur)
    full = None
    if remove is not None:
        full = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
        mask = cv2.bitwise_and(mask, cv2.bitwise_not(remove))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    areas = stats[:, cv2.CC_STAT_AREA]
    # Plusieurs taches possibles (fléchette, ombre, câble, reflet) : on essaie les plus grosses
    # et on garde la plus grosse fléchette plausible, pas juste la plus grosse tache.
    cands = sorted((i for i in range(1, n) if areas[i] >= DART_MIN_AREA // 3), key=lambda i: -areas[i])[:6]
    reasons, best = [], None
    for i in cands:
        r = _dart_from(i, n, labels, stats, centroids, cal, limit=BOARD_LIMIT + (60 if full is not None else 0))
        if full is not None and not isinstance(r, str):
            r = _extend_tip(r, full, cal)
        if isinstance(r, str):
            reasons.append(r)
        elif best is None or r["area"] > best["area"]:
            best = r
    if best is None and why is not None:
        why.append(reasons[0] if reasons else "aucune tache")
    return best


def _extend_tip(r, full, cal):
    """Après retrait de l'ombre, le bout du fût près de la pointe (vu au même endroit par toutes les
    caméras) a été retiré aussi : on reprend la pointe sur le masque complet, dans l'axe du fût.
    L'ombre part dans une autre direction : la marche s'arrête à la vraie pointe."""
    tip, tail = np.float64(r["tip_img"]), np.float64(r["tail_img"])
    v = tip - tail
    nv = np.linalg.norm(v)
    if nv < 1e-6:
        return r
    v /= nv
    perp = np.float64([-v[1], v[0]])
    h, w = full.shape
    last = tip
    miss = 0
    for k in range(1, 121):
        p = tip + v * k
        hit = False
        for off in (-2, -1, 0, 1, 2):
            x, y = (p + perp * off).round().astype(int)
            if 0 <= x < w and 0 <= y < h and full[y, x]:
                hit = True
                break
        if hit:
            last, miss = p, 0
        else:
            miss += 1
            if miss > 3:
                break
    tip_mm = cal.to_board(last)
    if np.linalg.norm(tip_mm) > BOARD_LIMIT:
        return "pointe hors cible"
    r = dict(r, tip_img=last, tip=tip_mm)
    step = (tail - last) / max(np.linalg.norm(tail - last), 1e-6) * min(25.0, r["length"] / 2)
    d = cal.to_board(last + step) - tip_mm
    nd = np.linalg.norm(d)
    r["dir"] = d / nd if nd > 1e-6 else r["dir"]
    return r


def _dart_from(main, n, labels, stats, centroids, cal, limit=BOARD_LIMIT):
    """Fléchette construite autour de la tache main, ou la raison du refus (texte)."""
    areas = stats[:, cv2.CC_STAT_AREA]
    c0 = np.float64(centroids[main])
    up = cal.normal_dir(c0)  # direction attendue pointe -> empennage dans l'image
    bx, by, bw, bh = stats[main, :4]
    ys, xs = np.nonzero(labels[by:by + bh, bx:bx + bw] == main)
    xs, ys = xs + bx, ys + by
    pts = np.float32(np.column_stack([xs, ys]))
    axis = up
    if len(pts) >= 5:
        ev, evec = np.linalg.eigh(np.cov(pts.T))
        v = evec[:, 1]
        # Tache allongée (fût) : son axe. Tache ronde (empennage seul) : la direction attendue.
        if ev[1] > 9 * max(ev[0], 1e-6) and abs(v @ up) > 0.5:
            axis = v if v @ up > 0 else -v
    # Le fût, fin, se coupe souvent en morceaux : on garde ceux qui sont dans l'axe de la fléchette.
    # Les morceaux doivent se suivre (trou de moins de PIECE_GAP px) : des petites taches de bruit
    # alignées par hasard de l'autre côté de la cible ne doivent pas rallonger la fléchette.
    keep = [main]
    proj_main = (pts - c0) @ axis
    lo, hi = float(proj_main.min()), float(proj_main.max())
    near_axis = []
    for i in range(1, n):
        if i == main or areas[i] < 15:
            continue
        c = np.float64(centroids[i]) - c0
        along = c @ axis
        if abs(c[0] * axis[1] - c[1] * axis[0]) < min(10 + 0.15 * abs(along), 40) and abs(along) < 450:
            # Étendue du morceau le long de l'axe, depuis sa boîte englobante.
            x, y, w, h = stats[i, :4]
            corners = np.float64([[x, y], [x + w, y], [x, y + h], [x + w, y + h]]) - c0
            pr = corners @ axis
            near_axis.append((i, float(pr.min()), float(pr.max())))
    grown = True
    while grown:
        grown = False
        for piece in list(near_axis):
            i, a, b = piece
            if a <= hi + PIECE_GAP and b >= lo - PIECE_GAP:
                keep.append(i)
                lo, hi = min(lo, a), max(hi, b)
                near_axis.remove(piece)
                grown = True
    area = int(areas[keep].sum())
    if area < DART_MIN_AREA:
        return "tache trop petite"
    if area > DART_MAX_AREA:
        return "tache trop grande"
    # Calculs restreints à la boîte qui englobe les morceaux gardés (bien plus petite que l'image).
    ks = stats[keep]
    ox, oy = int(ks[:, 0].min()), int(ks[:, 1].min())
    ex, ey = int((ks[:, 0] + ks[:, 2]).max()), int((ks[:, 1] + ks[:, 3]).max())
    sub = labels[oy:ey, ox:ex]
    lut = np.zeros(n, bool)
    lut[keep] = True
    sel_sub = lut[sub]
    ys, xs = np.nonzero(sel_sub)
    xs, ys = xs + ox, ys + oy
    pts = np.float32(np.column_stack([xs, ys]))
    if len(keep) > 1 and axis is up:
        # Empennage + morceaux de fût : l'axe passe par le centre de l'empennage et le fût.
        lut[main] = False
        oys, oxs = np.nonzero(lut[sub])
        others = np.float32(np.column_stack([oxs + ox, oys + oy]))
        fit_pts = np.vstack([others, np.repeat(np.float32([c0]), min(len(others), 200), axis=0)])
    else:
        fit_pts = pts
    vx, vy, x0, y0 = cv2.fitLine(fit_pts, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
    v, p0 = np.float64([vx, vy]), np.float64([x0, y0])
    if v @ up < 0:
        v = -v
    proj = (pts - p0) @ v
    length = float(proj.max() - proj.min())
    if length < 12:
        return "tache trop courte"
    # L'axe final vient du bout côté cible (fût et pointe) : l'empennage, gros et souvent vu de biais
    # ou mêlé à une autre fléchette, décale la droite de plusieurs mm.
    near = pts[proj <= proj.min() + max(30.0, 0.4 * length)]
    if len(near) >= 30:
        nv = cv2.fitLine(near, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
        v2 = np.float64(nv[:2])
        if abs(v2 @ v) > 0.8:
            v, p0 = (v2 if v2 @ up > 0 else -v2), np.float64(nv[2:])
            proj = (pts - p0) @ v
            length = float(proj.max() - proj.min())
    # La pointe est le bout opposé à l'empennage (qui part vers le joueur, donc vers la caméra).
    tip, tail = p0 + v * proj.min(), p0 + v * proj.max()
    tip_mm = cal.to_board(tip)
    if np.linalg.norm(tip_mm) > limit:
        return "pointe hors cible"
    step = (tail - tip) / max(np.linalg.norm(tail - tip), 1e-6) * min(25.0, length / 2)
    direction = cal.to_board(tip + step) - tip_mm
    nd = np.linalg.norm(direction)
    x0b, y0b = int(xs.min()), int(ys.min())
    x1b, y1b = int(xs.max()) + 1, int(ys.max()) + 1
    return {
        "tip": tip_mm,
        "dir": direction / nd if nd > 1e-6 else None,
        "tip_img": tip,
        "tail_img": tail,
        "area": area,
        "length": length,
        # Tache retenue (pour la trace) : boîte englobante et masque découpé.
        "bbox": (x0b, y0b, x1b - x0b, y1b - y0b),
        "mask": (sel_sub[y0b - oy:y1b - oy, x0b - ox:x1b - ox].astype(np.uint8) * 255),
    }


AGREE_MM = 40.0  # une caméra est d'accord si sa pointe est à moins de ça du point trouvé
OUTLIER_MM = 80.0  # pointe à plus de ça du point où les autres caméras concordent : caméra écartée
LINE_MM = 8.0  # ... ou si sa droite passe à moins de ça (une caméra est précise de côté, pas en profondeur)


def _intersect(obs):
    tips = np.float64([o["tip"] for o in obs])
    if len(obs) == 1:
        return tips[0]
    weights = [float(o.get("weight", 1.0)) for o in obs]

    def solve(tip_w):
        A, b = np.zeros((2, 2)), np.zeros(2)
        for o, wc in zip(obs, weights):
            if o.get("dir") is None:
                continue
            d = np.float64(o["dir"]).reshape(2, 1)
            P = (np.eye(2) - d @ d.T) * wc
            A += P
            b += P @ np.float64(o["tip"])
        # Un peu de poids aux pointes : évite l'instabilité si les droites sont presque parallèles.
        A += sum(tw * wc for tw, wc in zip(tip_w, weights)) * np.eye(2)
        b += sum(tw * wc * t for tw, wc, t in zip(tip_w, weights, tips))
        return np.linalg.solve(A, b)

    # D'abord les droites seules, puis le petit poids des pointes, mais seulement pour les pointes proches :
    # une pointe aberrante (caméra qui voit la fléchette hors cible) ne doit pas tirer le résultat.
    x = solve([1e-3] * len(obs))
    near = [0.05 if np.linalg.norm(t - x) <= AGREE_MM else 0.0 for t in tips]
    if not any(near):
        near = [0.05] * len(obs)
    return solve(near)


def _residual(x, o):
    """Distance (mm) entre x et l'observation : à sa droite si elle en a une, sinon à sa pointe."""
    t = np.float64(o["tip"])
    if o.get("dir") is None:
        return float(np.linalg.norm(t - x))
    d = np.float64(o["dir"])
    v = x - t
    return float(np.linalg.norm(v - (v @ d) * d))


def _agree(x, obs):
    """Toutes les caméras collent : droite à moins de LINE_MM, et au moins une pointe à moins de AGREE_MM."""
    if min(np.linalg.norm(np.float64(o["tip"]) - x) for o in obs) > AGREE_MM:
        return False
    return len(obs) == 1 or all(_residual(x, o) <= LINE_MM for o in obs)


def _drop_outlier(obs):
    """3 caméras ou plus : celle dont la pointe est très loin du point où les autres concordent
    (pointes à moins de AGREE_MM) est écartée, même si sa droite passe pas loin."""
    if len(obs) < 3:
        return obs
    best = None
    for out in obs:
        rest = [o for o in obs if o is not out]
        x = _intersect(rest)
        spread = max(np.linalg.norm(np.float64(o["tip"]) - x) for o in rest)
        far = np.linalg.norm(np.float64(out["tip"]) - x)
        if spread <= AGREE_MM and far > OUTLIER_MM and (best is None or spread < best[0]):
            best = (spread, rest)
    return best[1] if best else obs


def _pair_agrees(obs):
    """Au moins 2 caméras dont les droites et pointes concordent."""
    return len(obs) >= 2 and any(_agree(_intersect([a, b]), [a, b]) for i, a in enumerate(obs) for b in obs[i + 1:])


def fuse(obs, model=None):
    """Position de la pointe (mm) à partir des observations de plusieurs caméras.
    model : ajustements appris des corrections (learning.Model), ou None."""
    if model is not None:
        obs = model.apply(obs)
    obs = _drop_outlier(obs)
    x = _intersect(obs)
    if len(obs) == 1 or _agree(x, obs):
        return x
    # Caméras en désaccord, 3 caméras : si 2 sont d'accord, on écarte la troisième.
    if len(obs) >= 3:
        subs = [[o for o in obs if o is not out] for out in obs]
        sols = [(_intersect(s), s) for s in subs]
        ok = [(x2, s) for x2, s in sols if _agree(x2, s)]
        if ok:
            x2, s = min(ok, key=lambda e: max(_residual(e[0], o) for o in e[1]))
            return x2
    # Aucun accord net : l'intersection si une pointe la confirme, sinon la plus longue tache
    # (fléchette vue en entier) plutôt que de couper la poire en deux.
    if min(np.linalg.norm(np.float64(o["tip"]) - x) for o in obs) <= AGREE_MM:
        return x
    best = max(obs, key=lambda o: float(o.get("length", 0)) * float(o.get("weight", 1.0)))
    return np.float64(best["tip"])


_POOL = ThreadPoolExecutor(max_workers=3)


class Detector:
    """Machine à états des lancers. step() reçoit à chaque tour les images grises des caméras calibrées."""

    def __init__(self, on_dart, on_takeout, log=print):
        self.on_dart, self.on_takeout, self.log = on_dart, on_takeout, log
        self.model = None  # ajustements appris (learning.Model)
        self.reset()

    def reset(self):
        self.bg, self.bg_small, self.empty_small, self.prev = {}, {}, {}, {}
        self.darts = 0
        self.calm_ref = None  # (instant, petites images) du début de la période calme
        self.calm_frames = 0
        self.motion_at = None  # début du dernier mouvement : arrivée estimée de la fléchette
        self.prev_t = None
        self.first_motion, self.motion_log = None, []  # premier mouvement depuis la dernière décision (mesure)
        self.early_hist = []  # positions trouvées pendant la vibration
        self.settling = None  # position d'une fléchette comptée en avance, en attendant l'image calme
        self.quiet_since = time.monotonic()
        self.last = None
        self.turn_over = False
        self.placed = []  # fléchettes en place : zone de chaque caméra et son image d'avant la fléchette
        self.ctx = None

    def end_turn(self):
        """Le hub est passé au joueur suivant (bouton Fin de tour) : les fléchettes en place sont
        de l'ancien tour. Le prochain retrait ou la prochaine fléchette repart d'une cible vide."""
        if self.darts:
            self.turn_over = True

    def forget(self, name):
        for d in (self.bg, self.bg_small, self.empty_small, self.prev):
            d.pop(name, None)

    def step(self, frames, cals, now=None):
        """frames : {nom: image grise pleine résolution}, cals : {nom: Calibration}.
        now : instant des images (time.monotonic), maintenant par défaut."""
        now = time.monotonic() if now is None else now
        self.ctx = None  # images avant / après de la décision en cours (mode Debug)
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
        prev, prev_t = dict(self.prev), self.prev_t
        for n in frames:
            self.prev[n] = smalls[n]
        self.prev_t = now
        if self.first_motion is None and motion > MOTION_MAX:
            self.first_motion, self.motion_log = now, []
        if self.first_motion is not None and len(self.motion_log) < 90:
            self.motion_log.append((round((now - self.first_motion) * 1000), round(float(motion), 4)))
        if EARLY and self._early(frames, smalls, cals, now, motion):
            return
        if motion > MOTION_MAX:
            if self.calm_ref is not None or self.motion_at is None:
                self.motion_at = now
            self.calm_ref, self.calm_frames = None, 0
            return
        if self.calm_ref is None:
            # L'image d'avant est déjà pareille : le calme commence avec elle.
            self.calm_ref = (now if prev_t is None else prev_t, {n: prev.get(n, smalls[n]) for n in frames})
        else:
            t0, ref = self.calm_ref
            drift = max((changed(smalls[n], ref[n], 15) for n in frames if n in ref), default=0)
            if drift > MOTION_MAX:
                # Ça bouge encore, lentement : le calme repart d'ici.
                self.calm_ref, self.calm_frames = (now, dict(smalls)), 0
                return
        self.calm_frames += 1
        if self.calm_frames < CALM_FRAMES or now - self.calm_ref[0] < CALM_S:
            return
        first_motion, motion_log = self.first_motion, self.motion_log
        settling, self.settling = self.settling, None
        change = {n: changed(smalls[n], self.bg_small[n]) for n in frames}
        if max(change.values(), default=0) < CHANGE_MIN:
            # Rien de neuf : on suit doucement la lumière.
            if time.monotonic() - self.quiet_since > 5:
                self._rebase(frames, smalls, empty=self.darts == 0)
            return
        self.quiet_since = time.monotonic()
        self.ctx = {"frames": {n: (self.bg[n], frames[n]) for n in frames},
                    "change": {n: round(float(c), 4) for n, c in change.items()}}
        # Cible redevenue comme au début du tour : fléchettes retirées.
        empty = max((changed_light(smalls[n], self.empty_small[n]) for n in frames if n in self.empty_small),
                    default=1)
        if self.darts and empty < EMPTY_MAX and empty < 0.5 * max(change.values()):
            self._takeout(frames, smalls, f"écart {empty:.4f}")
            return
        if max(change.values()) > BIG_CHANGE:
            # Une caméra dont toute l'image a changé de luminosité (exposition, lumière du projecteur
            # pas encore revenue après une animation) n'est pas une main : on la recale sur le fond.
            for n in list(frames):
                if change[n] > BIG_CHANGE:
                    # Le fond est recalé sur l'image du moment (pas l'inverse) : le prochain fond reste une vraie image.
                    fixed = match_light(smalls[n], self.bg_small[n])
                    c2 = changed(smalls[n], fixed)
                    if c2 < BIG_CHANGE:
                        self.log(f"lumière recalée sur {n} ({change[n]:.3f} -> {c2:.3f})")
                        self.bg[n] = match_light(frames[n], self.bg[n])
                        self.bg_small[n] = fixed
                        change[n] = c2
            self.ctx["change"] = {n: round(float(c), 4) for n, c in change.items()}
            self.ctx["frames"] = {n: (self.bg[n], frames[n]) for n in frames}
        if max(change.values()) > BIG_CHANGE:
            if self.turn_over:
                # Tour fini à la main, puis main devant la cible : c'est le retrait.
                self._takeout(frames, smalls, "main après fin de tour")
                return
            # Main ou objet resté devant une caméra : on repart de cette image, sans rien compter.
            self.log(f"gros changement ignoré ({max(change.values()):.3f}, écart vide {empty:.4f})")
            self._rebase(frames, smalls, empty=self.darts == 0)
            return
        before = {n: self.bg[n] for n in frames}
        obs, why = self._observe(frames, cals, change)
        usable = sum(1 for n in frames if cals.get(n) is not None)
        if obs and usable >= 2:
            # Une vraie fléchette est vue par au moins 2 caméras qui concordent. Une seule caméra,
            # c'est presque toujours la lumière projetée (ombre de quelqu'un devant le projecteur,
            # reflet sur un logo imprimé) : on ne compte rien.
            if not _pair_agrees(obs):
                cams = ", ".join(o["cam"] for o in obs)
                self.log(f"tache ignorée ({'une seule caméra' if len(obs) < 2 else 'caméras en désaccord'} : {cams})")
                self._rebase(frames, smalls, empty=self.darts == 0)
                return
        if settling is not None:
            # Fléchette déjà comptée pendant sa vibration : on la revoit au calme, par rapport à l'image
            # d'avant elle. Même endroit : l'image calme devient le fond, rien de neuf.
            pos, pre = settling
            calm, _ = self._observe(frames, cals, {n: CHANGE_MIN for n in frames}, bg=pre)
            gap = np.linalg.norm(np.float64(fuse(calm)) - pos) if _pair_agrees(calm) else None
            # Une autre fléchette arrivée avant le calme (caméras en pause pendant l'animation de la
            # première, ou lancer très rapproché) : vue par rapport à l'image où la première a été
            # comptée, ailleurs qu'elle. Sans ce contrôle, le nouveau fond l'avalait sans la compter.
            other = (np.linalg.norm(np.float64(fuse(obs)) - pos) if obs and _pair_agrees(obs) else None)
            if (gap is None or gap < SETTLE_MM) and (other is None or other < SETTLE_MM):
                self.log("fléchette au calme : " + (f"{gap:.1f} mm de la position comptée" if gap is not None
                                                     else "pas revue"))
                self._rebase(frames, smalls)
                return
            if other is not None and other >= SETTLE_MM:
                self.log(f"fléchette au calme, et une autre arrivée entre-temps à {other:.0f} mm")
        gone = self._removed(frames) if obs else None
        if gone is not None:
            # Une fléchette en place a été retirée (sa zone est redevenue comme avant elle) : pas une nouvelle.
            self.placed.remove(gone)
            self.darts = max(0, self.darts - 1)
            if self.darts == 0:
                self._takeout(frames, smalls, "dernière fléchette retirée")
            else:
                self.log("fléchette retirée")
                self._rebase(frames, smalls)
            return
        if self.turn_over:
            if not obs:
                self._takeout(frames, smalls, "retrait après fin de tour")
                return
            # Fléchette du joueur suivant : la cible d'avant était donc déjà vide.
            self.log("nouveau tour : cible d'avant prise comme vide")
            self.turn_over = False
            self.darts = 0
            self.placed = []
            for n in frames:
                self.empty_small[n] = small_gray(before[n])
        self._rebase(frames, smalls, empty=self.darts == 0 and not obs)
        if not obs:
            self.log(f"changement sans fléchette ({', '.join(f'{n} {c:.4f}' for n, c in change.items())})")
            return
        self._commit(frames, obs, why, change, before, now, first_motion, motion_log)

    def _observe(self, frames, cals, change, bg=None):
        """Fléchette vue par chaque caméra (différence avec le fond), sans l'ombre portée."""
        bg = self.bg if bg is None else bg
        obs, why = [], {}
        # Ombre portée (vidéoprojecteur) : ce que plusieurs caméras voient au même endroit de la cible.
        masks = {n: diff_mask(bg[n], g) for n, g in frames.items()
                 if n in bg and cals.get(n) is not None and change[n] >= CHANGE_MIN / 3}
        try:
            flat = on_plane(masks, cals) if SHADOWS else {}
        except (cv2.error, np.linalg.LinAlgError):
            flat = {}
        todo = []
        for n, g in frames.items():
            cal = cals.get(n)
            if cal is None or n not in bg or change[n] < CHANGE_MIN / 3:
                if cal is not None:
                    why[n] = "changement trop faible"
                continue
            todo.append(n)

        def one(n):
            reasons = []
            return n, find_dart(bg[n], frames[n], cals[n], reasons, remove=flat.get(n)), reasons

        # Une caméra par cœur : OpenCV et numpy relâchent le verrou de Python.
        for n, o, reasons in _POOL.map(one, todo):
            if reasons:
                why[n] = reasons[0]
            if o:
                o["cam"] = n
                obs.append(o)
        return obs, why

    def _early(self, frames, smalls, cals, now, motion):
        """Pendant la vibration : compte la fléchette dès que sa position trouvée est stable. True si comptée."""
        if (self.first_motion is None or self.settling is not None or self.turn_over
                or now - self.first_motion < EARLY_AFTER or motion > EARLY_MOTION_MAX
                or sum(1 for n in frames if cals.get(n) is not None) < 2
                or any(n not in self.bg for n in frames)):
            return False
        change = {n: changed(smalls[n], self.bg_small[n]) for n in frames}
        if max(change.values()) < CHANGE_MIN or max(change.values()) > BIG_CHANGE:
            return False
        obs, why = self._observe(frames, cals, change)
        if not _pair_agrees(obs) or self._removed(frames) is not None:
            self.early_hist = []
            return False
        p = np.float64(fuse(obs))
        self.early_hist = (self.early_hist + [p])[-EARLY_N:]
        if len(self.early_hist) < EARLY_N:
            return False
        mid = np.mean(self.early_hist, axis=0)
        if max(np.linalg.norm(q - mid) for q in self.early_hist) > EARLY_MM:
            return False
        before = {n: self.bg[n] for n in frames}
        self.ctx = {"frames": {n: (self.bg[n], frames[n]) for n in frames},
                    "change": {n: round(float(c), 4) for n, c in change.items()}}
        first_motion, motion_log = self.first_motion, self.motion_log
        empty = self.darts == 0
        self._rebase(frames, smalls, empty=False)
        if empty:
            # Le fond « cible vide » reste celui d'avant la fléchette.
            for n in frames:
                self.empty_small[n] = small_gray(before[n])
        self.settling = (p, before)
        self.calm_ref, self.calm_frames = None, 0
        self._commit(frames, obs, why, change, before, now, first_motion, motion_log, early=True)
        return True

    def _commit(self, frames, obs, why, change, before, now, first_motion, motion_log, early=False):
        x, y = fuse(obs, self.model)
        raw = fuse(obs) if self.model is not None else (x, y)
        self.darts += 1
        crops = {}
        for o in obs:
            g = before[o["cam"]]
            bx, by, bw, bh = o["bbox"]
            x0, y0 = max(bx - 10, 0), max(by - 10, 0)
            x1, y1 = min(bx + bw + 10, g.shape[1]), min(by + bh + 10, g.shape[0])
            crops[o["cam"]] = ((x0, y0, x1, y1), g[y0:y1, x0:x1].copy())
        self.placed.append(crops)
        delay = None if first_motion is None else round((now - first_motion) * 1000)
        if first_motion is not None:
            moves = [m for _, m in motion_log]
            bursts = sum(1 for a, b in zip(moves, moves[1:]) if a <= MOTION_MAX < b) + (moves[:1] > [MOTION_MAX])
            self.log(f"mesure : {delay} ms depuis le 1er mouvement ({'en vibration' if early else 'au calme'}), "
                     f"{bursts} reprises, mouvements {' '.join(f'{t}:{m}' for t, m in motion_log)}")
        self.last = {"x": float(x), "y": float(y), "cams": {o["cam"]: [round(float(v), 1) for v in o["tip"]]
                                                           for o in obs}, "ts": time.time(), "delay_ms": delay}
        # Tout ce qu'il faut pour la trace : images avant / après, ce que chaque caméra a vu.
        info = dict(self.last, raw=[float(raw[0]), float(raw[1])], obs=obs, change=change, why=why,
                    frames={n: (before[n], frames[n]) for n in frames})
        self.on_dart(float(x), float(y), info)

    def _removed(self, frames):
        """Fléchette en place dont la zone ressemble de nouveau à l'image d'avant elle, ou None."""
        for p in reversed(self.placed):
            votes = []
            for n, ((x0, y0, x1, y1), pre) in p.items():
                if n not in frames or n not in self.bg:
                    continue
                cur = frames[n][y0:y1, x0:x1].astype(np.int16)
                d_pre = float(np.mean(np.abs(cur - pre)))
                d_bg = float(np.mean(np.abs(cur - self.bg[n][y0:y1, x0:x1])))
                votes.append(d_pre < 0.5 * d_bg)
            if votes and sum(votes) * 2 > len(votes):
                return p
        return None

    def _takeout(self, frames, smalls, why):
        self.log(f"fléchettes retirées ({why})")
        self.settling = None
        self.placed = []
        self.darts = 0
        self.turn_over = False
        self.on_takeout()
        self._rebase(frames, smalls, empty=True)

    def _rebase(self, frames, smalls, empty=False):
        self.first_motion, self.motion_log, self.early_hist = None, [], []
        for n in frames:
            self.bg[n], self.bg_small[n] = frames[n], smalls[n]
            if empty:
                self.empty_small[n] = smalls[n]
        self.quiet_since = time.monotonic()
