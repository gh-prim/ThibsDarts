"""Test sans caméra : cible et fléchettes synthétiques vues par 3 caméras virtuelles.
Lancer : python3 -m pytest cam/vision/tests  (ou python3 cam/vision/tests/test_detector.py)"""

import math
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "simulator"))
import detector  # noqa: E402
from dartlink import SECTORS, dart_at, segment_name  # noqa: E402

# Les tests enchaînent les images sans attendre : immobilité jugée sur le nombre d'images seulement.
detector.CALM_S = 0.0

W, H = 1280, 720
F = math.hypot(W, H) / 2 / math.tan(math.radians(50))
K = np.float64([[F, 0, W / 2], [0, F, H / 2], [0, 0, 1]])
S = 2.0  # px/mm de la texture


def board_texture():
    size = int(460 * S)
    img = np.full((size, size, 3), 40, np.uint8)
    c = size / 2
    yy, xx = np.mgrid[0:size, 0:size]
    x, y = (xx - c) / S, (yy - c) / S
    r = np.hypot(x, y)
    a = (np.degrees(np.arctan2(x, -y)) + 9) % 360 // 18
    dark = (a % 2 == 0)
    img[(r <= 170)] = (230, 230, 230)
    img[(r <= 170) & dark] = (20, 20, 20)
    ring = ((r >= 99) & (r <= 107)) | ((r >= 162) & (r <= 170))
    img[ring & dark] = (40, 40, 200)
    img[ring & ~dark] = (40, 160, 40)
    img[r <= 15.9] = (40, 160, 40)
    img[r <= 6.35] = (40, 40, 200)
    return img


def pose(direction, dist=300, height=-90):
    # Repère de la cible : x à droite, y en bas, donc z vers le mur ; le joueur est en z < 0.
    dx, dy = direction
    C = np.float64([dx * dist, dy * dist, height])
    target = np.float64([0, 0, 0])
    z = target - C
    z /= np.linalg.norm(z)
    up_world = np.float64([0, 0, np.sign(height)])  # vers le joueur : en haut de l'image
    x = np.cross(z, -up_world)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    R = np.vstack([-x, -y, z])
    t = -R @ C
    return R, t


def render(R, t, tex, darts=()):
    # Homographie texture -> image : point texture (u, v) -> plan (x, y, 0).
    Hp = K @ np.column_stack([R[:, 0], R[:, 1], t])
    c = tex.shape[0] / 2
    T = np.float64([[1 / S, 0, -c / S], [0, 1 / S, -c / S], [0, 0, 1]])
    img = cv2.warpPerspective(tex, Hp @ T, (W, H), borderValue=(90, 90, 90))
    # Pixels dont le rayon ne touche pas le plan devant la caméra : le mur au loin.
    yy, xx = np.mgrid[0:H, 0:W]
    rays = R.T @ np.linalg.inv(K) @ np.vstack([xx.ravel(), yy.ravel(), np.ones(W * H)])
    cz = (-R.T @ t)[2]
    img[(rays[2] * cz >= 0).reshape(H, W)] = (70, 70, 70)
    rvec, _ = cv2.Rodrigues(R)
    for d in darts:
        # (x, y) : fléchette droite ; (x, y, dx, dy) : arrière décalé de (dx, dy) mm (vibration).
        x, y = d[:2]
        dx, dy = d[2:] if len(d) == 4 else (0, 0)
        p, _ = cv2.projectPoints(np.float64([(x, y, 0), (x + dx * 60 / 110, y + dy * 60 / 110, -60),
                                             (x + dx, y + dy, -110)]), rvec, t, K, None)
        p = p.reshape(-1, 2)
        cv2.line(img, tuple(np.int32(p[0])), tuple(np.int32(p[1])), (200, 120, 0), 4, cv2.LINE_AA)
        cv2.line(img, tuple(np.int32(p[1])), tuple(np.int32(p[2])), (0, 200, 255), 9, cv2.LINE_AA)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.int16)
    gray += np.random.normal(0, 4, gray.shape).astype(np.int16)  # bruit du capteur
    return np.clip(gray, 0, 255).astype(np.uint8)


