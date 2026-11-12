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
    for (x, y) in darts:
        p, _ = cv2.projectPoints(np.float64([(x, y, 0), (x, y, -60), (x, y, -110)]), rvec, t, K, None)
        p = p.reshape(-1, 2)
        cv2.line(img, tuple(np.int32(p[0])), tuple(np.int32(p[1])), (200, 120, 0), 4, cv2.LINE_AA)
        cv2.line(img, tuple(np.int32(p[1])), tuple(np.int32(p[2])), (0, 200, 255), 9, cv2.LINE_AA)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.int16)
    gray += np.random.normal(0, 4, gray.shape).astype(np.int16)  # bruit du capteur
    return np.clip(gray, 0, 255).astype(np.uint8)


def calib_for(R, t):
    rvec, _ = cv2.Rodrigues(R)
    pts, _ = cv2.projectPoints(np.float64([(x, y, 0) for x, y in detector.CALIB_POINTS_MM]), rvec, t, K, None)
    return detector.Calibration(pts.reshape(-1, 2) + np.random.normal(0, 1.0, (5, 2)), (W, H))


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


if __name__ == "__main__":
    test_three_cameras()
    print("ok")
