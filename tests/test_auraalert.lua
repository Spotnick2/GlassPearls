-- Core/AuraAlert.lua (#21): AA.Read's three answers and source unit, AA.Source,
-- AA.Sounds (register, hold in combat, refusal, remove some or all), and
-- AA.Entry's evidence rules in every order the review named: an overlay alone,
-- SHOW then aura absent, aura present then HIDE, a HIDE without an ID, two IDs
-- disagreeing, unknown then HIDE (a proc consumed in combat), expiry while an
-- overlay still shows, and the countdown continuing through unknown reads.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local AA = GP.AuraAlert

-- Read: present with its source, absent only with the per-spell proof, unknown otherwise.
WoW.auras[1] = { expirationTime = 50, duration = 10, sourceUnit = "party1" }
local r, exp, dur, src = AA.Read(1)
check(r == "present" and exp == 50 and dur == 10 and src == "party1", "present: expiration, duration, source")
WoW.auras[1].sourceUnit = WoW.Secret("src")
r, exp, dur, src = AA.Read(1)
check(r == "present" and src == nil, "a secret source: still present, no source")
WoW.auras[1] = nil
eq(AA.Read(1), "absent", "nil and readable: absent")
WoW.spellAuraSecret[1] = true
eq(AA.Read(1), "unknown", "nil but secret for this spell: unknown")
WoW.spellAuraSecret[1] = nil

-- Source: a plain non-empty name, else nil.
WoW.unitNames.party1 = "Elune"
eq(AA.Source("party1"), "Elune", "the source's name")
WoW.unitNames.party1 = WoW.Secret("name")
eq(AA.Source("party1"), nil, "a secret name: nil")
WoW.unitNames.party1 = ""
eq(AA.Source("party1"), nil, "an empty name: nil")
WoW.unitNames.party1 = nil
eq(AA.Source(nil), nil, "no unit: nil")
eq(AA.Source("party9"), nil, "a unit without a name: nil")

-- Sounds.
local s = AA.Sounds.New("test sound")
s:Register({ 1, 2 }, { fileID = 9, throttle = 1 })
eq(s.status[1], "registered", "registered")
eq(WoW.auraSounds[s.sounds[2]].info.spellID, 2, "  per ID")
s:Remove({ 1 }, "off")
check(s.sounds[1] == nil and s.sounds[2] ~= nil and s.status[1] == "off", "remove some: the others stay")
s:Remove(nil, "off")
check(next(s.sounds) == nil and s.status[2] == "off", "remove all")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
s:Register({ 3 }, { fileID = 9, throttle = 1 })
check(s.pending and s.sounds[3] == nil, "in combat: held, pending")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.auraSoundRefused = true
GP.failures["test sound"] = nil
s:Register({ 3 }, { fileID = 9, throttle = 1 })
check(s.status[3] == "refused" and GP.failures["test sound"], "refused: recorded")
WoW.auraSoundRefused = false

-- Entry: the evidence rules.
local function entry() return AA.Entry.New({ 10, 11, 12 }) end
local e = entry()
eq(e:Update(0), "hidden", "nothing known: hidden")
e:SetOverlay(10, "shown")
eq(e:Update(1), "show", "an overlay alone shows it")
local x, overlayOnly = e:Expiration()
check(x == 0 and overlayOnly, "  with no plain expiration (overlay only)")
e:SetOverlay(10, "hidden")
eq(e:Update(2), "clear", "its HIDE clears it, though the other IDs stay unknown")
-- SHOW, then the aura reads absent: the overlay still holds it.
e = entry()
e:SetOverlay(10, "shown")
e:Update(0)
e:SetAura(10, "absent")
eq(e:Update(1), "keep", "SHOW then aura absent: the overlay holds it")
-- Aura present, then a HIDE: the aura holds it.
e = entry()
e:SetAura(11, "present", 30)
e:Update(0)
e:SetOverlay(11, "hidden")
eq(e:Update(1), "keep", "aura present then HIDE: the aura holds it")
e:SetAura(11, "absent")
eq(e:Update(2), "clear", "  then aura absent: cleared")
-- A HIDE without an ID hides every overlay, keeps aura answers.
e = entry()
e:SetOverlay(10, "shown")
e:SetAura(11, "present", 40)
e:Update(0)
e:HideAllOverlays()
eq(e.overlay[10], "hidden", "a nil HIDE: every overlay hidden")
eq(e:Update(1), "keep", "  the aura answer keeps it")
-- Two IDs disagreeing: one present holds it.
e = entry()
e:SetAura(10, "present", 20)
e:SetAura(11, "present", 25)
e:Update(0)
e:SetAura(10, "absent")
eq(e:Update(1), "keep", "one of two gone: kept")
eq((e:Expiration()), 25, "  the countdown is the other's")
-- Unknown then HIDE (consumed in combat): cleared.
e = entry()
e:SetOverlay(12, "shown")
e:SetAura(12, "present", 15)
e:Update(0)
e:SetAura(12, "unknown")
eq(e:Update(1), "keep", "an active ID turning unknown: kept")
eq((e:Expiration()), 15, "  its countdown still known (arithmetic through unknown)")
e:SetOverlay(12, "hidden")
eq(e:Update(2), "clear", "  then its overlay's HIDE: cleared (consumed), though its 15 s weren't up")
-- An unknown aura with no overlay: its own known expiration ends it.
e = entry()
e:SetAura(12, "present", 15)
e:Update(0)
e:SetAura(12, "unknown")
eq(e:Update(5), "keep", "unknown, no overlay, its expiration ahead: kept")
e:Expire(12)
eq(e:Update(16), "clear", "  its own expiration passed: cleared")
-- Expiry while the overlay still shows: kept.
e = entry()
e:SetAura(10, "present", 5)
e:SetOverlay(10, "shown")
e:Update(0)
local expired = e:ExpiredIDs(6)
eq(#expired, 1, "the expired ID is found")
e:Expire(10)
eq(e:Update(6), "keep", "expired, but its overlay still shows: kept (expiry is evidence)")
-- A consumed proc in combat: unknown and its overlay hidden, no expiration known.
e = entry()
e:SetOverlay(11, "shown")
e:Update(0)
e:SetAura(11, "unknown")
e:SetOverlay(11, "hidden")
eq(e:Update(1), "clear", "unknown aura, overlay hidden, nothing else: cleared (consumed)")
-- Source and reset.
e = entry()
e:SetAura(10, "present", 9, "raid3")
e:Update(0)
eq(e:SourceUnit(), "raid3", "the source unit of the present ID")
e:Reset()
check(not e.shown and e.aura[10] == "unknown" and e:Update(1) == "hidden", "reset: everything forgotten")

done("test_auraalert")
