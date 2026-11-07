"""gen_gearskills.py - Write Data/GearSkills.lua: which weapon and armor skills
each class and race can still learn, for the untrained gear pearl (#86).

Sources (References/Forever/db, fetched once per build with
References/Tools/Wago/wago.py; this script never fetches anything):
  SkillLine           the skill lines and their names (category 6 weapons,
                      category 8 armor proficiencies)
  SkillRaceClassInfo  per skill line, the classes and races it applies to:
                      ClassMask (-1 all), RaceMasks_0 / RaceMasks_1 (signed
                      32-bit words over ChrRaces' PlayableRaceBit: bits 0-31,
                      then 32 and up; both 0: unrestricted, a convention no
                      gear row of 70790 uses), Availability (1 a starting
                      skill, 0 learned), Flags (0x100 NOT_TRAINABLE by
                      convention), MinLevel
  ChrRaces            each race's PlayableRaceBit
  ChrClasses          each class's Filename (the classFile UnitClass returns)

Rules (Codex review of the plan, #86):
  - A row applies to (class, race) when the class's bit is in ClassMask and
    the race's bit in its race mask word.
  - learn[classFile][raceID][skillLine] = MinLevel when an applicable row has
    Availability 0 and no 0x100 flag, and NO applicable row has Availability
    1 (a starting skill: if the client still draws it red, something else is
    wrong, and the pearl leaves it alone). Two eligible rows with different
    MinLevels: the lower (none in 70790; the report says).
  - subclass[classID][subclassID] = skillLine: Enum.ItemWeaponSubclass and
    the armor subclasses, fixed below (fishing poles, Generic, miscellaneous
    and the rest are left out: the pearl never touches them).
Writes Tools/gearskills/report.txt with every class x race decision.

Usage (from the repo root):
    python Tools/gen_gearskills.py                 # the newest saved build
    python Tools/gen_gearskills.py 1.60.1.70790
"""
import collections
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(__file__)
DB = os.path.join(HERE, "..", "..", "References", "Forever", "db")
OUT = os.path.join(HERE, "..", "Data", "GearSkills.lua")
REPORT = os.path.join(HERE, "gearskills", "report.txt")
TABLES = ("skillline", "skillraceclassinfo", "chrraces", "chrclasses")
NOT_TRAINABLE = 0x100

# Item class -> subclass -> skill line. Weapons (class 2, Enum.ItemWeaponSubclass) and armor (class 4).
SUBCLASS = {
    2: {0: 44, 1: 172, 2: 45, 3: 46, 4: 54, 5: 160, 6: 229, 7: 43, 8: 55, 10: 136, 13: 473, 15: 173, 16: 176,
        18: 226, 19: 228},
    4: {1: 415, 2: 414, 3: 413, 4: 293, 6: 433},
}
# Who teaches each kind (the pearl's note): weapon masters for weapons, the class trainer for armor.
KIND = {2: "weapon", 4: "armor"}


def build_of(path):
    return re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1)


def newest_build():
    files = glob.glob(os.path.join(DB, "forever-skillraceclassinfo-*.csv"))
    if not files:
        sys.exit("no SkillRaceClassInfo export in %s: python References/Tools/Wago/wago.py get %s"
                 % (DB, " ".join(TABLES)))
    return max((build_of(f) for f in files), key=lambda b: [int(x) for x in b.split(".")])


def read(table, build):
    path = os.path.join(DB, "forever-%s-%s.csv" % (table, build))
    if not os.path.exists(path):
        sys.exit("missing %s: python References/Tools/Wago/wago.py get %s --build %s" % (path, table, build))
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def u32(v):
    return int(v) & 0xFFFFFFFF


