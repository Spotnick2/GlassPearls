"""gen_training.py - Write Data/Training.lua: what each class trainer teaches on
WoW Forever, for the training reminder pearl (#27).

Source: WhatsTraining's curated Forever lists (by Sveng, MIT), its
Classes/Camelot/<Class>.lua files in References/Addons/Class/WhatsTraining.
They are read as TEXT by the small parser below, never run. The client's own
tables can't tell a trainer spell from a talent or a quest reward (Cat Form,
Summon Voidwalker and the mage talents all sit in the class skill lines), so
the curated list is the source and the client tables only check it:
  SpellName    every ID exists
  SpellLevels  its BaseLevel against the trainer level (differences reported)

Entry fields kept: id, level (the spellsByLevel key), cost (copper),
requiredIds, requiredTalentId, race, faction, skills. Anything else stops the
script: a new field needs a decision. overriddenGroups (a later member known
means the earlier ones are learned) are resolved from the file's local lists.
Writes Tools/training/report.txt.

Usage (from the repo root):
    python Tools/gen_training.py                 # the newest saved build
    python Tools/gen_training.py 1.60.1.70532
"""
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "..")
DB = os.path.join(ROOT, "References", "Forever", "db")
SRC = os.path.join(ROOT, "References", "Addons", "Class", "WhatsTraining", "WhatsTraining")
OUT = os.path.join(HERE, "..", "Data", "Training.lua")
REPORT = os.path.join(HERE, "training", "report.txt")
CLASSES = ("Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior")
FIELDS = {"id", "cost", "requiredIds", "requiredTalentId", "race", "faction", "skills"}
FACTIONS = {"Alliance", "Horde"}


# ---------------------------------------------------------------------------
# A parser for the Lua subset these files use: numbers, strings, names, and
# tables with `name =`, `[number] =` or positional fields. Comments skipped.

TOKEN = re.compile(r"""\s*(?:
    (?P<comment>--[^\n]*)
  | (?P<number>-?\d+)
  | (?P<string>"[^"\n]*"|'[^'\n]*')
  | (?P<name>[A-Za-z_][A-Za-z_0-9.]*)
  | (?P<punct>[{}\[\]=,;()])
  | (?P<other>\S)
)""", re.X)


def tokens(text):
    out = []
    for m in TOKEN.finditer(text):
        kind = m.lastgroup
        if kind is None or kind == "comment":
            continue
        out.append((kind, m.group(kind)))
    return out