def calib_for(R, t):
    rvec, _ = cv2.Rodrigues(R)
    board = [detector.spec_point(k, a, detector.STANDARD_RINGS) for k, a in detector.CALIB_SPEC]
    pts, _ = cv2.projectPoints(np.float64([(x, y, 0) for x, y in board]), rvec, t, K, None)
    return detector.Calibration(pts.reshape(-1, 2) + np.random.normal(0, 1.0, (len(board), 2)), (W, H))


def test_three_cameras():
    np.random.seed(1)
    tex = board_texture()
    cams = {n: pose(d) for n, d in detector.PRESET_DIRS.items()}
    cals = {n: calib_for(R, t) for n, (R, t) in cams.items()}
    got, takeouts = [], []
    det = detector.Detector(lambda x, y, info: got.append((x, y)), lambda: takeouts.append(1), log=print)
    targets = [(0, -103), (40, 60), (-120, 20)]
    thrown = []

    def frames():
        return {n: render(R, t, tex, thrown) for n, (R, t) in cams.items()}

    for _ in range(4):
        det.step(frames(), cals)
    for tgt in targets:
        thrown.append(tgt)
        for _ in range(4):
            det.step(frames(), cals)
    errs = [math.hypot(g[0] - t[0], g[1] - t[1]) for g, t in zip(got, targets)]
    for g, t in zip(got, targets):
        print("visé", t, segment_name(*dart_at(*t)), "trouvé", [round(v, 1) for v in g], segment_name(*dart_at(*g)))
    assert len(got) == 3, got
    assert max(errs) < 6, errs
    # Main devant puis fléchettes retirées.
    blank = {n: np.full((H, W), 128, np.uint8) for n in cams}
    det.step(blank, cals)
    thrown.clear()
    for _ in range(4):
        det.step(frames(), cals)
    assert takeouts == [1]


def shade(img, p):
    v = int(img[int(p[1]) % H, int(p[0]) % W])
    return v + 60 if v < 128 else v - 60


def test_flight_and_broken_shaft():
    """Empennage gros et rond, fût pâle et coupé, plus une tache parasite hors cible plus grosse."""
    np.random.seed(3)
    tex = board_texture()
    for name, d in detector.PRESET_DIRS.items():
        R, t = pose(d)
        cal = calib_for(R, t)
        rvec, _ = cv2.Rodrigues(R)
        for tgt in [(10, -60), (45, -25), (-80, 70)]:
            bg = render(R, t, tex)
            cur = bg.copy()
            p, _ = cv2.projectPoints(np.float64([(*tgt, 0), (*tgt, -70), (*tgt, -110)]), rvec, t, K, None)
            p = p.reshape(-1, 2)
            # Fût en pointillés, juste au-dessus du seuil.
            for k in range(0, 10, 2):
                a, b = p[0] + (p[1] - p[0]) * k / 10, p[0] + (p[1] - p[0]) * (k + 1) / 10
                cv2.line(cur, tuple(np.int32(a)), tuple(np.int32(b)), shade(bg, a), 3)
            # Empennage : disque autour du haut.
            cv2.circle(cur, tuple(np.int32((p[1] + p[2]) / 2)), 28, 255, -1)
            # Parasite (câble, reflet) hors de la cible, plus gros que la fléchette.
            cv2.rectangle(cur, (20, 20), (130, 140), 255, -1)
            o = detector.find_dart(bg, cur, cal)
            assert o is not None, (name, tgt)
            err = float(np.linalg.norm(o["tip"] - np.float64(tgt)))
            assert err < 8, (name, tgt, [round(float(v), 1) for v in o["tip"]], err)


