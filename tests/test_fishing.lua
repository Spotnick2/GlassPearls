-- Easy fishing (#64): the key (its overrides and the secure button), the
-- session (channel events, the watchdog, adoption), combat and switching off.
-- The temp CVars are test_fishing_temps.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Every CVar the pearl may touch exists on this client (stub values).
local function knownCVars()
    for _, n in ipairs({ "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
        "SoftTargetIconGameObject", "SoftTargetIconInteract", "Sound_EnableAllSound", "Sound_EnableSFX",
        "Sound_EnableSoundWhenGameIsInBG", "Sound_SFXVolume", "Sound_MasterVolume", "Sound_MusicVolume",
        "Sound_EnableAmbience", "Sound_EnablePetSounds", "UnitNameNPC", "UnitNameNonCombatCreatureName",
        "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName" }) do
        WoW.cvarValues[n] = "1"
    end
    WoW.cvarValues.SoftTargetInteract = "0"
end
knownCVars()
WoW.known[7620] = true

local GP = loadAddon()
local F, P = GP.Fishing, GP.Pearls
local button = F._test.button()

local function start(id) WoW.channel = { id = id or 7620 }; WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-1", id or 7620) end
local function stop(id) WoW.channel = nil; WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-1", id or 7620) end
local function press(key)
    WoW.pressKey(key, true)
    WoW.pressKey(key, false)
end
local function tick(n) for _ = 1, n do WoW.advance(1) end end
local function casts() return WoW.calledCount("CastSpellByID") end
local function lastCast()
    for i = #WoW.calls, 1, -1 do if WoW.calls[i][1] == "CastSpellByID" then return WoW.calls[i][2] end end
end

-- The pearl.
local def = P.Get("fishing")
check(def ~= nil, "registered")
eq(def.category, "Professions", "on the Professions page")
eq(def.section, "Fishing", "  under Fishing")
eq(def.default, true, "on by default")
check(P.IsLive("fishing"), "enabled at login")
eq(BINDING_NAME_GLASSPEARLS_FISH, "Fish, then reel in", "the key's name in Key Bindings")
local pages = table.concat(P.Categories(), ",")
check(pages:find("Combat,Professions", 1, true) ~= nil, "Professions comes after Combat: " .. pages)
check(button ~= nil and not button:IsShown(), "the secure button exists, hidden")
eq(button:GetAttribute("type"), nil, "  disarmed")
eq(button:GetAttribute("typerelease"), nil, "  no typerelease (no second cast on a held release)")
eq(button:GetAttribute("useOnKeyDown"), nil, "  no useOnKeyDown: Blizzard's CVar picks the edge")

-- No key bound: no override.
eq(next(WoW.overrides), nil, "no key bound: nothing overridden")
eq(WoW.pressKey("F", true), "body", "  the key would run the binding's body")

-- A key bound: the cast override.
WoW.bindings.GLASSPEARLS_FISH = "F"
WoW.fire("UPDATE_BINDINGS")
local o = WoW.overrides.F
check(o and o.kind == "click" and o.target == F.BUTTON and o.priority == true, "a key bound: a priority click override")

-- One press: one cast of the highest known rank, then disarmed.
press("F")
eq(casts(), 1, "a press casts once")
eq(lastCast(), 7620, "  the rank known")
eq(button:GetAttribute("type"), nil, "  disarmed after the click")
WoW.known[18248] = true
WoW.fire("SPELLS_CHANGED")
press("F")
eq(lastCast(), 18248, "the highest rank known is cast")
WoW.cvars.ActionButtonUseKeyDown = true
press("F")
eq(casts(), 3, "acting on the down edge: still one cast")
WoW.cvars.ActionButtonUseKeyHeldSpell = true
press("F")
eq(casts(), 4, "with press-and-hold on: still one cast")
WoW.cvars.ActionButtonUseKeyDown, WoW.cvars.ActionButtonUseKeyHeldSpell = nil, nil

-- Refusals at the click.
WoW.openLoot({ { id = 2589, qty = 1 } })
press("F")
eq(casts(), 4, "a loot window open: no cast")
WoW.closeLoot()

-- Two keys.
WoW.bindings.GLASSPEARLS_FISH = { "F", "SHIFT-F" }
WoW.fire("UPDATE_BINDINGS")
check(WoW.overrides.F and WoW.overrides["SHIFT-F"], "two keys: both overridden")
WoW.bindings.GLASSPEARLS_FISH = "F"
WoW.fire("UPDATE_BINDINGS")
check(WoW.overrides["SHIFT-F"] == nil and WoW.overrides.F, "  a key unbound: its override cleared")

-- No loop when our own override calls raise UPDATE_BINDINGS.
local before = WoW.calledCount("SetOverrideBindingClick")
WoW.bindingEventsInside = true
WoW.bindings.GLASSPEARLS_FISH = { "F", "G" }
WoW.fire("UPDATE_BINDINGS")
eq(WoW.calledCount("SetOverrideBindingClick") - before, 2, "UPDATE_BINDINGS inside our calls: each key set once")
WoW.bindingEventsInside = false
WoW.bindings.GLASSPEARLS_FISH = "F"
WoW.fire("UPDATE_BINDINGS")

-- A session: the key interacts.
start()
check(F.IsFishing(), "a Fishing channel: a session")
o = WoW.overrides.F
check(o and o.kind == "command" and o.target == "INTERACTTARGET", "  the key interacts")
press("F")
eq(WoW.commands[#WoW.commands], "INTERACTTARGET", "  a press reels in")
eq(casts(), 4, "  and casts nothing")
eq(WoW.tempCVars.SoftTargetInteract, "3", "  the Interact Key is on")
stop()
check(not F.IsFishing(), "the channel stops: the session ends")
eq(WoW.overrides.F.kind, "click", "  the key casts again")
eq(WoW.tempCVars.SoftTargetInteract, nil, "  the Interact Key's temp is gone")
eq(F.state.lastEnd, "it stopped", "  the reason is kept")

-- Other channels, secret or other IDs: nothing.
WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-2", 10)
check(not F.IsFishing(), "another channel: no session")
WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-2", WoW.Secret("id"))
check(not F.IsFishing(), "a secret ID: no session")
start(1229271)
check(F.IsFishing(), "1229271 (also Fishing) is recognised")
WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-2", 10)
check(F.IsFishing(), "  another channel's stop doesn't end it")
stop(1229271)

-- The watchdog: a missed STOP.
start()
WoW.channel = nil
WoW.advance(1)
check(not F.IsFishing(), "the watchdog: no channel any more ends the session")
eq(F.state.lastEnd, "the channel ended", "  says why")
eq(WoW.overrides.F.kind, "click", "  the key casts again")

-- The watchdog: an unreadable channel ends it after 35 s, not before.
start()
WoW.channel = "throw"
tick(34)
check(F.IsFishing(), "unreadable for 34 s: still a session")
WoW.channel = { id = 7620 }
WoW.advance(1)
WoW.channel = "secret"
tick(34)
check(F.IsFishing(), "  a plain read in between starts the count again")
WoW.advance(1)
check(not F.IsFishing(), "  35 s unreadable: ended")

-- Renewal: one effective watchdog.
local function watchdogs()
    local n = 0
    for _, t in ipairs(WoW.timers) do if not t.cancelled then n = n + 1 end end
    return n
end
tick(3)
local base = watchdogs()
start()
start()
WoW.channel = { id = 7620 }
tick(2)
eq(watchdogs() - base, 1, "a START while open renews: one watchdog left running")
stop()
tick(1)
eq(watchdogs() - base, 0, "  none once ended")

-- A loading screen ends it.
start()
WoW.fire("PLAYER_LEAVING_WORLD")
check(not F.IsFishing(), "a loading screen ends the session")
WoW.channel = nil

-- Adoption: switched on during a cast from a bar.
P.Set("fishing", false)
WoW.channel = { id = 7732 }
P.Set("fishing", true)
check(F.IsFishing(), "switched on mid-cast: the running channel is adopted")
eq(WoW.overrides.F.kind, "command", "  the key interacts")
eq(WoW.tempCVars.SoftTargetInteract, "3", "  the Interact Key is on")
-- START after an adoption: renewed, one session.
local token = F.state.session.token
start(7732)
check(F.IsFishing() and F.state.session.token ~= token, "  a START after it renews the same session")
-- Adopt after a START: nothing new.
token = F.state.session.token
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
eq(F.state.session.token, token, "  an adoption with a session open changes nothing")
stop(7732)

-- Adoption: the channel unreadable at first, read again each second.
P.Set("fishing", false)
WoW.channel = "throw"
P.Set("fishing", true)
check(not F.IsFishing(), "an unreadable channel at Enable: no session yet")
WoW.channel = { id = 7620 }
WoW.advance(1)
check(F.IsFishing(), "  read again a second later: adopted")
stop()
-- A pending retry, then switched off: nothing reopens.
P.Set("fishing", false)
WoW.channel = "throw"
P.Set("fishing", true)
P.Set("fishing", false)
WoW.channel = { id = 7620 }
WoW.advance(3)
check(not F.IsFishing(), "a pending adoption retry after Disable reopens nothing")
eq(next(WoW.tempCVars), nil, "  and sets nothing")
WoW.channel = nil
P.Set("fishing", true)

-- Combat: the override waits; the regen computes it again.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
start()
eq(WoW.overrides.F.kind, "click", "a session starting in combat: the override can't change")
check(F.state.syncPending, "  it waits")
press("F")
eq(casts(), 4, "  the disarmed button casts nothing in combat")
stop()
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.overrides.F.kind, "click", "after the fight: the state now (idle), never the one captured")
check(not F.state.syncPending, "  nothing waits")

-- PostClick never writes under lockdown.
local writes = 0
local real = button.SetAttribute
rawset(button, "SetAttribute", function(self, k, v) writes = writes + 1; return real(self, k, v) end)
F._test.preClick(button, "LeftButton", false)
eq(button:GetAttribute("type"), "spell", "PreClick out of combat arms")
WoW.combat = true
writes = 0
F._test.postClick(button, "LeftButton", false)
eq(writes, 0, "  PostClick under lockdown writes nothing")
check(F.state.disarmPending, "  the disarm waits")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(button:GetAttribute("type"), nil, "  disarmed after the fight")
WoW.combat = true
writes = 0
F._test.preClick(button, "LeftButton", true)
F._test.postClick(button, "LeftButton", true)
eq(writes, 0, "a click in combat: no attribute write at all")
WoW.combat = false
rawset(button, "SetAttribute", nil)

-- Switched off in combat: the override is cleared after the fight.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
P.Set("fishing", false)
check(WoW.overrides.F ~= nil, "switched off in combat: the override stays for now")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.overrides.F, nil, "  cleared after the fight (nothing held)")

-- The binding's body, when no override took the key.
newChat()
F.OnKey()
check(chatHas("is off"), "off: the key says so")
P.Set("fishing", true)
WoW.known[7620], WoW.known[18248] = nil, nil
WoW.fire("SPELLS_CHANGED")
eq(WoW.overrides.F, nil, "Fishing not known: no override")
F.OnKey()
check(chatHas("don't know Fishing"), "  the key says so")
WoW.known[7620] = true
WoW.fire("SPELLS_CHANGED")

-- A channel ID read as a secret number is never used (a secret can't key a
-- table on the client). 1229271 isn't used after this.
WoW.MarkSecret(1229271, "channel spellID")
WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3", 1229271)
check(not F.IsFishing(), "a secret fishing ID: no session")

-- The report.
newChat()
SlashCmdList.GLASSPEARLS("fishing")
check(chatHas("Easy fishing: on; key F; casts rank 7620; input mkb"), "the report")

done("test_fishing")
