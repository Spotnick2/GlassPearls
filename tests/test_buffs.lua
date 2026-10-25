-- Buff alerts (#21): the entries and their defaults, the client's sounds (per
-- entry and switch), an aura read (exact time, "from <name>"), Blizzard's
-- overlay (approximate "~" time, HIDE, a HIDE without an ID, secret or
-- unlisted IDs), combat (unknown reads keep it, the countdown runs on),
-- expiry, switches, UNIT_AURA's payload untouched, the client's names (German),
-- the commands, off, and the fixate alert alongside (independent state and
-- frames that never overlap at any size).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DE = { [12536] = "Freizaubern", [16870] = "Freizaubern", [29166] = "Anregen", [10060] = "Seele der Macht",
             [1022] = "Segen des Schutzes", [6940] = "Segen der Opferung", [1044] = "Segen der Freiheit" }
for id, name in pairs(DE) do WoW.spells[id] = { name = name, icon = 136000 + id % 1000 } end
local GP = loadAddon()
local B, P, BF = GP.Buffs, GP.Pearls, GP.BuffsFrame
local function drain() for _ = 1, 30 do if #WoW.timers == 0 then return end WoW.flushTimers() end end
local function frame() return BF._test.frame() end
local function slots()
    local out = {}
    local f = frame()
    if not (f and f:IsShown()) then return out end
    for _, s in ipairs(f.slots) do if s:IsShown() then out[#out + 1] = s end end
    return out
end
local function fireAura() WoW.fire("UNIT_AURA", WoW.Secret("unit"), WoW.Secret("info")); drain() end

check(P.IsLive("buffs"), "on by default")
eq(P.Get("buffs").category, "Combat", "on the Combat page")
-- Sounds: every entry with its sound on (Clearcasting off: frequent).
local registered = {}
for _, s in pairs(WoW.auraSounds) do registered[s.info.spellID] = true end
check(not registered[12536] and not registered[16870], "Clearcasting's sound off by default")
for _, id in ipairs({ 29166, 456195, 10060, 1022, 5599, 10278, 442948, 6940, 20729, 1044 }) do
    check(registered[id], "the client's sound for " .. id)
end

-- An aura read: Innervate from another player, with its exact time left.
WoW.now = 100
WoW.auras[29166] = { expirationTime = 120, duration = 20, sourceUnit = "party1" }
WoW.unitNames.party1 = "Elune"
fireAura()
local s = slots()
eq(#s, 1, "Innervate: one alert")
eq(s[1].name:GetText(), "Anregen", "  the client's own name (German)")
eq(s[1].from:GetText(), "from Elune", "  who gave it")
eq(s[1].time:GetText(), "20", "  its exact time left")
WoW.now = 112.5
WoW.tick()
eq(s[1].time:GetText(), "7.5", "  counting down, in tenths under 10 s")
-- Self-cast: no "from".
WoW.auras[29166].sourceUnit = "player"
fireAura()
eq(slots()[1].from:GetText(), "", "self-cast: no 'from'")
-- Combat: unknown reads keep it, the countdown runs on.
WoW.auras[29166] = WoW.Secret("aura")
fireAura()
eq(#slots(), 1, "in combat, unknown: still shown")
WoW.now = 115
WoW.tick()
eq(slots()[1].time:GetText(), "5.0", "  its countdown still running (arithmetic)")
WoW.now = 121
drain()
fireAura()
eq(#slots(), 0, "its own expiration passed: gone")
WoW.auras[29166] = nil

-- The overlay: Clearcasting shown by Blizzard's proc overlay alone, an approximate time.
WoW.now = 200
WoW.spellAuraSecret[16870] = true      -- its aura unreadable (combat)
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 16870, 123, "CENTER", 1, 255, 255, 255)
s = slots()
eq(#s, 1, "an overlay alone shows Clearcasting")
eq(s[1].name:GetText(), "Freizaubern", "  by its client name")
eq(s[1].time:GetText(), "~15", "  with an approximate time ('~', the client's 15 s)")
WoW.fire("SPELL_ACTIVATION_OVERLAY_HIDE", 16870)
eq(#slots(), 0, "its HIDE: gone (consumed)")
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 16870, 123, "CENTER", 1, 255, 255, 255)
WoW.fire("SPELL_ACTIVATION_OVERLAY_HIDE")
eq(#slots(), 0, "a HIDE without an ID: every overlay hidden")
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", WoW.Secret("id"), 1, "CENTER", 1, 1, 1, 1)
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 99999, 1, "CENTER", 1, 1, 1, 1)
eq(#slots(), 0, "a secret or unlisted ID: ignored")
WoW.spellAuraSecret[16870] = nil
-- Two at once, side by side.
WoW.now = 300
WoW.auras[10060] = { expirationTime = 315, duration = 15 }
WoW.auras[1044] = { expirationTime = 310, duration = 10 }
fireAura()
eq(#slots(), 2, "two buffs: two slots")
-- An entry switched off: not shown, its sounds removed.
P.SetSetting("buffs", "freedom", false)
eq(#slots(), 1, "Freedom switched off: hidden")
registered = {}
for _, x in pairs(WoW.auraSounds) do registered[x.info.spellID] = true end
check(not registered[1044], "  its sound removed")
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 1044, 1, "CENTER", 1, 1, 1, 1)
eq(#slots(), 1, "  and its overlay ignored")
P.ResetSettings("buffs")
drain()
eq(#slots(), 2, "back on: shown again")
-- Switched off forgets: an overlay hidden while it was off can't come back stale.
WoW.auras[1044] = nil
WoW.spellAuraSecret[1044] = true
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 1044, 1, "CENTER", 1, 1, 1, 1)
P.SetSetting("buffs", "freedom", false)
WoW.fire("SPELL_ACTIVATION_OVERLAY_HIDE", 1044)   -- arrives while it's off: ignored
P.ResetSettings("buffs")
drain()
eq(#slots(), 1, "switched back on: its old overlay evidence is gone, not shown stale")
WoW.spellAuraSecret[1044] = nil
WoW.auras[1044] = { expirationTime = 310, duration = 10 }
fireAura()
check(B._test.events._units and B._test.events._units.UNIT_AURA[1] == "player", "UNIT_AURA registered for the player only")
-- A sound switch alone.
P.SetSetting("buffs", "clearcastingSound", true)
registered = {}
for _, x in pairs(WoW.auraSounds) do registered[x.info.spellID] = true end
check(registered[12536] and registered[16870], "Clearcasting's sound on: registered")
P.ResetSettings("buffs")
WoW.auras[10060], WoW.auras[1044] = nil, nil
fireAura()
eq(#slots(), 0, "both gone")
-- The alert switched off: nothing shown, still read.
P.SetSetting("buffs", "alert", false)
WoW.auras[10060] = { expirationTime = 999, duration = 15 }
fireAura()
check(not BF.IsShown(), "alert off: nothing shown")
eq(B.state.lastRead[10060], "present", "  still read (the report knows)")
P.ResetSettings("buffs")
WoW.auras[10060] = nil
fireAura()

-- No name is ever compared or looked up.
local src = io.open("Pearls/Buffs.lua"):read("*a"):gsub("%-%-[^\n]*", "")
for _, name in ipairs({ "Clearcasting", "Innervate", "Power Infusion", "Blessing" }) do
    check(not src:find('"' .. name, 1, true), "no spell name in the code: " .. name)
end
check(not src:find("GetAuraDataBySpellName", 1, true), "  and no lookup by name")

-- Commands.
newChat()
SlashCmdList.GLASSPEARLS("buffs")
local chat = table.concat(newChat(), "\n")
check(chat:find("what the client allowed", 1, true) and chat:find("Anregen", 1, true), "/gpearls buffs: the report, by client names")
check(chat:find("29166: aura readable", 1, true), "  per ID: secrecy, overlay, last read, sound")
WoW.now = 400
SlashCmdList.GLASSPEARLS("buffs test")
eq(#slots(), 6, "/gpearls buffs test: every entry switched on")
eq(frame()._mouse, true, "  draggable")
WoW.flushTimers(B.TEST_SECONDS)
drain()
check(not BF.IsShown(), "  gone after its seconds")

-- The fixate alert alongside: independent, and never overlapping.
WoW.now = 500
WoW.auras[12021] = { expirationTime = 510, duration = 10 }
WoW.auras[29166] = { expirationTime = 520, duration = 20 }
fireAura()
check(GP.FixateFrame.IsShown() and BF.IsShown(), "both alerts at once")
eq(GP.Fixate.state.alert.id, 12021, "  fixate's state its own")
eq(#slots(), 1, "  buff alerts' its own")
for _, size in ipairs({ "small", "normal", "large" }) do
    P.SetSetting("fixate", "size", size)
    P.SetSetting("buffs", "size", size)
    local fx = GP.FixateFrame._test.frame()
    local fy, fh = 260, fx._height
    local by, bh = BF.DEFAULT_Y, frame()._height
    check(math.abs(fy - by) > (fh + bh) / 2, size .. ": the two default frames don't overlap")
end
P.ResetSettings("fixate")
P.ResetSettings("buffs")
WoW.auras[12021], WoW.auras[29166] = nil, nil
fireAura()

-- Off: nothing reads or shows; sounds removed.
SlashCmdList.GLASSPEARLS("buffs off")
registered = 0
for _, x in pairs(WoW.auraSounds) do if B._test.byID[x.info.spellID] then registered = registered + 1 end end
eq(registered, 0, "off: its sounds removed")
WoW.auras[29166] = { expirationTime = 999, duration = 20 }
fireAura()
WoW.fire("SPELL_ACTIVATION_OVERLAY_SHOW", 16870, 1, "CENTER", 1, 1, 1, 1)
check(not BF.IsShown(), "  nothing shows")
newChat()
SlashCmdList.GLASSPEARLS("buffs test")
check(table.concat(newChat(), "\n"):find("are off", 1, true), "  the test says it's off")
SlashCmdList.GLASSPEARLS("buffs on")
drain()
eq(#slots(), 1, "back on: it reads at once")

done("test_buffs")