def test_aligned_noise_beyond_tip():
    """Cas réel : petites taches de bruit dans l'axe, de l'autre côté de la cible. La pointe reste sur la fléchette."""
    np.random.seed(5)
    tex = board_texture()
    for name, d in detector.PRESET_DIRS.items():
        R, t = pose(d)
        cal = calib_for(R, t)
        rvec, _ = cv2.Rodrigues(R)
        for tgt in [(10, -120), (-60, -100)]:
            bg = render(R, t, tex)
            cur = bg.copy()
            p, _ = cv2.projectPoints(np.float64([(*tgt, 0), (*tgt, -70), (*tgt, -110)]), rvec, t, K, None)
            p = p.reshape(-1, 2)
            cv2.line(cur, tuple(np.int32(p[0])), tuple(np.int32(p[1])), shade(bg, p[0]), 4)
            cv2.line(cur, tuple(np.int32(p[1])), tuple(np.int32(p[2])), 255, 9)
            # Taches de bruit tous les 90 px dans le prolongement, côté pointe, jusqu'au bord de la cible.
            u = (p[0] - p[2]) / np.linalg.norm(p[0] - p[2])
            for k in range(1, 6):
                q = p[0] + u * 90 * k
                cv2.circle(cur, tuple(np.int32(q)), 4, shade(bg, q), -1)
            o = detector.find_dart(bg, cur, cal)
            assert o is not None, (name, tgt)
            err = float(np.linalg.norm(o["tip"] - np.float64(tgt)))
            assert err < 8, (name, tgt, [round(float(v), 1) for v in o["tip"]], err)


def test_flight_off_axis():
    """Empennage décalé sur le côté (vu de biais, ou mêlé à une fléchette voisine) : l'axe suit le fût."""
    np.random.seed(11)
    tex = board_texture()
    lat = []
    for name, d in detector.PRESET_DIRS.items():
        R, t = pose(d)
        cal = calib_for(R, t)
        rvec, _ = cv2.Rodrigues(R)
        for tgt in [(0, -45), (30, -90), (-60, 20)]:
            bg = render(R, t, tex)
            cur = bg.copy()
            p, _ = cv2.projectPoints(np.float64([(*tgt, 0), (*tgt, -45), (*tgt, -70), (*tgt, -110)]), rvec, t, K, None)
            p = p.reshape(-1, 2)
            cv2.line(cur, tuple(np.int32(p[0])), tuple(np.int32(p[1])), shade(bg, p[0]), 5)
            cv2.line(cur, tuple(np.int32(p[1])), tuple(np.int32(p[2])), 255, 4)
            c = (p[2] + p[3]) / 2 + np.float64([22, 0])
            cv2.ellipse(cur, tuple(np.int32(c)), (30, 22), 0, 0, 360, 255, -1)
            o = detector.find_dart(bg, cur, cal)
            v, dd = np.float64(tgt) - o["tip"], o["dir"]
            lat.append(abs(v[0] * dd[1] - v[1] * dd[0]))
    assert max(lat) < 1.5, [round(float(x), 1) for x in lat]


def test_fuse_outlier_camera():
    # Cas réel S4 : Haut gauche et Haut droite d'accord à 2 mm, Bas voit la fléchette hors cible.
    def o(cam, tip, d):
        d = np.float64(d)
        return {"cam": cam, "tip": np.float64(tip), "dir": d / np.linalg.norm(d), "length": 100}
    obs = [o("Bas", [21.3, 218.8], [30, -150]), o("Haut gauche", [58.1, -35.7], [305, 115]),
           o("Haut droite", [60.2, -35.1], [325, -90])]
    x = detector.fuse(obs)
    assert np.linalg.norm(x - np.float64([59.6, -35.0])) < 1.5, x
    assert dart_at(*x) == (4, 1), dart_at(*x)


def test_fuse_disagreement():
    # Haut gauche voit toute la fléchette ; Haut droite n'a que l'empennage, pointe loin.
    good = {"cam": "Haut gauche", "tip": np.float64([44.8, -24.2]), "dir": np.float64([0.0, 1.0]), "length": 249}
    bad = {"cam": "Haut droite", "tip": np.float64([-131.8, 95.8]), "dir": np.float64([1.0, 0.0]), "length": 88}
    x = detector.fuse([good, bad])
    assert np.linalg.norm(x - good["tip"]) < 1, x
    # Trois caméras dont une fausse : on garde les deux d'accord.
    t = np.float64([40, -30])
    a = {"cam": "a", "tip": t + [3, 4], "dir": np.float64([0.6, 0.8]), "length": 200}
    b = {"cam": "b", "tip": t + [-4, 3], "dir": np.float64([-0.8, 0.6]), "length": 200}
    x = detector.fuse([a, b, bad])
    assert np.linalg.norm(x - t) < 3, x


