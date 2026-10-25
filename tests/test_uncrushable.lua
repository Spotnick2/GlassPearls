-- "Uncrushable" (#19): the math against hand-worked cases (Blizzard's Forever
-- constants), the macro's error, secrets, the shield gate, the line in the
-- stats pane's footer (addon-owned, Blizzard's frame untouched), the refresh
-- (hook and events, payloads untouched), the tooltip, the command, off.
-- tests/test_uncrushable_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
WoW.playerLevel = 60
-- Blizzard's pane, as the client builds it: note its own fields before we load.
local pane = CharacterStatsPaneScrollBox
local before = {}
for k in pairs(pane) do before[k] = true end

local GP = loadAddon()
local U, P = GP.Uncrushable, GP.Pearls
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function set(t) for k, v in pairs(t) do WoW.stats[k] = v end end

check(P.IsLive("uncrushable"), "on by default")
eq(P.Get("uncrushable").category, "Combat", "on the Combat page")

-- A: defense at the cap (300), level 60, a shield: short.
set({ defense = { 300, 0 }, dodge = 20, parry = 15, block = 30, shield = true })
local c = U.Compute()
check(near(c.miss, 4.4), "A: miss against a +3 boss = 5 - 15 x 0.04 = 4.4")
check(near(c.dodge, 19.4) and near(c.parry, 14.4) and near(c.block, 29.4), "A: each 0.6 lower against a boss")
check(near(c.total, 67.6), "A: total 67.6")
check(near(c.short, 32.4) and not c.uncrushable, "A: 32.4% short")
-- B: 140 defense above the cap: uncrushable.
set({ defense = { 300, 140 }, dodge = 30, parry = 25, block = 37 })
c = U.Compute()
check(near(c.miss, 10), "B: miss = 5 + 125 x 0.04 = 10 (defense above the cap counts)")
check(near(c.total, 100.2) and c.uncrushable, "B: 100.2%: uncrushable")
eq(c.short, 0, "B: nothing short")
-- The macro on B: dodge + block + parry + 5 + (rating 0 + 20) x 0.04 = 97.8 < 102.4.
check(near(U.MacroTotal(), 97.8), "the macro reads 97.8 for B (ratings are 0 here)")
check(U.MacroTotal() < 102.4, "  and calls an uncrushable tank crushable: its defense term never moves")
-- Exactly 100 (the 102.4 rule on the sheet's numbers): uncrushable.
set({ block = 36.8 })
c = U.Compute()
check(c.uncrushable, "exactly 100% (102.4% on the equal-level numbers): uncrushable")
check(near(10.6 + 30 + 25 + 36.8, 102.4), "  the same tank on the 102.4 rule")
-- Components never below 0; no shield, no block.
set({ defense = { 300, 0 }, dodge = 20, parry = 0, block = 30, shield = false })
c = U.Compute()
eq(c.parry, 0, "parry 0 stays 0 (never negative)")
eq(c.block, 0, "no shield: block counts 0")
check(not c.shield, "  and says so")
set({ dodge = 0.3 })
eq(U.Compute().dodge, 0, "dodge under 0.6 stays 0")
-- Level 40: the same 15-point gap.
WoW.playerLevel = 40
set({ defense = { 200, 0 }, dodge = 10, parry = 10, block = 10, shield = true })
c = U.Compute()
check(near(c.miss, 4.4), "level 40: miss 4.4 too (the gap is 15 at any level)")
WoW.playerLevel = 60
-- Effective defense never below 0; miss clamped.
set({ defense = { 0, -50 } })
check(U.Compute().miss >= 0, "miss is clamped at 0")
eq(U.Compute().defense, 0, "effective defense never below 0")
-- Secrets and junk: unreadable, never a number.
for _, k in ipairs({ "dodge", "parry", "block" }) do
    local was = WoW.stats[k]
    WoW.stats[k] = WoW.Secret(k)
    local r, why = U.Compute()
    check(r == nil and why == "unreadable", "a secret " .. k .. ": unreadable")
    WoW.stats[k] = was
end
WoW.stats.defense = { 300, WoW.Secret("mod") }
check(U.Compute() == nil, "a secret defense modifier: unreadable")
WoW.stats.defense = { 300, 0 }
WoW.stats.shield = WoW.Secret("shield")
check(U.Compute() == nil, "a secret shield answer: unreadable")
WoW.stats.shield = true
local realDodge = GetDodgeChance
GetDodgeChance = function() error("x") end
check(U.Compute() == nil, "a failing call: unreadable")
GetDodgeChance = realDodge

-- The line: in the stats pane's footer, addon-owned.
set({ defense = { 300, 140 }, dodge = 30, parry = 25, block = 37, shield = true })
pane:Show()
PaperDollFrame_UpdateStats()
local line = U._test.line()
check(line ~= nil and line:GetParent() == pane, "the line is ours, in Forever's stats pane")
local p1, p2 = line._points[1], line._points[2]
check(p1[1] == "BOTTOMLEFT" and p1[2] == pane and p2[1] == "BOTTOMRIGHT" and p2[2] == pane, "  in its footer")
check(WoW.hooked[_G] and WoW.hooked[_G].PaperDollFrame_UpdateStats, "refreshed through a secure hook")
check(line:IsShown(), "shown with a shield")
eq(line.text:GetText(), "Uncrushable (100.20%)", "  'Uncrushable' with the total")
local r, g = line.text:GetTextColor()
check(g == 1 and r < 0.5, "  in green")
set({ block = 30 })
PaperDollFrame_UpdateStats()
eq(line.text:GetText(), "Crushable: 6.80% short", "the hook refreshes it: 'Crushable: 6.80% short'")
r, g = line.text:GetTextColor()
check(r == 1 and g < 1, "  in orange")
set({ block = 37 })
WoW.fire("UNIT_STATS", WoW.Secret("unit"))
eq(line.text:GetText(), "Uncrushable (100.20%)", "UNIT_STATS refreshes it, its payload untouched")
WoW.fire("UNIT_AURA", WoW.Secret("unit"), WoW.Secret("info"))
check(line:IsShown(), "UNIT_AURA too (Shield Block raises block), payload untouched")
-- Blizzard's pane carries no field of ours.
local written = {}
for k in pairs(pane) do
    if not before[k] and not tostring(k):match("^_") then written[#written + 1] = tostring(k) end
end
eq(#written, 0, "no field written onto Blizzard's pane (" .. table.concat(written, ",") .. ")")
-- The shield gate, and "always".
set({ shield = false })
PaperDollFrame_UpdateStats()
check(not line:IsShown(), "no shield: hidden")
P.SetSetting("uncrushable", "always", true)
check(line:IsShown(), "'always': shown without a shield (applied at once)")
P.ResetSettings("uncrushable")
check(not line:IsShown(), "  back off: hidden")
set({ shield = true })
-- Unreadable: said, never a number; "in combat" only when in combat.
WoW.stats.dodge = WoW.Secret("dodge")
PaperDollFrame_UpdateStats()
eq(line.text:GetText(), "Uncrushable: stats unavailable", "unreadable: said, no number")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
eq(line.text:GetText(), "Uncrushable: stats unavailable in combat", "  'in combat' only when in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.stats.dodge = 30

-- The tooltip.
PaperDollFrame_UpdateStats()
line:GetScript("OnEnter")(line)
local tip = table.concat(GameTooltip._lines, "\n")
check(tip:find("Against a level 63 attacker", 1, true), "the tooltip: against a level 63 attacker")
check(tip:find("Miss|10.00%", 1, true) and tip:find("Dodge|29.40%", 1, true), "  miss and dodge against it")
check(tip:find("Parry|24.40%", 1, true) and tip:find("Block|36.40%", 1, true), "  parry and block")
check(tip:find("Total|100.20%", 1, true) and tip:find("Needs|100.00%", 1, true), "  total and need")
check(tip:find("pushed off the table", 1, true), "  crushing blows off the table")
check(not tip:find("%d+%.%d+%% chance", 1) , "  and no crushing percentage claimed")
set({ block = 30 })
line:GetScript("OnEnter")(line)
check(table.concat(GameTooltip._lines, "\n"):find("6.80% short of pushing crushing blows off the table", 1, true),
    "short: how far, not a crush chance")

-- The command (the macro's replacement).
newChat()
SlashCmdList.GLASSPEARLS("uncrushable")
local chat = table.concat(newChat(), "\n")
check(chat:find("Crushable: 6.80% short", 1, true) and chat:find("Total: 93.20%", 1, true), "/gpearls uncrushable prints it")
set({ block = 37 })

-- Off: hidden, events and the hook do nothing, the command says so.
SlashCmdList.GLASSPEARLS("uncrushable off")
check(not line:IsShown(), "off: hidden")
set({ block = 30 })
PaperDollFrame_UpdateStats()
WoW.fire("UNIT_STATS", "player")
check(not line:IsShown(), "  the hook and events do nothing")
newChat()
SlashCmdList.GLASSPEARLS("uncrushable")
check(table.concat(newChat(), "\n"):find("is off", 1, true), "  the command says it's off")
SlashCmdList.GLASSPEARLS("uncrushable on")
check(line:IsShown(), "back on: shown again")

done("test_uncrushable" .. (glass and " (glass)" or ""))
