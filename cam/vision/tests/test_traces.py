"""Coups fantômes : la trace signalée depuis le hub est gardée pour l'analyse."""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import traces  # noqa: E402


def test_keep_ghost():
    with tempfile.TemporaryDirectory() as tmp:
        store = traces.TraceStore(tmp, lambda x, y: "T20")
        tid = "0123abcd-0000-0000-0000-000000000000"
        d = os.path.join(store.dir, tid)
        os.makedirs(d)
        with open(os.path.join(d, "trace.json"), "w") as f:
            json.dump({"id": tid, "ts": 1, "x": 1.0, "y": -100.0, "segment": "T20",
                       "cams": {"Bas": {"seen": True, "segment": "T20"}, "Haut gauche": {"seen": False}}}, f)
        line = store.keep_ghost(tid, {"game": "501"})
        assert line["segment"] == "T20" and line["cams"] == {"Bas": "T20", "Haut gauche": None}
        assert os.path.exists(os.path.join(tmp, "fantomes", tid, "fantome.json"))
        with open(os.path.join(tmp, "fantomes.jsonl")) as f:
            assert json.loads(f.readline())["game"] == "501"
        assert store.keep_ghost("ffffffff-0000-0000-0000-000000000000", {}) is None