def test_takeout_light_and_manual_end():
    np.random.seed(5)
    tex = board_texture()
    cams = {n: pose(d) for n, d in detector.PRESET_DIRS.items()}
    cals = {n: calib_for(R, t) for n, (R, t) in cams.items()}
    got, takeouts = [], []
    det = detector.Detector(lambda x, y, info: got.append((x, y)), lambda: takeouts.append(1), log=print)
    thrown, light = [], [0]

    def frames():
        return {n: np.clip(render(R, t, tex, thrown).astype(np.int16) + light[0], 0, 255).astype(np.uint8)
                for n, (R, t) in cams.items()}

    def settle():
        for _ in range(4):
            det.step(frames(), cals)

    settle()
    thrown.append((30, -80))
    settle()
    assert len(got) == 1
    # Lampe allumée pendant qu'on retire : le retrait est quand même vu.
    thrown.clear()
    light[0] = 25
    settle()
    assert takeouts == [1] and det.darts == 0, (takeouts, det.darts)
    # Retrait sans main, référence vide faussée : vu quand même (la zone redevient comme avant).
    thrown.append((-50, 40))
    settle()
    det.empty_small = {n: np.zeros_like(v) for n, v in det.empty_small.items()}
    thrown.clear()
    settle()
    assert det.darts == 0 and takeouts == [1, 1] and len(got) == 2, (det.darts, takeouts, got)
    # Compteur resté bloqué (retrait raté), Fin de tour à la main, puis joueur suivant : on repart à 1.
    det.darts, det.placed = 2, []
    det.end_turn()
    thrown.append((60, 60))
    settle()
    assert det.darts == 1 and not det.turn_over, (det.darts, det.turn_over)
    thrown.clear()
    settle()
    assert det.darts == 0 and takeouts == [1, 1, 1], (det.darts, takeouts)
    # Fin de tour à la main fléchette en place, puis retrait : retrait.
    thrown.append((-20, -20))
    settle()
    det.end_turn()
    det.empty_small = {n: np.zeros_like(v) for n, v in det.empty_small.items()}
    thrown.clear()
    settle()
    assert det.darts == 0 and not det.turn_over, (det.darts, det.turn_over)


if __name__ == "__main__":
    test_three_cameras()
    test_flight_and_broken_shaft()
    test_flight_off_axis()
    test_aligned_noise_beyond_tip()
    test_fuse_disagreement()
    test_fuse_outlier_camera()
    test_takeout_light_and_manual_end()
    print("ok")


def test_ring_points():
    """Les bords des bandes cliqués aux 4 repères mesurent l'épaisseur des bandes d'une cible non officielle."""
    np.random.seed(2)
    R, t = pose(detector.PRESET_DIRS["Haut gauche"])
    rvec, _ = cv2.Rodrigues(R)
    real = {"double_in": 160.0, "triple_out": 108.5, "triple_in": 97.0}
    board = [detector.spec_point(k, a, real) for k, a in detector.CALIB_SPEC]
    pts, _ = cv2.projectPoints(np.float64([(x, y, 0) for x, y in board]), rvec, t, K, None)
    cal = detector.Calibration(pts.reshape(-1, 2) + np.random.normal(0, 0.7, (len(board), 2)), (W, H))
    # Ancien format à 5 points toujours accepté.
    legacy = [detector.spec_point(k, a, real) for k, a in detector.LEGACY_SPEC]
    lp, _ = cv2.projectPoints(np.float64([(x, y, 0) for x, y in legacy]), rvec, t, K, None)
    assert detector.Calibration(lp.reshape(-1, 2), (W, H)).rings == detector.STANDARD_RINGS
    for k, r in real.items():
        assert abs(cal.rings[k] - r) < 1.5, (k, cal.rings[k])
    assert dart_at(0, -98, cal.rings) == (20, 3)  # simple sur une cible officielle, triple ici