def applies(row, class_id, race_bit):
    cm = int(row["ClassMask"])
    if cm != -1 and not (u32(cm) >> (class_id - 1)) & 1:
        return False
    w0, w1 = u32(row["RaceMasks_0"]), u32(row["RaceMasks_1"])
    if w0 == 0 and w1 == 0:
        return True
    word, bit = (w0, race_bit) if race_bit < 32 else (w1, race_bit - 32)
    return (word >> bit) & 1 == 1


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else newest_build()
    lines = {r["ID"]: r for r in read("skillline", build)}
    rows = read("skillraceclassinfo", build)
    races = [(int(r["ID"]), r["ClientFileString"], int(r["PlayableRaceBit"]))
             for r in read("chrraces", build) if r["PlayableRaceBit"] not in ("", "-1")]
    classes = [(int(r["ID"]), r["Filename"]) for r in read("chrclasses", build) if r.get("Filename")]
    wanted = sorted({sl for subs in SUBCLASS.values() for sl in subs.values()})
    for sl in wanted:
        if str(sl) not in lines:
            sys.exit("skill line %d is not in SkillLine %s" % (sl, build))
    by_line = collections.defaultdict(list)
    for r in rows:
        if int(r["SkillID"]) in wanted:
            by_line[int(r["SkillID"])].append(r)

    learn = collections.defaultdict(lambda: collections.defaultdict(dict))
    report = ["gen_gearskills.py, build %s" % build, ""]
    for class_id, cfile in classes:
        for race_id, rname, rbit in races:
            decided = []
            for sl in wanted:
                app = [r for r in by_line[sl] if applies(r, class_id, rbit)]
                if not app:
                    continue
                start = [r for r in app if r["Availability"] == "1"]
                train = [r for r in app if r["Availability"] == "0" and not int(r["Flags"]) & NOT_TRAINABLE]
                name = lines[str(sl)]["DisplayName_lang"]
                if start:
                    decided.append("  %-18s starting skill (rows %s): left alone" % (name, ",".join(r["ID"] for r in start)))
                elif train:
                    levels = sorted({int(r["MinLevel"]) for r in train})
                    learn[cfile][race_id][sl] = levels[0]
                    note = " (several MinLevels %s: the lower)" % levels if len(levels) > 1 else ""
                    decided.append("  %-18s learnable from %d (rows %s)%s" % (name, levels[0],
                                   ",".join(r["ID"] for r in train), note))
                else:
                    decided.append("  %-18s not trainable (rows %s, flag 0x100)" % (name, ",".join(r["ID"] for r in app)))
            if decided:
                report.append("%s %s (%d):" % (cfile, rname, race_id))
                report.extend(decided)

    out = ["-- Data/GearSkills.lua: GENERATED by Tools/gen_gearskills.py from the client's",
           "-- SkillLine, SkillRaceClassInfo, ChrRaces and ChrClasses tables, build %s." % build,
           "-- Never edit it: run the script again. Tools/gearskills/report.txt has every decision.",
           "--   learn[classFile][raceID][skillLine] = the level it can be learned from",
           "--   subclass[itemClassID][subclassID] = skillLine; kind[itemClassID] = \"weapon\" | \"armor\"",
           "--   names[skillLine] = the client's English name (the report's; the pearl shows the client's own text)",
           "",
           "GlassPearls = GlassPearls or {}",
           "GlassPearls.GearSkillData = {",
           "    build = \"%s\"," % build,
           "    learn = {"]
    for cfile in sorted(learn):
        out.append("        %s = {" % cfile)
        for race_id in sorted(learn[cfile]):
            pairs = ", ".join("[%d] = %d" % (sl, lv) for sl, lv in sorted(learn[cfile][race_id].items()))
            out.append("            [%d] = { %s }," % (race_id, pairs))
        out.append("        },")
    out.append("    },")
    out.append("    subclass = {")
    for cid in sorted(SUBCLASS):
        pairs = ", ".join("[%d] = %d" % (s, sl) for s, sl in sorted(SUBCLASS[cid].items()))
        out.append("        [%d] = { %s }," % (cid, pairs))
    out.append("    },")
    out.append("    kind = { %s }," % ", ".join('[%d] = "%s"' % (c, k) for c, k in sorted(KIND.items())))
    out.append("    names = {")
    for sl in wanted:
        out.append('        [%d] = "%s",' % (sl, lines[str(sl)]["DisplayName_lang"]))
    out.append("    },")
    out.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")
    print("wrote %s and %s" % (OUT, REPORT))


if __name__ == "__main__":
    main()
