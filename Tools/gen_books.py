"""gen_books.py - Write Data/Books.lua (the library books pearl's data, #72)
and Tools/books/report.txt (the evidence, for review and day one).

The books are the client's: every ItemSparse row whose description calls it an
addition to "any library's collection", bind on pickup and unique. The run
fails if that list and Tools/books/books.csv differ.

Where each book lies is not in the client's tables (spawns are the server's).
Wowhead Forever has it, read from the shared cache only
(References/Tools/Wowhead/wowhead.py ... --offline; the fetch is a separate,
deliberate step, see CLAUDE.md and the wowhead-forever skill): the book's item
names the object it comes from (source 2, sourcemore), the object its spawn
points per zone (Wowhead's zone is the AreaTable ID: the UI map whose first
assignment is that area, exactly one zone map or the run fails; floor 0
only). Every book's spots are accepted in the CSV: `spots` = `wowhead` takes
those, `hand` the CSV's zone map, x and y instead (`source` says why; the
report shows what Wowhead says). A spot within MERGE_YARDS of another of the
same book on the same continent is one spot; two books never merge.
`entrance` marks a spot that is an entrance, not the book's place.

The turn-in quest: the CSV's ID, checked against Wowhead's cached quest of the
same name (a name search) or a cached quest tooltip that requires the book.
A book whose quest Wowhead doesn't know must be `unconfirmed` or `absent`.

Positions are written as world coordinates in the client tables' order (x
north, y west, c = the continent's map ID), as Data/Landmarks.lua, plus the
zone map and its x, y (0-100) for the tooltip.

Usage (from the repo root):  python Tools/gen_books.py
"""
import csv
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "landmarks"))
import clientdb as db  # noqa: E402

SRC = os.path.join(HERE, "books")
OUT = os.path.join(HERE, "..", "Data", "Books.lua")
REPORT = os.path.join(SRC, "report.txt")
WOWHEAD = os.path.normpath(os.path.join(HERE, "..", "..", "References", "Tools", "Wowhead", "wowhead.py"))
MERGE_YARDS = 30
MARK = "addition to any library's collection"
STATUSES = ("ok", "unconfirmed", "absent")
CONTINENTS = (0, 1)       # Eastern Kingdoms, Kalimdor
FACTIONS = ("", "Alliance", "Horde")


def wowhead(*args):
    """One offline call of the shared tool; its results."""
    out = subprocess.run([sys.executable, "-I", WOWHEAD] + list(args) + ["--offline"],
                         capture_output=True, text=True, encoding="utf-8", check=False).stdout
    return json.loads(out).get("results", [])


def wowhead_ids(kind, ids, *extra):
    listfile = os.path.join(SRC, ".ids.tmp")
    with open(listfile, "w") as f:
        f.write("\n".join(str(i) for i in sorted(ids)) + "\n")
    try:
        return {int(r["id"]): r for r in wowhead("get", kind, "--ids-file", listfile, "--full", *extra)}
    finally:
        os.remove(listfile)


def finite(*vs):
    return all(isinstance(v, (int, float)) and math.isfinite(v) for v in vs)