if __name__ == "__main__":
    test_ring_points()
    print("bandes ok")


def test_calm_is_a_duration():
    """À 30 images/s : la fléchette est comptée après CALM_S de calme, et un lent mouvement
    (invisible d'une image à la suivante) repousse la décision."""
    cams = {n: pose(d) for n, d in detector.PRESET_DIRS.items()}
    cals = {n: calib_for(R, t) for n, (R, t) in cams.items()}
    got = []
    det = detector.Detector(lambda x, y, info: got.append(info), lambda: None, log=print)
    tex = board_texture()
    thrown, light = [], [0]
    base = {}

    def frames():
        if not base or tuple(thrown) not in base:
            base[tuple(thrown)] = {n: render(R, t, tex, thrown) for n, (R, t) in cams.items()}
        return {n: np.clip(g.astype(np.int16) + light[0], 0, 255).astype(np.uint8)
                for n, g in base[tuple(thrown)].items()}

    saved, saved_early, dt, now = detector.CALM_S, detector.EARLY, 1 / 30, 0.0
    detector.CALM_S, detector.EARLY = 0.15, False
    try:
        for _ in range(10):
            det.step(frames(), cals, now)
            now += dt
        thrown.append((40, 60))
        steps = 0
        while not got and steps < 30:
            det.step(frames(), cals, now)
            now += dt
            steps += 1
        assert got, "pas détectée"
        # 1 image de mouvement, puis 0,15 s de calme : 5 à 6 images, pas 1 ou 2.
        assert 5 <= steps <= 7, steps
        assert got[0]["delay_ms"] is not None and 140 <= got[0]["delay_ms"] <= 220, got[0]["delay_ms"]

        # Deuxième fléchette, puis lent changement de 4 niveaux de gris par image (15 = seuil).
        thrown.append((-120, 20))
        det.step(frames(), cals, now)
        now += dt
        for i in range(12):
            light[0] += 4
            det.step(frames(), cals, now)
            now += dt
        assert len(got) == 1, "comptée pendant que l'image bougeait encore"
    finally:
        detector.CALM_S, detector.EARLY = saved, saved_early


def test_early_while_vibrating():
    """L'arrière de la fléchette vibre 0,7 s : elle est comptée pendant la vibration, au bon endroit,
    une seule fois ; la suivante est comptée aussi."""
    np.random.seed(3)
    cams = {n: pose(d) for n, d in detector.PRESET_DIRS.items()}
    cals = {n: calib_for(R, t) for n, (R, t) in cams.items()}
    got, logs = [], []
    det = detector.Detector(lambda x, y, info: got.append((x, y, info)), lambda: None, log=logs.append)
    tex = board_texture()
    thrown = []

    def frames():
        return {n: render(R, t, tex, thrown) for n, (R, t) in cams.items()}

    saved, dt, now = detector.CALM_S, 1 / 30, 0.0
    detector.CALM_S = 0.15
    try:
        for _ in range(8):
            det.step(frames(), cals, now)
            now += dt
        for tgt in [(40, 60), (-90, -30)]:
            thrown.append(tgt)
            first = len(got)
            counted_at = None
            for i in range(40):
                amp = 12 * math.exp(-i / 8) if i < 21 else 0  # vibration amortie, environ 0,7 s
                thrown[-1] = (tgt[0], tgt[1], amp * (1 if i % 2 else -1), 0.0) if amp else tgt
                det.step(frames(), cals, now)
                now += dt
                if counted_at is None and len(got) > first:
                    counted_at = i
            assert len(got) == first + 1, ([g[:2] for g in got], logs[-6:])
            assert counted_at is not None and counted_at <= 10, counted_at
            x, y, info = got[-1]
            assert math.hypot(x - tgt[0], y - tgt[1]) < 6, (x, y)
            thrown[-1] = tgt
        assert any("au calme" in m or "fléchette au calme" in m for m in logs), logs
    finally:
        detector.CALM_S = saved
