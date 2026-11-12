-- Paladin tank reminders (#22): only a paladin who knows Righteous Fury (other
-- classes register nothing), the shield gate and its option, hidden in combat
-- and back after, the three answers ("off" needs both Fury IDs proven absent;
-- unknown changes nothing), the death reset, the "ends in" heads-up (gone at 0
-- without claiming "off"), no Salvation reminder (#98: the client removed it;
-- its IDs never read), no client sound, the client's names (French), the
-- commands, the panel, off.
-- tests/test_paladintank_glass.lua runs it again under Glass UI's glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local glass = arg and arg[1] == "glass"
if glass then
    WoW.installGlassUI({ look = { tint = "smoked", accent = "gold" },
        body = { tint = { 0.1, 0.1, 0.12, 0.8 }, backing = { 0, 0, 0, 0.5 }, wash = 0.5 },
        accent = { 0.9, 0.7, 0.2 } })
end
-- A French paladin tank: the client's own names.
WoW.class = "PALADIN"
WoW.spells[25780] = { name = "Fureur vertueuse", icon = 135962 }
WoW.spells[407627] = { name = "Fureur vertueuse", icon = 135962 }
WoW.spells[1038] = { name = "Salut", icon = 135967 }
WoW.spells[25895] = { name = "Salut collectif", icon = 135967 }
WoW.known[25780] = true
WoW.stats.shield = true
local GP = loadAddon()
local T, P = GP.PaladinTank, GP.Pearls
eq(GP.Theme.Active(), glass and "glass" or "forever", "the look: " .. (glass and "glass" or "WoW Forever's"))
local function fire(e, ...) WoW.fire(e, ...) end
local function aura() fire("UNIT_AURA", WoW.Secret("unit"), WoW.Secret("info")) end
local function texts()
    local f, out = T.Frame(), {}
    if not (f and f:IsShown()) then return "" end
    for _, r in ipairs(f.rows) do if r.text:IsShown() then out[#out + 1] = r.text:GetText() end end
    return table.concat(out, " | ")
end

check(P.IsLive("paladintank"), "on by default")
-- No Righteous Fury on a tank: "is off", in the client's language.
eq(texts(), "Fureur vertueuse is off", "Fury off, out of combat: the reminder, by the client's name")
-- Fury present: gone.
WoW.now = 100
WoW.auras[25780] = { expirationTime = 1900, duration = 1800 }
aura()
eq(texts(), "", "Fury present: nothing")
-- One Fury ID unknown: "off" needs both proven absent.
WoW.auras[25780] = nil
WoW.spellAuraSecret[407627] = true
aura()
eq(texts(), "", "one ID absent, the other unknown: not claimed off (last observed: present)")
WoW.spellAuraSecret[407627] = nil
aura()
eq(texts(), "Fureur vertueuse is off", "both proven absent: off")
-- Unknown changes nothing either way.
WoW.auras[25780] = WoW.Secret("aura")
aura()
eq(texts(), "Fureur vertueuse is off", "unknown after absent: still off (last observed)")
WoW.auras[25780] = { expirationTime = 2000, duration = 1800 }
aura()
WoW.auras[25780] = WoW.Secret("aura")
aura()
eq(texts(), "", "unknown after present: still nothing")
-- The heads-up, and its end.
WoW.auras[25780] = { expirationTime = 150, duration = 1800 }
WoW.now = 100
aura()
eq(texts(), "Fureur vertueuse ends in 0:50", "under a minute left: the heads-up")
WoW.now = 140
WoW.tick()
eq(texts(), "Fureur vertueuse ends in 0:10", "  its clock ticks")
WoW.now = 151
WoW.tick()
eq(texts(), "", "  at 0 it just goes: Fury isn't claimed off before a read says so")
WoW.auras[25780] = nil
aura()
eq(texts(), "Fureur vertueuse is off", "  the next read decides: off")
P.SetSetting("paladintank", "rfSoon", false)
WoW.auras[25780] = { expirationTime = 180, duration = 1800 }
WoW.now = 150
aura()
eq(texts(), "", "heads-up switched off: nothing")
P.ResetSettings("paladintank")

-- No Salvation reminder (#98): the client removed Salvation (1038) and Mass
-- Salvation (25895) in 70862. Even with one on you, nothing reads or says it.
WoW.now = 1000
WoW.auras[25780] = { expirationTime = 2800, duration = 1800 }
WoW.auras[1038] = { expirationTime = 4570, duration = 3600, sourceUnit = "party2" }
WoW.auras[25895] = { expirationTime = 4600, duration = 3600, sourceUnit = "player" }
WoW.auraReads[1038], WoW.auraReads[25895] = nil, nil
aura()
eq(texts(), "", "Fury on, a Salvation aura on you: nothing (no Salvation reminder)")
eq((WoW.auraReads[1038] or 0) + (WoW.auraReads[25895] or 0), 0, "  Salvation's IDs are never read")
WoW.auras[25780] = nil
aura()
eq(texts(), "Fureur vertueuse is off", "Fury gone, Salvation still there: only Fury's reminder")
WoW.auras[1038], WoW.auras[25895] = nil, nil
-- The clock rounds to the nearest second.
eq(T.Clock(49.6), "0:50", "the clock rounds (49.6 s: 0:50)")
eq(T.Clock(3570.4), "59:30", "  and shows minutes")
eq(T.Clock(-3), "0:00", "  never negative")

-- Hidden in combat, back after (and read again then).
WoW.combat = true
fire("PLAYER_REGEN_DISABLED")
eq(texts(), "", "in combat: hidden")
WoW.combat = false
fire("PLAYER_REGEN_ENABLED")
eq(texts(), "Fureur vertueuse is off", "after combat: back, read again")
-- A death forgets: read again.
WoW.auras[25780] = WoW.Secret("aura")
fire("PLAYER_DEAD")
eq(texts(), "", "after a death: forgotten; an unknown read shows nothing")
WoW.auras[25780] = nil
fire("PLAYER_ALIVE")
eq(texts(), "Fureur vertueuse is off", "  the next proven read decides")
-- The shield gate.
WoW.stats.shield = false
fire("PLAYER_EQUIPMENT_CHANGED", 17, true)
eq(texts(), "", "no shield: hidden")
P.SetSetting("paladintank", "noShield", true)
eq(texts(), "Fureur vertueuse is off", "'even without a shield': shown")
P.ResetSettings("paladintank")
WoW.stats.shield = true
fire("PLAYER_EQUIPMENT_CHANGED", 17, true)
-- Knowing Fury, through SPELLS_CHANGED.
WoW.known[25780] = nil
fire("SPELLS_CHANGED")
eq(texts(), "", "a paladin without Righteous Fury: nothing")
WoW.known[407627] = true
fire("SPELLS_CHANGED")
eq(texts(), "Fureur vertueuse is off", "the rune variant counts as knowing it")
WoW.known[407627], WoW.known[25780] = nil, true
fire("SPELLS_CHANGED")
-- The switches.
P.SetSetting("paladintank", "rf", false)
eq(texts(), "", "the Fury reminder switched off")
P.ResetSettings("paladintank")

-- No client sound, no name compared.
local sounds = 0
for _, s in pairs(WoW.auraSounds) do
    if s.info.spellID == 25780 or s.info.spellID == 407627 then sounds = sounds + 1 end
end
eq(sounds, 0, "no client sound registered (they can't follow these gates)")
local src = io.open("Pearls/PaladinTank.lua"):read("*a"):gsub("%-%-[^\n]*", "")
for _, name in ipairs({ "Righteous Fury", "Salvation", "Fureur vertueuse", "Blessing of Salvation" }) do
    check(not src:find('==%s*"' .. name), "no spell name compared in the code: " .. name)
end
check(not src:find("GetAuraDataBySpellName", 1, true) and not src:find("GetSpellInfo(\"", 1, true), "  and no lookup by name")

-- Commands and the panel.
newChat()
SlashCmdList.GLASSPEARLS("paladintank")
local chat = table.concat(newChat(), "\n")
check(chat:find("Fureur vertueuse (25780): absent", 1, true), "/gpearls paladintank: the last reads")
check(not chat:find("(1038)", 1, true) and not chat:find("(25895)", 1, true), "  no Salvation row")
check(chat:find("Cooldown Manager", 1, true), "  and the pointer for combat")
SlashCmdList.GLASSPEARLS("paladintank test")
eq(texts(), "Fureur vertueuse is off", "the test shows the reminder")
eq(T.Frame()._mouse, true, "  draggable")
local pf = T.Frame()
function pf:GetCenter() return 600, 300 end
pf:GetScript("OnDragStop")(pf)
eq(GP.charDB.paladintank and GP.charDB.paladintank.y, 300, "  the drag is saved per character")
WoW.flushTimers(T.TEST_SECONDS)
eq(texts(), "Fureur vertueuse is off", "  after its seconds: back to the real reminders")
GP.Options.Open("cat:Combat")
local row
for _, pl in ipairs(GP.Options._test.pages["cat:Combat"].placed) do if pl.key == "paladintank" then row = pl.row end end
row.gear:GetScript("OnClick")(row.gear)
local content = GP.Options._test.pages["config:paladintank"].frame._children[1]
local checks = {}
for _, w in ipairs(content._children) do if w._template == "UICheckButtonTemplate" then checks[#checks + 1] = w end end
eq(#checks, 3, "three switches (no Salvation)")
checks[3]:SetChecked(true)
checks[3]:GetScript("OnClick")(checks[3])
eq(P.Setting("paladintank", "noShield"), true, "the third: even without a shield")
P.ResetSettings("paladintank")
eq(P.Setting("paladintank", "salv"), nil, "the Salvation setting is gone")
GP.Options._test.win():Hide()

-- Off.
SlashCmdList.GLASSPEARLS("paladintank off")
eq(texts(), "", "off: hidden")
aura()
eq(texts(), "", "  and nothing reads")
SlashCmdList.GLASSPEARLS("paladintank on")
eq(texts(), "Fureur vertueuse is off", "back on")

done("test_paladintank" .. (glass and " (glass)" or ""))
