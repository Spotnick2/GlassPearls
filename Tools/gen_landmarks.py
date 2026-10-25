"""gen_landmarks.py - Write Data/Landmarks.lua (the map landmarks pearl's data,
#10) and Tools/landmarks/report.txt (the evidence, for review and day one).

Positions are the game's facts. Where the client has them they come from its
own tables (References/Forever/db, the wago-tools skill):
- transport docks: the transport taxi paths' stops (TaxiPathNode rows with a
  Delay: the boat or zeppelin waits there), named by Tools/landmarks/transports.csv;
- the Deeprun Tram: its two portal triggers (AreaTrigger), Tools/landmarks/tram.csv.
Dungeon and raid entrances aren't in the client (no Encounter Journal tables):
Tools/landmarks/entrances.csv holds each door's zone position, converted to
world coordinates with UiMapAssignment, and the report gives the distance to
the nearest client trigger as evidence (never a gate: a cave mouth can be far
from its portal).
Level ranges: Wowhead's Forever zone tooltips ("Level a-b"), read from the
shared cache only (References/Tools/Wowhead/wowhead.py ... --offline): the
fetch is a separate, deliberate step (see CLAUDE.md, the wowhead-forever skill).

Usage (from the repo root):  python Tools/gen_landmarks.py
"""
import csv
import json
import math
import os
import re
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "landmarks"))
import clientdb as db  # noqa: E402

SRC = os.path.join(HERE, "landmarks")
OUT = os.path.join(HERE, "..", "Data", "Landmarks.lua")
REPORT = os.path.join(SRC, "report.txt")
WOWHEAD = os.path.normpath(os.path.join(HERE, "..", "..", "References", "Tools", "Wowhead", "wowhead.py"))
MERGE_YARDS = 30          # two stops this close are one pier
CLIENT_YARDS = 40         # an entrance this close to a client trigger: "client"
NEAR_YARDS = 200          # within this: "near"; farther: "hand" (review by sight on day one)
# Cities: Wowhead gives them 1-60, which says nothing.
CITIES = {1453, 1454, 1455, 1456, 1457, 1458}