def convert(maps, area, zone, x, y):
    """A zone map position (0-100) to (continent, world x, world y, assignment), validated."""
    if not finite(x, y) or not (0 < x < 100 and 0 < y < 100):
        raise SystemExit("zone %d: position %r, %r isn't inside 0-100" % (zone, x, y))
    a = maps._rect(zone)
    if not a:
        raise SystemExit("zone %d has no UiMapAssignment" % zone)
    keys = ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1", "Region_0", "Region_1", "Region_3", "Region_4")
    if not finite(*(a[k] for k in keys)):
        raise SystemExit("zone %d: a non-finite rectangle" % zone)
    if not (a["UiMin_0"] < a["UiMax_0"] and a["UiMin_1"] < a["UiMax_1"]
            and a["Region_0"] < a["Region_3"] and a["Region_1"] < a["Region_4"]):
        raise SystemExit("zone %d: a degenerate rectangle" % zone)
    if a["continent"] not in CONTINENTS:
        raise SystemExit("zone %d: on world map %d, not a continent" % (zone, a["continent"]))
    if area is not None and maps.area_of(zone) != area:
        raise SystemExit("zone %d: its first assignment is area %s, not %d" % (zone, maps.area_of(zone), area))
    c, wx, wy = maps.to_world(zone, x / 100, y / 100)
    if not finite(wx, wy) or not (a["Region_0"] <= wx <= a["Region_3"] and a["Region_1"] <= wy <= a["Region_4"]):
        raise SystemExit("zone %d: %.1f, %.1f converts outside its world rectangle" % (zone, x, y))
    return c, wx, wy, a


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    build = db.build_of("ItemSparse")
    maps = db.Maps(build)   # UiMap and UiMapAssignment of the same build, or the run fails
    report = ["Library books evidence, client build %s" % build, ""]

    client = {}
    for r in db.table("ItemSparse", build):
        if MARK in (r.get("Description_lang") or ""):
            if r["Bonding"] != "1" or r["MaxCount"] != "1":
                raise SystemExit("%s %s: a library book that isn't bind on pickup and unique" % (r["ID"], r["Display_lang"]))
            client[int(r["ID"])] = r["Display_lang"]
    with open(os.path.join(SRC, "books.csv"), newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    listed = [int(r["item"]) for r in rows]
    if len(set(listed)) != len(listed):
        raise SystemExit("books.csv lists a book twice")
    if set(listed) != set(client):
        raise SystemExit("books.csv and the client differ: missing %s, not a book %s"
                         % (sorted(set(client) - set(listed)), sorted(set(listed) - set(client))))

    area_map = {}
    for u in maps.maps:
        if maps.kind(u) == 3 and maps.area_of(u):
            area_map.setdefault(maps.area_of(u), []).append(u)

    items = wowhead_ids("item", listed, "--kind", "xml")
    objects_of = {}
    for item, r in items.items():
        j = ((r.get("fields") or {}).get("json") or {}) if r.get("outcome") in ("cached", "fetched") else {}
        objects_of[item] = [s["ti"] for s in j.get("sourcemore") or [] if s.get("t") == 2 and s.get("ti")]
    objects = wowhead_ids("object", {o for os_ in objects_of.values() for o in os_})
    quests = wowhead_ids("quest", {int(r["quest"]) for r in rows if r["quest"]})

    def wowhead_spots(item):
        spots = []
        for o in objects_of.get(item, []):
            m = ((objects.get(o) or {}).get("fields") or {}).get("map") or {}
            zone_maps = area_map.get(m.get("zone")) or []
            if len(zone_maps) != 1:
                if m.get("coords"):
                    report.append("    object %d: area %s is %d zone maps, not used" % (o, m.get("zone"), len(zone_maps)))
                continue
            for floor, points in (m.get("coords") or {}).items():
                if floor != "0":
                    raise SystemExit("object %d: coordinates on floor %s (only floor 0 is converted)" % (o, floor))
                for x, y in points:
                    spots.append((zone_maps[0], x, y, o, m.get("zone")))
        return spots

    def quest_ok(item, name, quest):
        q = quests.get(quest)
        text = ((q or {}).get("fields") or {}).get("text") or []
        if q and q.get("outcome") in ("cached", "fetched") and ("- " + name) in text:
            return "tooltip requires it"
        for res in wowhead("search", name, "--type", "quest"):
            for h in res.get("hits") or []:
                if h.get("type") == "quest" and h.get("name") == name and int(h["id"]) == quest:
                    return "name search"
        return None

    books = []
    report.append("Books (item, quest, status: spots)")
    for r in rows:
        item, quest = int(r["item"]), int(r["quest"])
        name, status, faction = client[item], r["status"], r["faction"]
        if status not in STATUSES or faction not in FACTIONS:
            raise SystemExit("%d: status %r or faction %r" % (item, status, faction))
        evidence = quest_ok(item, name, quest)
        if not evidence and status == "ok":
            raise SystemExit("%d %s: quest %d isn't confirmed by Wowhead's cache; mark it unconfirmed or absent"
                             % (item, name, quest))
        found = wowhead_spots(item)
        report.append("  %d %s | quest %d (%s) | %s%s" % (item, name, quest, evidence or "NOT on Wowhead", status,
                                                         (" | " + faction) if faction else ""))
        if r["spots"] not in ("wowhead", "hand") or bool(r["zone"]) != (r["spots"] == "hand"):
            raise SystemExit("%d: spots %r needs a zone, x and y exactly when 'hand'" % (item, r["spots"]))
        if r["entrance"] not in ("", "1"):
            raise SystemExit("%d: entrance %r" % (item, r["entrance"]))
        if r["spots"] == "hand":
            zone, x, y = int(r["zone"]), float(r["x"]), float(r["y"])
            if maps.kind(zone) != 3:
                raise SystemExit("%d: zone %d isn't a zone map" % (item, zone))
            raw = [(zone, x, y, None, None)]
            report.append("    by hand: %s %.1f, %.1f (%s)" % (maps.name(zone), x, y, r["source"] or "no reason given"))
            for z, wx, wy, o, _ in found:
                report.append("    Wowhead says (not used): %s %.1f, %.1f (object %d)" % (maps.name(z), wx, wy, o))
        else:
            if not found:
                raise SystemExit("%d %s: no spot on Wowhead (cached): give it by hand" % (item, name))
            for o in objects_of.get(item, []):
                report.append("    object %d: %s" % (o, (objects.get(o) or {}).get("name")))
            raw = found
        spots = []
        for zone, x, y, o, area in raw:
            if maps.kind(zone) != 3:
                raise SystemExit("%d: zone %d isn't a zone map" % (item, zone))
            c, wx, wy, a = convert(maps, area, zone, x, y)
            w = (c, wx, wy)
            near = next((s for s in spots if s["c"] == w[0] and math.hypot(s["x"] - w[1], s["y"] - w[2]) <= MERGE_YARDS), None)
            if near:
                near["n"] += 1
                report.append("    merged: %s %.1f, %.1f into %.1f, %.1f" % (maps.name(zone), x, y, near["mx"], near["my"]))
                continue
            spots.append({"c": w[0], "x": w[1], "y": w[2], "zone": zone, "mx": x, "my": y, "n": 1,
                          "area": area if area is not None else maps.area_of(zone), "assign": a["id"],
                          "order": a["order"]})
        for s in spots:
            report.append("    spot: %s (area %d, map %d, assignment %d order %d) %.1f, %.1f -> continent %d, "
                          "world %.1f, %.1f (%d point%s)%s%s"
                          % (maps.name(s["zone"]), s["area"], s["zone"], s["assign"], s["order"], s["mx"], s["my"],
                             s["c"], s["x"], s["y"], s["n"],
                             "" if s["n"] == 1 else "s", " [wowhead]" if r["spots"] == "wowhead" else "",
                             " [entrance]" if r["entrance"] else ""))
        books.append({"item": item, "quest": quest, "faction": faction, "status": status, "note": r["note"],
                      "hand": r["spots"] == "hand", "entrance": r["entrance"] == "1", "spots": spots})

    out = ["-- Data/Books.lua: GENERATED by Tools/gen_books.py (client build %s). Do not edit:" % build,
           "-- change Tools/books/books.csv and run it again. World positions (c = the client's",
           "-- continent map ID, x north, y west) and the zone map's x, y (0-100); the evidence is",
           "-- Tools/books/report.txt.",
           "",
           "GlassPearls = GlassPearls or {}",
           "GlassPearls.BookData = {",
           "    build = %s," % lua_str(build),
           "    books = {"]
    for b in books:
        fields = ["item = %d" % b["item"], "quest = %d" % b["quest"]]
        if b["faction"]:
            fields.append("faction = %s" % lua_str(b["faction"]))
        if b["status"] != "ok":
            fields.append("status = %s" % lua_str(b["status"]))
        if b["hand"]:
            fields.append("hand = true")
        if b["entrance"]:
            fields.append("entrance = true")
        if b["note"]:
            fields.append("note = %s" % lua_str(b["note"]))
        spots = ", ".join("{ c = %d, x = %.1f, y = %.1f, zone = %d, mx = %.1f, my = %.1f }"
                          % (s["c"], s["x"], s["y"], s["zone"], s["mx"], s["my"]) for s in b["spots"])
        out.append("        { %s, spots = { %s } }," % (", ".join(fields), spots))
    out += ["    },", "}", ""]
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(out))
    report += ["", "%d books, %d spots" % (len(books), sum(len(b["spots"]) for b in books)), ""]
    with open(REPORT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(report))
    print("wrote %s (%d books) and %s" % (os.path.relpath(OUT), len(books), os.path.relpath(REPORT)))


if __name__ == "__main__":
    main()
