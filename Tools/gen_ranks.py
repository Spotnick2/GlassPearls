"""gen_ranks.py - Write Data/SpellRanks.lua: every class spell that comes in
ranks, grouped, from the client's own tables, for the low spell ranks pearl
(#12). At runtime the pearl compares spell IDs only; the English names here
group the ranks offline and never reach the addon.

Sources (References/Forever/db, fetched once per build with
References/Tools/Wago/wago.py; this script never fetches anything):
  SkillLine          which skill lines are class trees (CategoryID 7 with the
                     0x400 flag: pet families and Beast Training lack it)
  SkillLineAbility   the spells of each skill line; AcquireMethod 3 rows are
                     Season of Discovery rune copies (408xxx, 425xxx), dropped
  Spell              NameSubtext_lang "Rank N" and the description
  SpellName          the name a group is keyed on, with its skill line
  SpellLevels        BaseLevel (DifficultyID 0), shown only, never compared

Rules:
  - A group is (skill line, English name) with two or more distinct ranks.
  - A group with two spells at one rank is two spells sharing a name
    (Lightning Shield's buff and its bolt): it is split by the first sentence
    of their descriptions, one chain each. Two IDs left at one rank of a chain
    are the same spell (Seal of Righteousness 1: 20154, 21084): both stay.
  - A gap (a rank missing from SkillLineAbility) is filled from Spell +
    SpellName + SpellLevels only when exactly one spell has that name, that
    rank and a level above 0; otherwise it stays a gap. Split chains are never
    gap-filled.
  - Tools/ranks/exclude.csv names groups whose ranks are different spells
    (Detect Invisibility: lesser, normal, greater). Groups whose descriptions
    differ once numbers and $tokens are stripped are listed in the report for
    a by-hand review.
Writes Tools/ranks/report.txt with every decision.

Usage (from the repo root):
    python Tools/gen_ranks.py                 # the newest saved build
    python Tools/gen_ranks.py 1.60.1.70532
"""
import collections
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(__file__)
DB = os.path.join(HERE, "..", "..", "References", "Forever", "db")
OUT = os.path.join(HERE, "..", "Data", "SpellRanks.lua")
REPORT = os.path.join(HERE, "ranks", "report.txt")
EXCLUDE = os.path.join(HERE, "ranks", "exclude.csv")
TABLES = ("skillline", "skilllineability", "spell", "spellname", "spelllevels")
CLASS_CATEGORY, CLASS_FLAG, RUNE_ACQUIRE = 7, 0x400, "3"
RANK = re.compile(r"Rank (\d+)$")


def build_of(path):
    return re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1)


def newest_build():
    files = glob.glob(os.path.join(DB, "forever-skilllineability-*.csv"))
    if not files:
        sys.exit("no SkillLineAbility export in %s: python References/Tools/Wago/wago.py get %s"
                 % (DB, " ".join(TABLES)))
    return build_of(max(files, key=lambda p: tuple(int(x) for x in build_of(p).split("."))))


def rows(table, build):
    path = os.path.join(DB, "forever-%s-%s.csv" % (table, build))
    if not os.path.exists(path):
        sys.exit("missing %s: python References/Tools/Wago/wago.py get %s --build %s" % (path, table, build))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def normalized(text):
    """A description with its numbers and $tokens gone: ranks of one spell match."""
    text = re.sub(r"\$\{[^}]*\}|\$<[^>]*>|\$[a-zA-Z]+\d*|\$\d+[a-zA-Z]*\d*", "", text or "")
    return re.sub(r"\s+", " ", re.sub(r"[\d.,%]+", "", text)).strip().lower()


