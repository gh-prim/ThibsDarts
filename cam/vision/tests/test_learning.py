"""Apprentissage des corrections : une caméra décalée est rattrapée, sans toucher à la calibration."""

import math
import os
import random
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "simulator"))
import detector  # noqa: E402
import learning  # noqa: E402
from dartlink import dart_at, segment_name  # noqa: E402


def seg(x, y):
    return segment_name(*dart_at(x, y))


def observe(truth, bias):
    """Ce que verraient les 3 caméras : pointe sur la vraie position (+ biais), axe vers la caméra."""
    obs = []
    for cam, d in detector.PRESET_DIRS.items():
        b = np.float64(bias.get(cam, (0, 0)))
        tip = np.float64(truth) + b + np.random.normal(0, 0.6, 2)
        # Erreur en profondeur le long de l'axe, typique d'une caméra rasante.
        tip = tip + np.float64(d) * np.random.normal(0, 4)
        obs.append({"cam": cam, "tip": tip, "dir": np.float64(d)})
    return obs


def test_bias_is_learned():
    random.seed(3)
    np.random.seed(3)
    bias = {"Haut droite": (4.0, 6.9)}  # caméra qui a un peu bougé (8 mm sur le côté de son axe)
    with tempfile.TemporaryDirectory() as tmp:
        lr = learning.Learner(tmp, detector.fuse, seg)
        # Fléchettes autour du T20 (zone 0), corrigées en touchant la vraie position.
        truths = [(random.uniform(-14, 14), random.uniform(-112, -94)) for _ in range(40)]
        all_obs = []
        for i, t in enumerate(truths):
            obs = observe(t, bias)
            all_obs.append(obs)
            x, y = detector.fuse(obs)
            lr.add(f"{i:08x}-0000", obs, x, y)

        def real(model):
            """Segments justes et erreur moyenne par rapport aux vraies positions."""
            pts = [detector.fuse(o, model) for o in all_obs]
            good = sum(seg(*p) == seg(*t) for p, t in zip(pts, truths))
            return good, float(np.mean([math.hypot(p[0] - t[0], p[1] - t[1]) for p, t in zip(pts, truths)]))

        before = real(None)
        # Comme un joueur : il corrige les fléchettes fausses, et en touche quelques autres sur la cible.
        for i, (t, obs) in enumerate(zip(truths, all_obs)):
            if i < 20 or seg(*detector.fuse(obs)) != seg(*t):
                lr.correct(f"{i:08x}-0000", seg(*t), *t)
        after = real(None if lr.model.empty else lr.model)
        stats = lr.stats()
        print("avant", before, "après", after, "modèle", stats["model"])
        assert "Haut droite" in lr.model.offsets
        assert after[0] >= before[0] and after[1] < before[1]
        # Rien n'a touché la calibration : seul adjustments.json existe en plus des exemples.
        assert sorted(os.listdir(tmp)) == ["adjustments.json", "examples.jsonl"]
        # Rechargé depuis le disque, le modèle est le même ; reset l'efface.
        lr2 = learning.Learner(tmp, detector.fuse, seg)
        assert lr2.model.to_json() == lr.model.to_json()
        lr2.reset()
        assert lr2.model.empty


def test_no_change_without_bias():
    np.random.seed(5)
    random.seed(5)
    with tempfile.TemporaryDirectory() as tmp:
        lr = learning.Learner(tmp, detector.fuse, seg)
        truths = [(random.uniform(-60, 60), random.uniform(-160, 160)) for _ in range(30)]
        for i, t in enumerate(truths):
            obs = observe(t, {})
            x, y = detector.fuse(obs)
            lr.add(f"{i:08x}-0000", obs, x, y)
            lr.correct(f"{i:08x}-0000", seg(*t), *t)
        assert all(math.hypot(*v[:2]) <= learning.MAX_OFFSET for zs in lr.model.offsets.values() for v in zs.values())


if __name__ == "__main__":
    test_bias_is_learned()
    test_no_change_without_bias()
    print("ok")
