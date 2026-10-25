"""clientdb.py - The client's own tables for Tools/gen_landmarks.py: loading the
newest saved wago.tools exports (References/Forever/db, fetched with the
wago-tools skill) and converting between world and UI map coordinates.

World coordinates: x points north, y points west (the client's). A UI map
position is (x, y) in 0..1 from the top-left. UiMapAssignment gives, for each
UI map, the world rectangle (Region min/max) of one continent (MapID) that it
shows between UiMin and UiMax.
"""
import csv
import glob
import math
import os
import re

DB = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "References", "Forever", "db"))


def _build(path):
    return tuple(int(x) for x in re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1).split("."))


def table(name, build=None):
    """Rows of a saved table (newest build, or `build`), as dicts."""
    if build:
        path = os.path.join(DB, "forever-%s-%s.csv" % (name.lower(), build))
    else:
        files = glob.glob(os.path.join(DB, "forever-%s-*.csv" % name.lower()))
        if not files:
            raise SystemExit("no %s export in %s: python References/Tools/Wago/wago.py get %s" % (name, DB, name))
        path = max(files, key=_build)
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def build_of(name):
    files = glob.glob(os.path.join(DB, "forever-%s-*.csv" % name.lower()))
    return ".".join(str(x) for x in _build(max(files, key=_build)))


class Maps:
    """UI maps and their world rectangles."""

    def __init__(self, build=None):
        self.maps = {int(r["ID"]): r for r in table("UiMap", build)}
        self.assign = []
        for r in table("UiMapAssignment", build):
            a = {k: float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1",
                                          "Region_0", "Region_1", "Region_3", "Region_4")}
            a.update(uimap=int(r["UiMapID"]), continent=int(r["MapID"]), area=int(r["AreaID"]),
                     order=int(r["OrderIndex"]))
            self.assign.append(a)

    def name(self, uimap):
        m = self.maps.get(uimap)
        return m["Name_lang"] if m else None

    def kind(self, uimap):
        m = self.maps.get(uimap)
        return int(m["Type"]) if m else None

    def area_of(self, uimap):
        """The AreaTable ID of a UI map's first assignment (Wowhead's zone ID)."""
        rows = sorted((a for a in self.assign if a["uimap"] == uimap), key=lambda a: a["order"])
        return rows[0]["area"] if rows else None

    def _rect(self, uimap):
        rows = [a for a in self.assign if a["uimap"] == uimap]
        return min(rows, key=lambda a: a["order"]) if rows else None

    def to_world(self, uimap, x, y):
        """A UI map position (0..1) to (continent, world x, world y), or None."""
        a = self._rect(uimap)
        if not a:
            return None
        fx = (x - a["UiMin_0"]) / (a["UiMax_0"] - a["UiMin_0"])
        fy = (y - a["UiMin_1"]) / (a["UiMax_1"] - a["UiMin_1"])
        wy = a["Region_4"] - fx * (a["Region_4"] - a["Region_1"])   # map x grows west -> east: world y falls
        wx = a["Region_3"] - fy * (a["Region_3"] - a["Region_0"])   # map y grows north -> south: world x falls
        return a["continent"], wx, wy

    def to_map(self, uimap, continent, wx, wy):
        """A world position to (x, y) on `uimap`, or None when that map doesn't show it."""
        a = self._rect(uimap)
        if not a or a["continent"] != continent:
            return None
        fx = (a["Region_4"] - wy) / (a["Region_4"] - a["Region_1"])
        fy = (a["Region_3"] - wx) / (a["Region_3"] - a["Region_0"])
        return a["UiMin_0"] + fx * (a["UiMax_0"] - a["UiMin_0"]), a["UiMin_1"] + fy * (a["UiMax_1"] - a["UiMin_1"])

    def zone_at(self, continent, wx, wy):
        """The smallest zone (UI map type 3) whose rectangle holds the point, with its (x, y)."""
        best = None
        for a in self.assign:
            if a["continent"] != continent or self.kind(a["uimap"]) != 3:
                continue
            if not (a["Region_0"] <= wx <= a["Region_3"] and a["Region_1"] <= wy <= a["Region_4"]):
                continue
            size = (a["Region_3"] - a["Region_0"]) * (a["Region_4"] - a["Region_1"])
            if best is None or size < best[0]:
                best = (size, a["uimap"])
        if not best:
            return None
        pos = self.to_map(best[1], continent, wx, wy)
        return best[1], pos[0], pos[1]


def yards(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])
