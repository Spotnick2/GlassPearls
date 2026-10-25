-- The fixate alert (#17): the three answers (present / absent / unknown) and
-- what each does to the alert; the client's sound (registered with the right
-- structure, refused and recorded, held until combat ends, removed when off);
-- UNIT_AURA's payload never touched; no name ever compared or looked up, and
-- the alert in the client's language (German and French); the commands; the
-- dispatcher's key/command split; switching off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A German client: the client's own names for the four spells.
for _, id in ipairs({ 12021, 463171, 1222688, 1315448 }) do WoW.spells[id] = { name = "Fixierung", icon = 136129 } end
local GP = loadAddon()
-- Only the fixate spells' sounds count here (other pearls register their own).
FIXATE = {}
for _, id in ipairs(GP.Fixate.SPELLS) do FIXATE[id] = true end
local F, P, FR = GP.Fixate, GP.Pearls, GP.FixateFrame
local function drain() for _ = 1, 20 do if #WoW.timers == 0 then return end WoW.flushTimers() end end
local function aura(exp) return { expirationTime = exp, duration = 10, icon = 136129, spellId = 12021 } end
local function alertShown() return FR.IsShown() and F.state.alert ~= nil end

check(P.IsLive("fixate"), "on by default")
eq(P.Get("fixate").category, "Combat", "on the Combat page")

-- The client's sound: one per spell, the documented structure, registered at login.
local n, sample = 0, nil
for _, s in pairs(WoW.auraSounds) do if FIXATE[s.info.spellID] then n = n + 1; sample = s end end
eq(n, 4, "a sound registered for each of the four spells")
eq(sample.trigger, Enum.UnitAuraSoundTrigger.Added, "  on Added")
eq(sample.info.unitToken, "player", "  for the player")
check(type(sample.info.spellID) == "number", "  by spell ID")
eq(sample.info.soundFileID, F.SOUND_FILE, "  the raid warning file")
check(sample.info.throttleSeconds >= 0 and sample.info.throttleSeconds <= 5, "  a throttle within 0-5 s")
eq(sample.info.outputChannel, "Master", "  on the master channel")
eq(F.state.soundStatus[12021], "registered", "status: registered")

-- The three answers.
eq(F.Read(12021), "absent", "no aura, and the client says it's readable: absent")
WoW.spellAuraSecret[12021] = true
eq(F.Read(12021), "unknown", "no aura, but the aura would be secret: unknown, never absent")
WoW.spellAuraSecret[12021] = WoW.Secret("perSpell")
eq(F.Read(12021), "unknown", "  the per-spell answer itself secret: unknown")
WoW.spellAuraSecret[12021] = nil
local realPer = C_Secrets.ShouldSpellAuraBeSecret
C_Secrets.ShouldSpellAuraBeSecret = function() error("x") end
eq(F.Read(12021), "unknown", "  the per-spell check failing: unknown")
C_Secrets.ShouldSpellAuraBeSecret = nil
eq(F.Read(12021), "unknown", "  no per-spell check at all (another build): unknown, never absent")
C_Secrets.ShouldSpellAuraBeSecret = realPer
WoW.auras[12021] = aura(110)
local r, exp = F.Read(12021)
eq(r, "present", "a plain table: present")
eq(exp, 110, "  with its expiration")
WoW.auras[12021] = WoW.Secret("aura")
eq(F.Read(12021), "unknown", "a secret table: unknown")
WoW.auras[12021] = { expirationTime = WoW.Secret("exp"), duration = 10 }
eq(F.Read(12021), "unknown", "a secret field: unknown")
local realGet = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function() error("Auras cannot be accessed when secret") end
eq(F.Read(12021), "unknown", "a throw: unknown")
C_UnitAuras.GetPlayerAuraBySpellID = realGet
WoW.auras[12021] = nil