def rows(name):
    with open(os.path.join(SRC, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def zone_levels(ids):
    """{ areaID: (min, max) } from Wowhead's cached zone tooltips."""
    if not ids:
        return {}
    listfile = os.path.join(SRC, ".zoneids.tmp")
    with open(listfile, "w") as f:
        f.write("\n".join(str(i) for i in sorted(ids)) + "\n")
    try:
        out = subprocess.run([sys.executable, "-I", WOWHEAD, "get", "zone", "--ids-file", listfile, "--offline"],
                             capture_output=True, text=True, check=False).stdout
    finally:
        os.remove(listfile)
    levels = {}
    for r in json.loads(out).get("results", []):
        text = " ".join((r.get("fields") or {}).get("text") or [])
        m = re.search(r"Level (\d+)(?:\s*-\s*(\d+))?", text)
        if m:
            lo = int(m.group(1))
            levels[int(r["id"])] = (lo, int(m.group(2) or lo))
    return levels


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    maps = db.Maps()
    build = db.build_of("UiMap")
    report = ["Map landmarks evidence, client build %s" % build, ""]
    triggers = defaultdict(list)
    trig_by_id = {}
    for r in db.table("AreaTrigger"):
        t = (int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"]), int(r["ID"]))
        triggers[t[0]].append(t)
        trig_by_id[t[3]] = t

    # Entrances, grouped by door.
    ent_rows = rows("entrances.csv")
    levels = zone_levels({int(r["area"]) for r in ent_rows if r["area"]}
                         | {maps.area_of(u) for u in maps.maps if maps.kind(u) == 3 and maps.area_of(u)})
    doors = {}
    order = []
    for r in ent_rows:
        zone, x, y = int(r["zone"]), float(r["x"]) / 100, float(r["y"]) / 100
        if maps.kind(zone) != 3:
            raise SystemExit("%s: zone %d isn't a zone map" % (r["name"], zone))
        if not (0 < x < 1 and 0 < y < 1):
            raise SystemExit("%s: position off the map" % r["name"])
        w = maps.to_world(zone, x, y)
        key = r["door"] or ("lfg" + r["lfg"])
        if key not in doors:
            near = min(triggers[w[0]], key=lambda t: math.hypot(t[1] - w[1], t[2] - w[2]), default=None)
            dist = math.hypot(near[1] - w[1], near[2] - w[2]) if near else float("inf")
            conf = "client" if dist <= CLIENT_YARDS else ("near" if dist <= NEAR_YARDS else "hand")
            doors[key] = {"key": key, "c": w[0], "x": w[1], "y": w[2], "zone": zone, "list": [],
                          "trigger": near[3] if near else None, "dist": dist, "conf": conf}
            order.append(key)
        # Wowhead's range; else the CSV's fallback (a minimum alone shows as "28+").
        lv, src = (levels.get(int(r["area"])) if r["area"] else None), "wowhead"
        if not lv and r.get("min"):
            lv, src = (int(r["min"]), int(r["max"]) if r.get("max") else None), "csv"
        doors[key]["list"].append({"lfg": int(r["lfg"]), "name": r["name"], "kind": r["kind"], "levels": lv,
                                   "levels_from": src if lv else None})
    report.append("Entrances (door: nearest client trigger, confidence)")
    for key in order:
        d = doors[key]
        def lvtext(e):
            if not e["levels"]:
                return "(no levels)"
            lo, hi = e["levels"]
            return ("%d-%d" % (lo, hi) if hi else "%d+" % lo) + ("" if e["levels_from"] == "wowhead" else " [csv]")
        names = ", ".join("%s %s" % (e["name"], lvtext(e)) for e in d["list"])
        report.append("  %-8s %-20s %5.0f yd (trigger %s) %-6s  %s" % (
            key, maps.name(d["zone"]), d["dist"], d["trigger"], d["conf"], names))

    # Transports: the transport taxi paths' stops.
    names = {(int(r["path"]), int(r["stop"])): r for r in rows("transports.csv")}
    wanted = {p for p, _ in names}
    stops = defaultdict(list)
    for r in db.table("TaxiPathNode"):
        pid = int(r["PathID"])
        if pid in wanted and r["Delay"] not in ("", "0"):
            stops[pid].append((int(r["NodeIndex"]), int(r["ContinentID"]), float(r["Loc_0"]), float(r["Loc_1"])))
    docks = []   # { c, x, y, name, kind, sides, routes }

    def dock_for(c, x, y, info):
        for d in docks:
            if d["c"] == c and math.hypot(d["x"] - x, d["y"] - y) <= MERGE_YARDS:
                if d["name"] != info["dock"]:
                    raise SystemExit("one pier, two names: %s / %s" % (d["name"], info["dock"]))
                return d
        d = {"c": c, "x": x, "y": y, "name": info["dock"], "kind": info["kind"], "sides": info["sides"], "routes": []}
        docks.append(d)
        return d

    for pid in sorted(stops):
        seq = []
        for _, c, x, y in sorted(stops[pid]):
            if seq and seq[0][0] == c and math.hypot(seq[0][1] - x, seq[0][2] - y) <= MERGE_YARDS:
                continue   # back at the first stop: a round trip
            seq.append((c, x, y))
        if len(seq) != sum(1 for p, _ in names if p == pid):
            raise SystemExit("path %d has %d stops; transports.csv names %d" % (
                pid, len(seq), sum(1 for p, _ in names if p == pid)))
        on_path = [dock_for(c, x, y, names[(pid, i + 1)]) for i, (c, x, y) in enumerate(seq)]
        for d in on_path:
            for other in on_path:
                if other is not d and other["name"] not in d["routes"]:
                    d["routes"].append(other["name"])
    for r in rows("tram.csv"):
        c, x, y, _ = trig_by_id[int(r["trigger"])]
        docks.append({"c": c, "x": x, "y": y, "name": r["dock"], "kind": "tram", "sides": "AH", "routes": [r["to"]]})
    report.append("")
    report.append("Transports (client positions: taxi path stops, tram triggers)")
    for d in docks:
        z = maps.zone_at(d["c"], d["x"], d["y"])
        report.append("  %-9s %-22s %-3s near %s  -> %s" % (
            d["kind"], d["name"], d["sides"], ("%s %.1f,%.1f" % (maps.name(z[0]), z[1] * 100, z[2] * 100)) if z else "?",
            ", ".join(d["routes"])))

    # Zone levels.
    zones = {}
    for u in sorted(maps.maps):
        if maps.kind(u) == 3 and u not in CITIES and maps.area_of(u) in levels:
            zones[u] = levels[maps.area_of(u)]
    report.append("")
    report.append("Zone levels: %d zones" % len(zones))
    report.append("  " + ", ".join("%s %d-%d" % (maps.name(u), lo, hi) for u, (lo, hi) in zones.items()))

    # Lua.
    L = [
        "-- Data/Landmarks.lua: GENERATED by Tools/gen_landmarks.py (client build %s). Do not edit:" % build,
        "-- change Tools/landmarks/*.csv and run it again. World positions (c = the client's",
        "-- continent map ID, x north, y west); the evidence is Tools/landmarks/report.txt.",
        "",
        "GlassPearls = GlassPearls or {}",
        "GlassPearls.LandmarkData = {",
        "    build = %s," % lua_str(build),
        "    entrances = {",
    ]
    for key in order:
        d = doors[key]
        kinds = {e["kind"] for e in d["list"]}
        L.append("        { key = %s, kind = %s, c = %d, x = %.1f, y = %.1f, zone = %d, confidence = %s, list = {" % (
            lua_str(key), lua_str("raid" if kinds == {"raid"} else "dungeon"), d["c"], d["x"], d["y"], d["zone"],
            lua_str(d["conf"])))
        for e in d["list"]:
            lv = ""
            if e["levels"]:
                lo, hi = e["levels"]
                lv = "min = %d, " % lo + ("max = %d, " % hi if hi else "")
            L.append("            { lfg = %d, name = %s, %sraid = %s }," % (
                e["lfg"], lua_str(e["name"]), lv, "true" if e["kind"] == "raid" else "false"))
        L.append("        } },")
    L.append("    },")
    L.append("    transports = {")
    for d in docks:
        L.append("        { kind = %s, c = %d, x = %.1f, y = %.1f, name = %s, sides = %s, routes = { %s } }," % (
            lua_str(d["kind"]), d["c"], d["x"], d["y"], lua_str(d["name"]), lua_str(d["sides"]),
            ", ".join(lua_str(n) for n in d["routes"])))
    L.append("    },")
    # Every zone map: flight points are asked per zone (C_TaxiMap.GetTaxiNodesForMap).
    zonemaps = sorted(u for u in maps.maps if maps.kind(u) == 3)
    L.append("    zonemaps = { %s }," % ", ".join(str(u) for u in zonemaps))
    L.append("    zones = {")
    for u, (lo, hi) in zones.items():
        L.append("        [%d] = { %d, %d },   -- %s" % (u, lo, hi, maps.name(u)))
    L.append("    },")
    L.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    with open(REPORT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print("%d entrances (%d doors), %d transport stops, %d zones -> %s" % (
        len(ent_rows), len(order), len(docks), len(zones), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
