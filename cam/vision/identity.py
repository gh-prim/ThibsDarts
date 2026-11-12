"""Reconnaître une caméra à ce qu'elle voit.

Les 3 caméras sont identiques jusqu'au numéro de série : rien dans le matériel ne les distingue.
Quand le propriétaire nomme une caméra ("Bas"), on garde une image de référence de sa vue.
Ensuite chaque caméra branchée est comparée aux références (points ORB + homographie) et
reçoit le nom de celle qui lui ressemble le plus, quel que soit le port USB.
Ça ne marche bien qu'avec des caméras fixées autour de la cible.
"""

import itertools
import json
import os
import re

import cv2
import numpy as np

# Nombre minimal de points cohérents pour dire qu'une vue correspond à une référence.
MIN_SCORE = 25

_orb = cv2.ORB_create(1000)
_matcher = cv2.BFMatcher(cv2.NORM_HAMMING)


def features(gray):
    return _orb.detectAndCompute(gray, None)


def score(a, b):
    """Points qui se correspondent entre deux vues, après une homographie RANSAC."""
    (ka, da), (kb, db) = a, b
    if da is None or db is None or len(da) < 10 or len(db) < 10:
        return 0
    good = [m for m, n in (p for p in _matcher.knnMatch(da, db, k=2) if len(p) == 2) if m.distance < 0.75 * n.distance]
    if len(good) < 8:
        return 0
    src = np.float32([ka[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([kb[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    _, mask = cv2.findHomography(src, dst, cv2.RANSAC, 5.0)
    return int(mask.sum()) if mask is not None else 0


def assign(views, refs):
    """views : {id caméra: features}, refs : {nom: features}. Rend {id: (nom ou None, score)}.

    Essaie toutes les répartitions (au plus 3 caméras) et garde celle qui a le meilleur total,
    chaque nom n'allant qu'à une caméra.
    """
    ids, names = list(views), list(refs)
    scores = {(i, n): score(views[i], refs[n]) for i in ids for n in names}
    best, best_total = {i: (None, 0) for i in ids}, -1
    slots = names + [None] * len(ids)
    for perm in set(itertools.permutations(slots, len(ids))):
        pick = {}
        for i, n in zip(ids, perm):
            s = scores.get((i, n), 0) if n else 0
            pick[i] = (n, s) if n and s >= MIN_SCORE else (None, s if n else 0)
        total = sum(s for n, s in pick.values() if n)
        if total > best_total:
            best, best_total = pick, total
    return best


class RefStore:
    """Images de référence nommées, dans <dossier>/cameras/ et cameras.json."""

    def __init__(self, data_dir):
        self.dir = os.path.join(data_dir, "cameras")
        self.file = os.path.join(data_dir, "cameras.json")
        self.refs = {}
        try:
            with open(self.file) as f:
                saved = json.load(f).get("refs", {})
        except (OSError, ValueError, AttributeError):
            saved = {}
        for name, png in saved.items():
            gray = cv2.imread(os.path.join(self.dir, png), cv2.IMREAD_GRAYSCALE)
            if gray is not None:
                self.refs[name] = (png, features(gray))

    @property
    def names(self):
        return list(self.refs)

    def features(self):
        return {n: f for n, (_, f) in self.refs.items()}

    def set(self, name, gray):
        os.makedirs(self.dir, exist_ok=True)
        png = "ref-" + (re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "camera") + ".png"
        cv2.imwrite(os.path.join(self.dir, png), gray)
        self.refs[name] = (png, features(gray))
        self._save()

    def remove(self, name):
        if self.refs.pop(name, None):
            self._save()

    def _save(self):
        tmp = self.file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"refs": {n: png for n, (png, _) in self.refs.items()}}, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.file)