def first_sentence(text):
    """What a spell is: its description's first sentence, normalized. Later
    sentences change between ranks (Holy Nova's later ranks add one); two
    different spells sharing a name differ in the first."""
    return normalized(re.split(r"\.(?:\s|$)", text or "", maxsplit=1)[0])


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else newest_build()
    class_lines = {int(r["ID"]): r["DisplayName_lang"] for r in rows("skillline", build)
                   if int(r["CategoryID"] or 0) == CLASS_CATEGORY and int(r["Flags"] or 0) & CLASS_FLAG}
    name = {int(r["ID"]): r["Name_lang"] for r in rows("spellname", build)}
    spell = {int(r["ID"]): r for r in rows("spell", build)}
    level = {}
    for r in rows("spelllevels", build):
        if int(r["DifficultyID"] or 0) == 0:
            level[int(r["SpellID"])] = int(r["BaseLevel"] or 0)

    def rank_of(sid):
        m = RANK.match((spell.get(sid) or {}).get("NameSubtext_lang", "") or "")
        return int(m.group(1)) if m else None

    groups = collections.defaultdict(dict)        # (line, name) -> {spellID: rank}
    runes = 0
    for r in rows("skilllineability", build):
        line, sid = int(r["SkillLine"]), int(r["Spell"])
        if line not in class_lines or rank_of(sid) is None:
            continue
        if r["AcquireMethod"] == RUNE_ACQUIRE:
            runes += 1
            continue
        groups[(line, name.get(sid, "?"))][sid] = rank_of(sid)

    # Candidates for gaps: name -> rank -> [spellID] with a level.
    by_name = collections.defaultdict(lambda: collections.defaultdict(list))
    for sid in spell:
        rk = rank_of(sid)
        if rk is not None and level.get(sid, 0) > 0 and sid in name:
            by_name[name[sid]][rk].append(sid)

    excluded = {}
    if os.path.exists(EXCLUDE):
        with open(EXCLUDE, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(r for r in f if not r.startswith("#")):
                excluded[(int(r["skillline"]), r["name"])] = r["reason"]

    report = ["gen_ranks.py, build %s" % build, "",
              "%d class skill lines; %d rune copies dropped (AcquireMethod 3)" % (len(class_lines), runes), ""]
    kept, notes = [], collections.defaultdict(list)
    for key in sorted(groups, key=lambda k: (k[0], k[1])):
        members = groups[key]
        ranks = collections.Counter(members.values())
        label = "%s / %s" % (class_lines[key[0]], key[1])
        if len(ranks) < 2:
            continue
        if key in excluded:
            notes["excluded (Tools/ranks/exclude.csv)"].append("%s: %s" % (label, excluded[key]))
            continue
        chains = [members]
        if any(n > 1 for n in ranks.values()):
            # Two spells share the name (Lightning Shield's buff and its bolt,
            # Holy Nova's damage and its heal): split by the first sentence of
            # the description, one chain each. Two IDs left at one rank of a
            # chain are the same spell (Seal of Righteousness 1): both stay.
            split = collections.defaultdict(dict)
            for s, rk in members.items():
                split[first_sentence(spell[s].get("Description_lang"))][s] = rk
            chains = [c for c in split.values() if len(set(c.values())) >= 2]
            for c in chains:
                if len(set(c.values())) != len(c):
                    notes["same spell, two IDs at one rank"].append(
                        "%s: %s" % (label, ", ".join(str(s) for s in sorted(c, key=lambda x: (c[x], x)))))
            notes["split by description"].append("%s: %d chain(s)" % (label, len(chains)))
        for chain in chains:
            gap_fill = len(chains) == 1   # a gap of a split chain is never guessed
            for rk in range(1, max(chain.values())):
                if rk in chain.values():
                    continue
                cands = [s for s in by_name[key[1]][rk] if s not in members] if gap_fill else []
                if len(cands) == 1:
                    chain[cands[0]] = rk
                    notes["gap filled"].append("%s: rank %d = %d" % (label, rk, cands[0]))
                else:
                    notes["gap left"].append("%s: rank %d (%d candidates)" % (label, rk, len(cands)))
            if len(chains) == 1 and len({normalized(spell[s].get("Description_lang")) for s in chain}) > 1:
                notes["review: descriptions differ"].append(label)
            kept.append((key, sorted(chain, key=lambda s: (chain[s], s)), chain))

    lines = [
        "-- Data/SpellRanks.lua: GENERATED by Tools/gen_ranks.py from the client's",
        "-- SkillLine, SkillLineAbility, Spell, SpellName and SpellLevels tables",
        "-- (build %s, wago.tools). Do not edit: re-run the script after a new build," % build,
        "-- and see Tools/ranks/report.txt for what it dropped, filled and excluded.",
        "-- Every class spell that comes in ranks. ranks[spellID] = { group, rank, level };",
        "-- groups[group] = its spell IDs, lowest rank first. The low spell ranks pearl",
        "-- (#12) compares these IDs only; the names below are comments.",
        "",
        "GlassPearls = GlassPearls or {}",
        "GlassPearls.SpellRankData = {",
        "    build = \"%s\"," % build,
        "    groups = {",
    ]
    for g, (key, ids, _) in enumerate(kept, 1):
        lines.append("        { %s },   -- %d %s (%s)" % (", ".join(map(str, ids)), g, key[1], class_lines[key[0]]))
    lines += ["    },", "    ranks = {"]
    for g, (_, ids, members) in enumerate(kept, 1):
        for sid in ids:
            lines.append("        [%d] = { %d, %d, %d }," % (sid, g, members[sid], level.get(sid, 0)))
    lines += ["    },", "}"]
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    report.append("%d groups written" % len(kept))
    for title in ("excluded (Tools/ranks/exclude.csv)", "split by description", "same spell, two IDs at one rank", "gap filled",
                  "gap left", "review: descriptions differ"):
        report += ["", "%s (%d)" % (title, len(notes[title]))] + ["  " + n for n in notes[title]]
    with open(REPORT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print("%d rank groups from build %s -> %s" % (len(kept), build, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