-- UNIT_AURA: the payload is never touched (every argument throws if touched).
WoW.now = 100
WoW.auras[12021] = aura(110)
WoW.fire("UNIT_AURA", WoW.Secret("unit"), WoW.Secret("updateInfo"))
drain()
check(alertShown(), "UNIT_AURA with a secret payload: read by ID, the alert shows")
eq(F.state.alert.id, 12021, "  for that spell")
check(F._test.events._units and F._test.events._units.UNIT_AURA[1] == "player", "registered for the player only")
eq(#WoW.soundsPlayed, 0, "the client plays the sound: ours doesn't")
-- The alert in the client's language.
local frame = FR._test.frame()
eq(frame.name:GetText(), "Fixierung", "the headline is the client's own spell name")
eq(frame.icon._file, 136129, "  with its icon")
eq(frame.countdown:GetText(), "10", "  and the countdown (10 s left)")
WoW.now = 105.5
WoW.tick()
eq(frame.countdown:GetText(), "4.5", "  ticking, in tenths under 10 s")

-- Unknown never clears it; absent does; the countdown does.
WoW.auras[12021] = WoW.Secret("aura")
WoW.fire("UNIT_AURA")
drain()
check(alertShown(), "unknown (secret in combat): the alert stays")
WoW.auras[12021] = nil
WoW.spellAuraSecret[12021] = true
WoW.fire("UNIT_AURA")
drain()
check(alertShown(), "a nil read while the aura would be secret: still unknown, it stays")
WoW.spellAuraSecret[12021] = nil
WoW.fire("PLAYER_REGEN_ENABLED")
drain()
check(not alertShown(), "after combat, absent for sure: cleared")
WoW.auras[1222688] = aura(0)
WoW.auras[1222688].expirationTime = 0
WoW.fire("UNIT_AURA")
drain()
check(alertShown(), "an aura without an expiration (channelled, until cancelled): shown")
eq(frame.countdown:GetText(), "", "  without a countdown")
WoW.auras[1222688] = nil
WoW.fire("UNIT_AURA")
drain()
check(not alertShown(), "  and cleared when absent")
WoW.now = 200
WoW.auras[463171] = aura(203)
WoW.fire("UNIT_AURA")
drain()
WoW.auras[463171] = WoW.Secret("aura")
WoW.now = 203.1
WoW.tick()
check(not alertShown(), "unknown, but its own countdown ran out: cleared")
WoW.auras[463171] = nil
-- Unknown never shows it either.
WoW.auras[12021] = WoW.Secret("aura")
WoW.fire("UNIT_AURA")
drain()
check(not alertShown(), "unknown with nothing shown: nothing shows")
WoW.auras[12021] = nil

-- The client's sound refused: recorded, said, and our own sound instead.
P.SetSetting("fixate", "sound", false)
local left = 0
for _, s in pairs(WoW.auraSounds) do if FIXATE[s.info.spellID] then left = left + 1 end end
eq(left, 0, "sound off: the client's sounds removed")
eq(F.state.soundStatus[12021], "off", "  status off")
WoW.auraSoundRefused = true
GP.failures["pearl fixate sound"] = nil
P.SetSetting("fixate", "sound", true)
eq(F.state.soundStatus[12021], "refused", "refused by the client: recorded as such")
check(GP.failures["pearl fixate sound"] ~= nil, "  and in /gpearls failures")
WoW.now = 300
WoW.auras[12021] = aura(310)
WoW.fire("UNIT_AURA")
drain()
eq(#WoW.soundsPlayed, 1, "  then the alert plays our own sound")
WoW.fire("UNIT_AURA")
drain()
eq(#WoW.soundsPlayed, 1, "  once per fixate, not per update")
WoW.auras[12021] = nil
WoW.fire("UNIT_AURA")
drain()
WoW.auraSoundRefused = false
P.ResetSettings("fixate")
-- Held until combat ends.
P.SetSetting("fixate", "sound", false)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
P.SetSetting("fixate", "sound", true)
left = 0
for _, s in pairs(WoW.auraSounds) do if FIXATE[s.info.spellID] then left = left + 1 end end
eq(left, 0, "switched on in combat: not registered yet")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
left = 0
for _, s in pairs(WoW.auraSounds) do if FIXATE[s.info.spellID] then left = left + 1 end end
eq(left, 4, "  registered once combat ends")
P.ResetSettings("fixate")

-- No name is ever compared or looked up: the code holds no spell name, and
-- GetAuraDataBySpellName (which throws in the stub) is never called.
local src = io.open("Pearls/Fixate.lua"):read("*a"):gsub("%-%-[^\n]*", "")
check(not src:find('"Fixate"', 1, true) and not src:find("GetAuraDataBySpellName", 1, true),
    "no spell name in the code, no lookup by name")
-- French: the same, in French.
WoW.spells[12021].name = "Fixer"
WoW.now = 400
WoW.auras[12021] = aura(405)
WoW.fire("UNIT_AURA")
drain()
eq(frame.name:GetText(), "Fixer", "a French client: the French name")
WoW.auras[12021] = nil
WoW.fire("UNIT_AURA")
drain()
-- The alert switched off: nothing shown, still read.
P.SetSetting("fixate", "alert", false)
WoW.auras[12021] = aura(405)
WoW.fire("UNIT_AURA")
drain()
check(not FR.IsShown(), "alert off: nothing shown")
eq(F.state.lastRead[12021], "present", "  still read (the report knows)")
WoW.auras[12021] = nil
WoW.fire("UNIT_AURA")
drain()
P.ResetSettings("fixate")

-- An alert already expired when shown: no empty frame (Codex review of #18).
P.SetSetting("fixate", "alert", false)
WoW.now = 450
WoW.auras[12021] = aura(452)
WoW.fire("UNIT_AURA")
drain()
WoW.now = 460                 -- expired while hidden
P.SetSetting("fixate", "alert", true)
check(not FR.IsShown(), "switched back on after it expired: no empty frame shown")
eq(F.state.alert, nil, "  and the alert is over")
WoW.auras[12021] = nil
WoW.fire("UNIT_AURA")
drain()
-- Test shows even with the display switched off (to place it).
P.SetSetting("fixate", "alert", false)
WoW.now = 470
F.Test()
check(FR.IsShown(), "Test with the alert switched off: still shown, to place it")
eq(FR._test.frame()._mouse, true, "  and draggable")
F.Clear()
P.ResetSettings("fixate")

-- Commands, and the dispatcher: the key switches it, other arguments are its command.
newChat()
SlashCmdList.GLASSPEARLS("fixate")
local lines = table.concat(newChat(), "\n")
check(lines:find("what the client allowed", 1, true), "/gpearls fixate: the report")
check(lines:find("Fixer (12021): sound the client plays it; aura readable now; last read absent", 1, true),
    "  per spell: name, ID, sound, secrecy, last read")
WoW.now = 500
SlashCmdList.GLASSPEARLS("fixate test")
check(alertShown() and F.state.alert.test, "/gpearls fixate test: the alert, as a test")
eq(frame._mouse, true, "  draggable during the test")
WoW.fire("UNIT_AURA")
drain()
check(F.state.alert and F.state.alert.test, "  a read during the test doesn't replace it")
WoW.now = 505.1
WoW.tick()
check(not alertShown(), "  it ends after its seconds")
SlashCmdList.GLASSPEARLS("fixate off")
check(not P.IsLive("fixate"), "/gpearls fixate off switches the pearl")
left = 0
for _, s in pairs(WoW.auraSounds) do if FIXATE[s.info.spellID] then left = left + 1 end end
eq(left, 0, "  its sounds removed")
WoW.auras[12021] = aura(510)
WoW.fire("UNIT_AURA")
drain()
check(not alertShown(), "  and nothing reads or shows")
newChat()
SlashCmdList.GLASSPEARLS("fixate test")
check(table.concat(newChat(), "\n"):find("is off", 1, true), "  the test says it's off")
SlashCmdList.GLASSPEARLS("fixate on")
check(P.IsLive("fixate"), "/gpearls fixate on")
drain()
check(alertShown(), "  back on: it reads at once and shows")
-- A pearl key without a command of that name still answers on/off as before.
newChat()
SlashCmdList.GLASSPEARLS("junk")
check(table.concat(newChat(), "\n"):find("is on. /gpearls junk on/off", 1, true), "a pearl without its own command: on/off as before")

-- A refused UNIT_AURA registration is recorded (Codex review of #18).
P.Set("fixate", false)
local realReg = GP.Fixate._test.events.RegisterUnitEvent
GP.Fixate._test.events.RegisterUnitEvent = function() return false end
GP.failures["pearl fixate UNIT_AURA"] = nil
P.Set("fixate", true)
eq(GP.failures["pearl fixate UNIT_AURA"], "refused", "RegisterUnitEvent returning false: recorded as refused")
GP.Fixate._test.events.RegisterUnitEvent = realReg

done("test_fixate")