class Parser:
    def __init__(self, toks, names):
        self.t, self.i, self.names = toks, 0, names

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError("expected %r, got %r" % (value, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.peek()
        if v == "{":
            return self.table()
        self.take()
        if kind == "number":
            return int(v)
        if kind == "string":
            return v[1:-1]
        if kind == "name":
            if v not in self.names:
                raise ValueError("unknown name %r" % v)
            return self.names[v]
        raise ValueError("unexpected %r" % v)

    def table(self):
        self.take("{")
        keyed, items = {}, []
        while self.peek()[1] != "}":
            kind, v = self.peek()
            if v == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                keyed[key] = self.value()
            elif kind == "name" and self.peek(1)[1] == "=":
                self.take()
                self.take("=")
                keyed[v] = self.value()
            else:
                items.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        if keyed and items:
            raise ValueError("a table mixes keyed and positional fields")
        return keyed if keyed else items


def parse_class(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r'wt\.forClass\("([A-Z]+)"\)', text)
    if not m:
        raise ValueError("%s: no wt.forClass" % path)
    token = m.group(1)
    names = {}
    for lm in re.finditer(r"^local (\w+) = (\{[^\n]*\})\s*$", text, re.M):
        names[lm.group(1)] = Parser(tokens(lm.group(2)), {}).value()
    groups = []
    gm = re.search(r"^class\.overriddenGroups = ", text, re.M)
    if gm:
        p = Parser(tokens(text[gm.end():]), names)
        groups = p.value()
    sm = re.search(r"^class\.spellsByLevel = ", text, re.M)
    if not sm:
        raise ValueError("%s: no spellsByLevel" % path)
    byLevel = Parser(tokens(text[sm.end():]), names).value()
    if not isinstance(byLevel, dict):
        raise ValueError("%s: spellsByLevel is not keyed by level" % path)
    entries = []
    for level in sorted(byLevel):
        for e in byLevel[level]:
            unknown = set(e) - FIELDS
            if unknown:
                raise ValueError("%s level %d: unknown fields %s" % (path, level, sorted(unknown)))
            if not isinstance(e.get("id"), int) or not isinstance(e.get("cost"), int):
                raise ValueError("%s level %d: an entry without id or cost" % (path, level))
            if "faction" in e and e["faction"] not in FACTIONS:
                raise ValueError("%s: faction %r" % (path, e["faction"]))
            for s in e.get("skills", []):
                if set(s) != {"skill", "level"}:
                    raise ValueError("%s: skills entry %r" % (path, s))
            entries.append(dict(e, level=level))
    return token, entries, groups


# ---------------------------------------------------------------------------

def build_of(path):
    return re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1)


def rows(table, build):
    path = os.path.join(DB, "forever-%s-%s.csv" % (table, build))
    if not os.path.exists(path):
        sys.exit("missing %s: python References/Tools/Wago/wago.py get %s --build %s" % (path, table, build))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def toc_version():
    with open(os.path.join(SRC, "WhatsTraining.toc"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("## Version:"):
                return line.split(":", 1)[1].strip()
    return "?"


def lua_entry(e):
    parts = ["id = %d" % e["id"], "level = %d" % e["level"], "cost = %d" % e["cost"]]
    if e.get("requiredIds"):
        parts.append("req = { %s }" % ", ".join(str(x) for x in e["requiredIds"]))
    if e.get("requiredTalentId"):
        parts.append("talent = %d" % e["requiredTalentId"])
    if e.get("race"):
        parts.append("race = %d" % e["race"])
    if e.get("faction"):
        parts.append('faction = "%s"' % e["faction"])
    if e.get("skills"):
        parts.append("skill = { %s }" % ", ".join("{ %d, %d }" % (s["skill"], s["level"]) for s in e["skills"]))
    return "{ " + ", ".join(parts) + " }"


def main():
    if len(sys.argv) > 1:
        build = sys.argv[1]
    else:
        files = sorted(glob.glob(os.path.join(DB, "forever-spellname-*.csv")))
        if not files:
            sys.exit("no SpellName export in %s" % DB)
        build = build_of(files[-1])
    names = {r["ID"]: r["Name_lang"] for r in rows("spellname", build)}
    levels = {}
    for r in rows("spelllevels", build):
        if r.get("DifficultyID", "0") == "0":
            levels[r["SpellID"]] = int(r["BaseLevel"] or 0)

    version = toc_version()
    report = ["gen_training.py: WhatsTraining %s, checked against build %s" % (version, build), ""]
    out = [
        "-- Data/Training.lua: GENERATED by Tools/gen_training.py. Do not edit: re-run it",
        "-- after a WhatsTraining update or a new build (Tools/training/report.txt).",
        "-- What each class trainer teaches on Forever. The list is WhatsTraining's",
        "-- (%s), curated by Sveng (MIT, thanks): Blizzard's facts, gathered" % version,
        "-- by hand. Checked against the client's SpellName and SpellLevels (build %s)." % build,
        "-- classes[classFile] = { spells = { { id, level, cost (copper), req = IDs",
        "-- that must be known, talent = the talent spell it needs, race = raceID,",
        '-- faction = "Alliance"|"Horde", skill = { { skillLine, rank } } }, ... },',
        "-- groups = { IDs where a later one known means the earlier ones are learned } }.",
        "",
        "GlassPearls = GlassPearls or {}",
        "GlassPearls.TrainingData = {",
        '    source = "WhatsTraining %s",' % version,
        '    build = "%s",' % build,
        "    classes = {",
    ]
    total = 0
    for cls in CLASSES:
        token, entries, groups = parse_class(os.path.join(SRC, "Classes", "Camelot", cls + ".lua"))
        notes = []
        for e in entries:
            sid = str(e["id"])
            if sid not in names:
                notes.append("%d: not in SpellName" % e["id"])
            elif levels.get(sid) and levels[sid] != e["level"]:
                notes.append("%d %s: trainer level %d, SpellLevels %d" % (e["id"], names[sid], e["level"], levels[sid]))
            t = e.get("requiredTalentId")
            if t and str(t) not in names:
                notes.append("%d: talent %d not in SpellName" % (e["id"], t))
        for g in groups:
            if not isinstance(g, list) or not all(isinstance(x, int) for x in g):
                raise ValueError("%s: an override group is not a list of IDs" % cls)
        out.append("        %s = {" % token)
        out.append("            spells = {")
        for e in entries:
            out.append("                %s,   -- %s" % (lua_entry(e), names.get(str(e["id"]), "?")))
        out.append("            },")
        out.append("            groups = {")
        for g in groups:
            out.append("                { %s },   -- %s" % (", ".join(str(x) for x in g), names.get(str(g[0]), "?")))
        out.append("            },")
        out.append("        },")
        total += len(entries)
        report.append("%s: %d spells, %d override groups, %d with a talent, %d race, %d faction, %d skill"
                      % (token, len(entries), len(groups), sum(1 for e in entries if e.get("requiredTalentId")),
                         sum(1 for e in entries if e.get("race")), sum(1 for e in entries if e.get("faction")),
                         sum(1 for e in entries if e.get("skills"))))
        report += ["  " + n for n in notes]
    out += ["    },", "}"]
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    report += ["", "%d spells written" % total]
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print("wrote %s (%d spells) and %s" % (OUT, total, REPORT))


if __name__ == "__main__":
    main()
