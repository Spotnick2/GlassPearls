"""gen_restock.py - Write Data/Restock.lua: what the restock pearl (#14) may
buy, from the client's own tables.

  food / drink  items of class 0, subclass 5 whose use spell (directly, or a
                spell it triggers: the Manna Biscuits) carries aura 84 (regen
                health: food) or 85 (regen mana: water). Alcohol carries
                neither. value = the total restored: the aura's points x the
                spell's duration / 5 s (Refreshing Spring Water 42 x 18 / 5 =
                151, as its tooltip says). bop: bind on pickup (never bought;
                the level-1 copies of high-end food are). conjured: Flags_0
                0x2.
  ammo          class 6: subclass 2 arrows, 3 bullets, with the required level.
  reagents      Tools/restock/reagents.csv (an audited allowlist), kept only
                where a class's own spell consumes the item (SpellReagents over
                the class skill lines of SkillLineAbility, rune copies dropped: SkillLine category 7
                with flag 0x400, as gen_ranks.py; the rogue's Poisons line too),
                per class, with the spells that consume it.

Tables: Item, ItemSparse, ItemXItemEffect, ItemEffect, SpellEffect, SpellMisc,
SpellDuration, SpellReagents, SkillLine, SkillLineAbility, SpellName (fetched
once per build with References/Tools/Wago/wago.py). Never fetches anything.
Tools/restock/report.txt lists every decision.

Usage (from the repo root):
    python Tools/gen_restock.py                 # the newest saved build
    python Tools/gen_restock.py 1.60.1.70532
"""
import collections
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(__file__)
DB = os.path.join(HERE, "..", "..", "References", "Forever", "db")
OUT = os.path.join(HERE, "..", "Data", "Restock.lua")
REPORT = os.path.join(HERE, "restock", "report.txt")
ALLOW = os.path.join(HERE, "restock", "reagents.csv")

AURA_FOOD, AURA_DRINK = "84", "85"
EFFECT_TRIGGER = "64"
CLASS_CATEGORY, CLASS_FLAG = 7, 0x400
POISONS_LINE = 40
RUNE_ACQUIRE = "3"   # Season of Discovery rune copies (as gen_ranks.py)
CONJURED = 0x2
# ChrClasses IDs (SkillLineAbility.ClassMask bit = ID - 1) to class files.
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN",
           8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
# The classic vendor lines, for the report's order check.
VENDOR_LINES = {
    "water": [159, 1179, 1205, 1708, 1645, 8766],
    "bread": [4540, 4541, 4542, 4544, 4601, 8950],
    "meat": [117, 2287, 3770, 3771, 4599, 8952],
}


def build_of(path):
    return re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1)


def newest_build():
    files = glob.glob(os.path.join(DB, "forever-itemxitemeffect-*.csv"))
    if not files:
        sys.exit("no ItemXItemEffect export in %s: python References/Tools/Wago/wago.py get ItemXItemEffect" % DB)
    return build_of(max(files, key=lambda p: tuple(int(x) for x in build_of(p).split("."))))


