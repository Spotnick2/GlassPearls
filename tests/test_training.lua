-- Training reminder (#27): the level-up toast (new, waiting, a level jump,
-- nothing to say, combat hold, a run of level-ups as one toast, learning
-- refreshes it, waiting off), what is
-- learnable (requirements, talents, override and rank groups, unknown reads
-- never listed, race, faction, skill), talent points (plain and sane only),
-- the other spec as last seen, the tooltip lines and hook, the commands, the
-- panel, off. tests/test_training_glass.lua runs it again under Glass UI.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
-- A French paladin at level 5 who knows Devotion Aura 1 and Holy Light 1.
WoW.class = "PALADIN"
WoW.playerLevel = 5
WoW.known[465], WoW.known[635] = true, true
WoW.spells[639] = { name = "Lumière sacrée", icon = 135920 }
WoW.spells[1311606] = { name = "Horion sacré", icon = 135972 }
WoW.spells[20473] = { name = "Horion sacré", icon = 135972 }
local GP = loadAddon()
local T, P, F = GP.Training, GP.Pearls, GP.TrainingFrame
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))

local function ids(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.id end
    return table.concat(out, ",")
end
local function view() return F.IsShown() and F.Get().view or nil end
local function levelUp(to, payload)
    WoW.playerLevel = to
    WoW.fire("PLAYER_LEVEL_UP", payload == nil and to or payload)
    WoW.flushTimers(T.LEVEL_DELAY)
end
local function spellsChanged()
    WoW.fire("SPELLS_CHANGED")
    WoW.flushTimers(T.REMEMBER_DELAY)
end
local function labels()
    local out = {}
    for _, l in ipairs(F.Get().labels) do if l:IsShown() then out[#out + 1] = l:GetText() end end
    return table.concat(out, " | ")
end

check(P.IsLive("training"), "on by default")
eq(#(WoW.tooltipPostCalls[Enum.TooltipDataType.Spell] or {}), 1, "one spell tooltip post call")
check(not F.IsShown(), "no toast at login")

-- Level 6: new at the trainer, and what was already waiting.
WoW.playerLevel = 6
WoW.fire("PLAYER_LEVEL_UP", 6)
check(not F.IsShown(), "not before its short delay")
WoW.flushTimers(T.LEVEL_DELAY)
check(F.IsShown(), "level 6: the toast")
eq(ids(view().new), "498,639,679,21082", "  new: the level-6 spells (Holy Light 2 needs Holy Light 1: known)")
eq(ids(view().waiting), "19740,20271", "  waiting: the level-4 spells not learned")
eq(view().cost, 600, "  their cost")
eq(F.Get().title:GetText(), "Level 6", "  its title")
eq(F.Get().icons.big[2].rank:GetText(), 2, "  the rank in the icon's corner (Holy Light 2)")
check(labels():find("New at your trainer", 1, true) and labels():find("Also waiting", 1, true), "  its two rows")
check(labels():find("About 600c at the trainer", 1, true), "  the cost line")
P.SetSetting("training", "cost", false)
check(not labels():find("About", 1, true), "  the cost switch off: no cost line")
P.ResetSettings("training")
-- Learning one refreshes it.
WoW.known[498] = true
spellsChanged()
eq(ids(view().new), "639,679,21082", "learned at the trainer: gone from the toast")
-- Waiting off.
P.SetSetting("training", "waiting", false)
eq(ids(view().waiting), "", "'also waiting' switched off: only the new ones")
P.ResetSettings("training")
F.Hide()

-- What is learnable.
local ctx = T.Context(6)
local entry = function(id) for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do if e.id == id then return e end end end
eq(T.Status(entry(639), ctx), "available", "Holy Light 2: available")
WoW.known[635] = nil
eq(T.Status(entry(639), T.Context(6)), "req", "  without Holy Light 1: a missing requirement, not listed")
WoW.known[635] = true
eq(T.Status(entry(853), T.Context(6)), "later", "Hammer of Justice at level 6: later")
WoW.knownSecret[679] = true
eq(T.Status(entry(679), T.Context(6)), "unknown", "a secret read: can't tell, never listed")
WoW.knownSecret[679] = nil
WoW.knownSecret[635] = true
eq(T.Status(entry(639), T.Context(6)), "unknown", "  a secret read of a requirement: can't tell")
WoW.knownSecret[635] = nil
-- A later member of an override group, or a higher rank, means it's learned.
WoW.known[465], WoW.known[10290] = nil, true
eq(T.Status(entry(465), T.Context(10)), "known", "Devotion Aura 2 known: rank 1 counts as learned")
WoW.known[465], WoW.known[10290] = true, nil
WoW.known[647] = true
eq(T.Status(entry(639), T.Context(14)), "known", "Holy Light 3 known: rank 2 counts as learned")
WoW.known[647] = nil
-- Race, faction, skill.
eq(T.Status({ id = 1, level = 1, cost = 0, race = 3 }, T.Context(6)), nil, "another race's spell: not for you")
eq(T.Status({ id = 1, level = 1, cost = 0, faction = "Horde" }, T.Context(6)), nil, "the other faction's: not for you")
eq(T.Status({ id = 1, level = 1, cost = 0, faction = "Alliance" }, T.Context(6)), "available", "  your faction's: yes")
eq(T.Status({ id = 1, level = 1, cost = 0, skill = { { 40, 1 } } }, T.Context(6)), "skill", "a skill requirement: never listed")
-- A talent's ranks.
WoW.playerLevel = 45
eq(T.Status(entry(20473), T.Context(45)), "talent", "Holy Shock 2 without the talent: not listed")
WoW.known[1311606] = true
eq(T.Status(entry(20473), T.Context(45)), "available", "  with it: available")
WoW.knownSecret[1311606] = true
eq(T.Status(entry(20473), T.Context(45)), "unknown", "  the talent read secret: can't tell")
WoW.knownSecret[1311606] = nil
-- A rogue's poisons: a later member of an override group means it's learned
-- (the one group the rank groups don't cover).
WoW.class = "ROGUE"
local poison
for _, e in ipairs(GP.TrainingData.classes.ROGUE.spells) do if e.id == 8687 then poison = e end end
WoW.known[8691] = true
eq(T.Status(poison, T.Context(36)), "known", "Instant Poison II known: I counts as learned (override group)")
WoW.known[8691] = nil
WoW.class = "PALADIN"

-- A level jump: only the levels passed (4 to 8: 6 and 8 are new; a level-4
-- spell not learned was already waiting).
for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
    if e.level <= 4 and e.id ~= 20271 then WoW.known[e.id] = true end
end
WoW.known[1311606], WoW.known[498] = nil, nil
T.state.level = 4
levelUp(8)
eq(ids(view().new), "498,639,679,21082,853,1152,3127", "4 to 8 at once: levels 6 and 8 are new")
eq(ids(view().waiting), "20271", "  the level-4 one not learned was already waiting")
F.Hide()
for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
    if e.level <= 8 then WoW.known[e.id] = true end
end
-- A secret payload: the level is read again.
T.state.level = 8
WoW.playerLevel = 8
WoW.fire("PLAYER_LEVEL_UP", WoW.Secret("level"))
WoW.flushTimers(T.LEVEL_DELAY)
eq(T.state.level, 8, "a secret level in the event: UnitLevel's")
F.Hide()

-- Nothing to say: no toast.
for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
    if e.level <= 9 then WoW.known[e.id] = true end
end
levelUp(9)
check(not F.IsShown(), "nothing to learn: no toast")
-- Talent points alone are worth a toast; only plain, sane counts.
WoW.talentPoints = 1
levelUp(9)
check(F.IsShown() and view().points == 1, "a talent point to spend: the toast")
check(labels():find("1 talent point to spend", 1, true), "  says so")
F.Hide()
eq(T.TalentPoints(), 1, "the client's count")
WoW.talentPoints = WoW.Secret("points")
eq(T.TalentPoints(), nil, "  a secret: no count")
WoW.talentPoints = 52
eq(T.TalentPoints(), nil, "  more than 51: not believed")
WoW.talentPoints = 1.5
eq(T.TalentPoints(), nil, "  not whole: not believed")
WoW.talentPoints = nil
eq(T.TalentPoints(), nil, "  no currency: no count")
WoW.talentPoints = 0
levelUp(9)
check(not F.IsShown(), "  zero points: no toast")
WoW.talentPoints = nil

-- In combat: held until it ends.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
levelUp(10)
check(not F.IsShown(), "levelled in combat: held")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(F.IsShown(), "  shown when combat ends")
check(view().new[1] and view().new[1].level == 10, "  with the level-10 spells")
F.Hide()
-- The toast goes by itself, unless the mouse is on it.
levelUp(10)
local tf = F.Get()
function tf:IsMouseOver() return true end
WoW.flushTimers(F.SECONDS)
check(F.IsShown(), "the mouse on it: it stays")
function tf:IsMouseOver() return false end
WoW.flushTimers(5)
check(not F.IsShown(), "  then goes")

-- A run of level-ups is one toast whose spells all stay new: within the
-- delay, held in combat, or while the toast is open. Also with "also waiting"
-- off, where a spell counted as waiting would vanish.
local function knowUpTo(level)
    for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
        if e.level <= level then WoW.known[e.id] = true end
    end
end
local function firstAt(level)
    for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
        if e.level == level and not (e.talent or e.race or e.faction) then return e.id end
    end
end
local function has(list, id)
    for _, e in ipairs(list) do if e.id == id then return true end end
    return false
end
P.SetSetting("training", "waiting", false)
knowUpTo(10)
T.state.level = 10
local shows, show = 0, T.Show
T.Show = function(...) shows = shows + 1; return show(...) end
WoW.playerLevel = 12
WoW.fire("PLAYER_LEVEL_UP", 12)
WoW.playerLevel = 14
WoW.fire("PLAYER_LEVEL_UP", 14)
WoW.flushTimers(T.LEVEL_DELAY)
T.Show = show
eq(shows, 1, "two level-ups within the delay: one toast")
check(has(view().new, firstAt(12)) and has(view().new, firstAt(14)), "  one toast: levels 12 and 14 both new")
eq(F.Get().title:GetText(), "Level 14", "  titled with the latest level")
F.Hide()
knowUpTo(14)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
levelUp(16)
levelUp(18)
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(has(view().new, firstAt(16)) and has(view().new, firstAt(18)), "two level-ups in combat: both new after it")
eq(F.Get().title:GetText(), "Level 18", "  titled with the latest level")
F.Hide()
knowUpTo(18)
levelUp(20)
levelUp(22)
check(has(view().new, firstAt(20)) and has(view().new, firstAt(22)), "a level-up while the toast is open: it grows")
F.Get():Hide()   -- Esc (UISpecialFrames), not our OK; the level-22 spells left unlearned
levelUp(24)
check(not has(view().new, firstAt(22)), "  a toast closed with Esc isn't extended")
F.Hide()
knowUpTo(24)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
levelUp(26)
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 1)
WoW.flushTimers(T.SWAP_DELAY)
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(view() and view().kind == "level" and has(view().new, firstAt(26)), "a swap held after a level-up: the level-up's toast")
F.Hide()
knowUpTo(26)
WoW.playerLevel = 28
WoW.fire("PLAYER_LEVEL_UP", 28)
P.Set("training", false)
P.Set("training", true)
WoW.flushTimers(T.LEVEL_DELAY)
check(not F.IsShown(), "a level-up before the pearl went off and on: forgotten")
P.ResetSettings("training")

-- The other spec, as last seen.
for _, e in ipairs(GP.TrainingData.classes.PALADIN.spells) do
    if e.level <= 45 and not e.talent and not e.race and not e.faction then WoW.known[e.id] = true end
end
WoW.playerLevel = 45
T.state.level = 45
WoW.known[1311606] = true          -- spec 1 talented Holy Shock
spellsChanged()
WoW.specGroup, WoW.known[1311606] = 2, nil
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
WoW.flushTimers(T.SWAP_DELAY)
check(F.IsShown() and view().kind == "swap", "a spec swap: the toast")
eq(#view().other, 1, "  the other spec's talent")
eq(ids(view().other[1].spells), "20473", "  its waiting rank (Holy Shock 2 at 40)")
check(labels():find("Your other spec: Horion sacré 1 (rank 2), as last seen", 1, true), "  says it: " .. labels())
F.Hide()
-- Learned in spec 1: gone.
WoW.specGroup, WoW.known[1311606], WoW.known[20473] = 1, true, true
spellsChanged()
WoW.specGroup, WoW.known[1311606], WoW.known[20473] = 2, nil, nil
spellsChanged()
eq(#T.OtherSpec(T.Context(45)), 0, "the rank learned in that spec: nothing waits")
-- Back in spec 1 with the rank not learned: the swap toast's new ones are
-- its talent ranks, and spec 1's own record is never "the other spec".
WoW.specGroup, WoW.known[1311606], WoW.known[20473] = 1, true, nil
spellsChanged()
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
WoW.flushTimers(T.SWAP_DELAY)
eq(ids(view().new), "20473", "swapped to the talented spec: its talent rank is new")
eq(#view().other, 0, "  and its own record isn't the other spec")
F.Hide()
-- A group never seen active says nothing.
GP.charDB.training = nil
eq(#T.OtherSpec(T.Context(45)), 0, "no record of the other spec: nothing")
WoW.specGroup = 1
WoW.known[1311606], WoW.known[20473] = true, true
spellsChanged()

-- The tooltip.
local tip = WoW.spellTooltip(20473)
check(tip:find("Next rank: 3 at 48 (then 4 at 56)", 1, true), "Holy Shock 2 at 45: its next ranks: " .. tip)
WoW.playerLevel = 50
tip = WoW.spellTooltip(20473)
check(tip:find("Rank 3: at your trainer now", 1, true) and tip:find("Next rank: 4 at 56", 1, true),
    "at 50: rank 3 waits at the trainer, 4 comes at 56")
WoW.known[1311606], WoW.known[20473] = nil, nil
tip = WoW.spellTooltip(1311606)
check(tip:find("Rank 2 needs Horion sacré", 1, true), "without the talent: the rank needs it: " .. tip)
WoW.known[1311606], WoW.known[20473] = true, true
eq(WoW.spellTooltip(99999), "spell:99999", "a spell not in your lists: untouched")
eq(WoW.spellTooltip(10293), "spell:10293", "your highest rank: nothing to add")
P.SetSetting("training", "tooltip", false)
eq(WoW.spellTooltip(20473), "spell:20473", "the tooltip switch off: untouched")
P.ResetSettings("training")
GameTooltip:SetOwner(UIParent)
T._test.onTooltip(GameTooltip, { id = WoW.Secret("id") })
eq(#GameTooltip._lines, 0, "a secret spell ID: nothing")
WoW.playerLevel = 45

-- Commands.
newChat()
SlashCmdList.GLASSPEARLS("training")
local chat = table.concat(newChat(), "\n")
check(chat:find("Training reminder, level 45:", 1, true), "/gpearls training: the report")
check(chat:find("At level 46:", 1, true), "  the next trainer level's spells (46)")
SlashCmdList.GLASSPEARLS("training test")
check(F.IsShown() and view().kind == "test", "the test toast")
eq(F.Get().title:GetText(), "Level 45  (test)", "  says it's a test")
local pf = F.Get()
function pf:GetLeft() return 100 end
function pf:GetTop() return 700 end
pf:GetScript("OnDragStop")(pf)
eq(GP.charDB.trainingToast and GP.charDB.trainingToast.y, 700, "  the drag is saved per character")
WoW.flushTimers(F.TEST_SECONDS)
check(not F.IsShown(), "  gone after its seconds")

-- The panel.
GP.Options.Open("cat:Combat")
local row
for _, pl in ipairs(GP.Options._test.pages["cat:Combat"].placed) do if pl.key == "training" then row = pl.row end end
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:training"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end end
eq(#checks, 6, "six switches")
checks[1]:SetChecked(false)
checks[1]:GetScript("OnClick")(checks[1])
eq(P.Setting("training", "toast"), false, "the first: the level-up toast")
WoW.known[20929] = nil
levelUp(48)
check(not F.IsShown(), "  off: no toast")
P.ResetSettings("training")
GP.Options._test.win():Hide()

-- Off.
levelUp(48)
check(F.IsShown(), "a toast")
SlashCmdList.GLASSPEARLS("training off")
check(not F.IsShown(), "off: hidden")
levelUp(48)
check(not F.IsShown(), "  no toast")
eq(WoW.spellTooltip(20473), "spell:20473", "  no tooltip lines")
SlashCmdList.GLASSPEARLS("training on")
check(WoW.spellTooltip(20473):find("at your trainer now", 1, true), "back on: the tooltip again")
eq(#WoW.tooltipPostCalls[Enum.TooltipDataType.Spell], 1, "  still one post call (it can't be removed, never added twice)")

-- The generated data.
local classes = 0
for class, d in pairs(GP.TrainingData.classes) do
    classes = classes + 1
    local ok = #d.spells > 50
    for _, e in ipairs(d.spells) do
        if type(e.id) ~= "number" or type(e.level) ~= "number" or type(e.cost) ~= "number" or e.level < 1 or e.level > 60 then ok = false end
    end
    check(ok, "Data/Training.lua: " .. class .. "'s entries are well formed")
end
eq(classes, 9, "  nine classes")

done("test_training" .. (glass and " (glass)" or ""))