def rows(table, build):
    path = os.path.join(DB, "forever-%s-%s.csv" % (table, build))
    if not os.path.exists(path):
        sys.exit("missing %s: python References/Tools/Wago/wago.py get %s --build %s" % (path, table, build))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return float(v or 0)
    except ValueError:
        return 0.0


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else newest_build()
    item = {r["ID"]: r for r in rows("item", build)}
    sparse = {r["ID"]: r for r in rows("itemsparse", build)}
    effect = {r["ID"]: r for r in rows("itemeffect", build)}
    item_spells = collections.defaultdict(list)
    for r in rows("itemxitemeffect", build):
        e = effect.get(r["ItemEffectID"])
        if e and e["SpellID"] not in ("", "0"):
            item_spells[r["ItemID"]].append(e["SpellID"])
    spell_effects = collections.defaultdict(list)
    for r in rows("spelleffect", build):
        if int(r["DifficultyID"] or 0) == 0:
            spell_effects[r["SpellID"]].append(r)
    durations = {r["ID"]: int(r["Duration"] or 0) for r in rows("spellduration", build)}
    spell_duration = {}
    for r in rows("spellmisc", build):
        if int(r["DifficultyID"] or 0) == 0:
            spell_duration[r["SpellID"]] = durations.get(r["DurationIndex"], 0)
    names = {r["ID"]: r["Name_lang"] for r in rows("spellname", build)}

    def restores(sid, depth=0):
        """{kind: total} for one spell, following triggered spells once."""
        out = {}
        for f in spell_effects.get(sid, []):
            kind = {AURA_FOOD: "food", AURA_DRINK: "drink"}.get(f["EffectAura"])
            if kind and f["Effect"] == "6":
                seconds = spell_duration.get(sid, 0) / 1000.0
                out[kind] = out.get(kind, 0) + int(round(num(f["EffectBasePointsF"]) * seconds / 5))
            elif f["Effect"] == EFFECT_TRIGGER and depth == 0:
                for k, v in restores(f["EffectTriggerSpell"], 1).items():
                    out[k] = out.get(k, 0) + v
        return out

    report = ["gen_restock.py, build %s" % build, ""]
    food, drink, dropped = {}, {}, []
    for iid, r in item.items():
        if r["ClassID"] != "0" or r["SubclassID"] != "5" or iid not in sparse:
            continue
        s = sparse[iid]
        kinds = {}
        for sid in item_spells.get(iid, []):
            for k, v in restores(sid).items():
                kinds[k] = max(kinds.get(k, 0), v)
        if not kinds:
            dropped.append((int(iid), s["Display_lang"], "restores neither health nor mana (alcohol, buff food)"))
            continue
        entry = {"level": int(s["RequiredLevel"] or 0), "bop": s["Bonding"] == "1",
                 "conjured": bool(int(s["Flags_0"] or 0) & CONJURED), "name": s["Display_lang"]}
        if "food" in kinds:
            food[int(iid)] = dict(entry, value=kinds["food"])
        if "drink" in kinds:
            drink[int(iid)] = dict(entry, value=kinds["drink"])

    ammo = {}
    for iid, r in item.items():
        if r["ClassID"] == "6" and r["SubclassID"] in ("2", "3") and iid in sparse:
            s = sparse[iid]
            ammo[int(iid)] = {"kind": int(r["SubclassID"]), "level": int(s["RequiredLevel"] or 0),
                              "name": s["Display_lang"]}

    # Reagents: the allowlist, over the classes' own spells.
    allow = {}
    with open(ALLOW, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(line for line in f if not line.startswith("#")):
            allow[int(r["item"])] = (int(r["target"]), r["why"])
    class_lines = {int(r["ID"]) for r in rows("skillline", build)
                   if int(r["CategoryID"] or 0) == CLASS_CATEGORY and int(r["Flags"] or 0) & CLASS_FLAG}
    class_lines.add(POISONS_LINE)
    class_spells = collections.defaultdict(set)
    for r in rows("skilllineability", build):
        if int(r["SkillLine"]) not in class_lines or r["AcquireMethod"] == RUNE_ACQUIRE:
            continue
        mask = int(r["ClassMask"] or 0)
        for cid, cls in CLASSES.items():
            if mask & (1 << (cid - 1)):
                class_spells[cls].add(r["Spell"])
    consumes = collections.defaultdict(list)
    for r in rows("spellreagents", build):
        for k in range(8):
            reagent = r.get("Reagent_%d" % k, "0")
            if reagent not in ("", "0"):
                consumes[r["SpellID"]].append(int(reagent))
    reagents = collections.defaultdict(lambda: collections.defaultdict(set))
    unlisted = collections.defaultdict(set)
    for cls, sids in class_spells.items():
        for sid in sids:
            for reagent in consumes.get(sid, []):
                if reagent in allow:
                    reagents[cls][reagent].add(int(sid))
                else:
                    unlisted[reagent].add("%s %s" % (cls, names.get(sid, sid)))
    used = {i for per in reagents.values() for i in per}
    for i in sorted(set(allow) - used):
        sys.exit("reagents.csv lists %d (%s), but no class spell consumes it" % (i, allow[i][1]))

    # The report.
    report.append("%d food, %d water (Manna Biscuits and the like are both), %d ammo" % (len(food), len(drink), len(ammo)))
    report.append("")
    report.append("Classic vendor lines, value beside required level (each should rise):")
    for line, ids in VENDOR_LINES.items():
        table = drink if line == "water" else food
        report.append("  %s: %s" % (line, ", ".join(
            "%s %d@%d" % (table[i]["name"], table[i]["value"], table[i]["level"]) if i in table else "%d missing" % i
            for i in ids)))
    report.append("")
    report.append("Bind on pickup (never bought, counted when carried):")
    for i in sorted(set(food) | set(drink)):
        e = food.get(i) or drink.get(i)
        if e["bop"]:
            report.append("  %d %s (level %d)" % (i, e["name"], e["level"]))
    report.append("")
    report.append("Dropped food & drink:")
    for i, n, why in sorted(dropped):
        report.append("  %d %s: %s" % (i, n, why))
    report.append("")
    report.append("Reagents kept, per class:")
    for cls in sorted(reagents):
        for i in sorted(reagents[cls]):
            report.append("  %s %d %s (target %d): %s" % (cls, i, sparse.get(str(i), {}).get("Display_lang", "?"),
                          allow[i][0], ", ".join(sorted(names.get(str(s), str(s)) for s in reagents[cls][i]))))
    report.append("")
    report.append("Reagents of class spells not on the allowlist (not bought):")
    for i in sorted(unlisted):
        report.append("  %d %s: %s" % (i, sparse.get(str(i), {}).get("Display_lang", "?"), ", ".join(sorted(unlisted[i]))))

    def flag(e, k):
        return (", %s = true" % k) if e[k] else ""

    lines = [
        "-- Data/Restock.lua: GENERATED by Tools/gen_restock.py from the client's tables",
        "-- (build %s, wago.tools) and Tools/restock/reagents.csv. Do not edit: re-run" % build,
        "-- the script after a new build. What the restock pearl (#14) may buy: food and",
        "-- water (value: the total restored; bop: bind on pickup, never bought), ammo",
        "-- (kind 2 arrows, 3 bullets) and, per class, the allowlisted reagents its own",
        "-- spells consume.",
        "",
        "GlassPearls = GlassPearls or {}",
        "GlassPearls.RestockData = {",
        "    build = \"%s\"," % build,
    ]
    for label, table in (("food", food), ("drink", drink)):
        lines.append("    %s = {" % label)
        for i in sorted(table):
            e = table[i]
            lines.append("        [%d] = { level = %d, value = %d%s%s },   -- %s" % (
                i, e["level"], e["value"], flag(e, "bop"), flag(e, "conjured"), e["name"]))
        lines.append("    },")
    lines.append("    ammo = {")
    for i in sorted(ammo):
        e = ammo[i]
        lines.append("        [%d] = { kind = %d, level = %d },   -- %s" % (i, e["kind"], e["level"], e["name"]))
    lines.append("    },")
    lines.append("    reagents = {")
    for cls in sorted(reagents):
        lines.append("        %s = {" % cls)
        for i in sorted(reagents[cls]):
            spells = ", ".join(str(s) for s in sorted(reagents[cls][i]))
            lines.append("            [%d] = { %s },   -- %s" % (i, spells, sparse.get(str(i), {}).get("Display_lang", "?")))
        lines.append("        },")
    lines.append("    },")
    lines.append("    targets = {")
    for i in sorted(used):
        lines.append("        [%d] = %d,   -- %s" % (i, allow[i][0], allow[i][1]))
    lines.append("    },")
    lines.append("}")
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(REPORT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print("%d food, %d water, %d ammo, %d reagents from build %s -> %s" % (
        len(food), len(drink), len(ammo), len(used), build, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
