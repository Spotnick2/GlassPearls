-- Easy fishing (#64): the temp CVars. Each group set while fishing and removed
-- after, the settings changed mid-session, gamepad style, the review's traces
-- (an old removal never hits a newer session's or the gamepad's temp), silent
-- refusals and unreadable readbacks, eligibility, adoption with temps already
-- there, and `/gpearls fishing reset`.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local INTERACT = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
    "SoftTargetIconGameObject", "SoftTargetIconInteract" }
local SOUNDS = { "Sound_EnableAllSound", "Sound_EnableSFX", "Sound_EnableSoundWhenGameIsInBG", "Sound_SFXVolume",
    "Sound_MasterVolume", "Sound_MusicVolume", "Sound_EnableAmbience", "Sound_EnablePetSounds" }
local NAMES = { "UnitNameNPC", "UnitNameNonCombatCreatureName", "UnitNameInteractiveNPC",
    "UnitNameFriendlySpecialNPCName" }
for _, list in ipairs({ INTERACT, SOUNDS, NAMES }) do
    for _, n in ipairs(list) do WoW.cvarValues[n] = "0.5" end
end
WoW.known[7620] = true

local GP = loadAddon()
local F, P = GP.Fishing, GP.Pearls

local function tick(n) for _ = 1, n or 1 do WoW.advance(1) end end
local function start() WoW.channel = { id = 7620 }; WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "C", 7620) end
local function stop() WoW.channel = nil; WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "C", 7620) end
local function count(list)
    local n = 0
    for _, name in ipairs(list) do if WoW.tempCVars[name] ~= nil then n = n + 1 end end
    return n
end
local function none() return next(WoW.tempCVars) == nil end

-- Defaults: only the interact group.
start()
eq(count(INTERACT), 5, "fishing: the interact group set")
eq(WoW.tempCVars.SoftTargetInteract, "3", "  softTargetInteract Any")
eq(WoW.tempCVars.SoftTargetInteractRange, "60", "  a range past the bobber")
eq(count(SOUNDS) + count(NAMES), 0, "  sounds and names off by default")
eq(F.state.held.SoftTargetInteract.status, "applied", "  read back: applied")
stop()
check(none(), "stopped: every temp removed")
eq(WoW.cvarValues.SoftTargetInteract, "0.5", "  the player's own value never written")
eq(#WoW.cvarSets, 0, "  no SetCVar at all")

-- Sounds and names on.
P.SetSetting("fishing", "sounds", true)
P.SetSetting("fishing", "names", true)
check(none(), "settings on while not fishing: nothing yet")
start()
eq(count(SOUNDS), 8, "the sounds group set")
eq(WoW.tempCVars.Sound_MusicVolume, "0", "  music off")
eq(WoW.tempCVars.Sound_SFXVolume, "1.00", "  effects at the volume setting (100%)")
eq(WoW.tempCVars.Sound_EnableSoundWhenGameIsInBG, "1", "  heard in the background")
eq(count(NAMES), 4, "the names group set")
-- The volume changed mid-session: at once.
P.SetSetting("fishing", "volume", 50)
eq(WoW.tempCVars.Sound_SFXVolume, "0.50", "the volume changed mid-session: applied at once")
eq(WoW.tempCVars.Sound_MasterVolume, "0.50", "  the master volume too")
-- A group switched off mid-session: removed at once.
P.SetSetting("fishing", "names", false)
eq(count(NAMES), 0, "names switched off mid-session: removed at once")
P.SetSetting("fishing", "interact", false)
eq(count(INTERACT), 0, "interact switched off mid-session: removed at once")
P.SetSetting("fishing", "interact", true)
eq(count(INTERACT), 5, "  back on: set again")
stop()
check(none(), "stopped: everything removed")

-- Gamepad style: the interact group is the gamepad's, never ours.
WoW.inputStyle = Enum.InputDeviceInterfaceType.Gamepad
WoW.tempCVars.SoftTargetInteract, WoW.tempCVars.SoftTargetInteractRange = "1", "20"   -- Blizzard's
local removedBefore = WoW.tempCount("remove", "SoftTargetInteract")
start()
eq(WoW.tempCVars.SoftTargetInteract, "1", "gamepad style: the gamepad's temp untouched")
eq(F.state.held.SoftTargetInteract, nil, "  not held")
eq(count(SOUNDS), 8, "  sounds still ours")
stop()
eq(WoW.tempCVars.SoftTargetInteractRange, "20", "  still the gamepad's after the session")
eq(WoW.tempCount("remove", "SoftTargetInteract"), removedBefore, "  never removed by us")
WoW.inputStyle = "throw"
start()
eq(F.state.held.SoftTargetInteract, nil, "an unreadable style: interact not set")
stop()
WoW.tempCVars = {}

-- A transition during a session: dropped unremoved, re-applied a frame later on Mkb.
WoW.inputStyle = Enum.InputDeviceInterfaceType.Mkb
start()
local removes = WoW.tempCount("remove")
WoW.inputStyle = Enum.InputDeviceInterfaceType.Gamepad
WoW.tempCVars.SoftTargetInteract, WoW.tempCVars.SoftTargetInteractRange = "1", "20"   -- Blizzard's Init
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
eq(F.state.held.SoftTargetInteract, nil, "to gamepad mid-session: interact dropped")
eq(WoW.tempCount("remove"), removes, "  without removing anything")
WoW.flushTimers(0)
eq(WoW.tempCVars.SoftTargetInteract, "1", "  a frame later in gamepad style: the gamepad's stays")
WoW.inputStyle = Enum.InputDeviceInterfaceType.Mkb
for _, n in ipairs(INTERACT) do WoW.tempCVars[n] = nil end                             -- Blizzard's MKB Init
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
WoW.flushTimers(0)
eq(count(INTERACT), 5, "back to Mkb mid-session: the interact group applied again")
eq(WoW.tempCVars.SoftTargetInteract, "3", "  ours")
stop()
check(none(), "  and removed at the end")

-- Trace (a): session A's removal throws; session B wants it; the regen keeps B's.
start()
WoW.tempRemoveThrows.Sound_MusicVolume = true
stop()
eq(WoW.tempCVars.Sound_MusicVolume, "0", "a removal that throws: the temp stays")
check(F.state.held.Sound_MusicVolume ~= nil, "  still held (retried later)")
start()
local sets = WoW.tempCount("set", "Sound_MusicVolume")
WoW.tempRemoveThrows.Sound_MusicVolume = nil
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.tempCVars.Sound_MusicVolume, "0", "  session B wants it: the regen leaves it")
eq(WoW.tempCount("set", "Sound_MusicVolume"), sets, "  not set twice")
stop()
eq(WoW.tempCVars.Sound_MusicVolume, nil, "  removed once B ends")

-- Trace (b): an interact removal throws; the style becomes gamepad with no
-- session; the regen removes nothing of the gamepad's.
start()
WoW.tempRemoveThrows.SoftTargetInteract = true
stop()
check(F.state.held.SoftTargetInteract ~= nil, "an interact removal that throws: held")
WoW.tempRemoveThrows.SoftTargetInteract = nil
WoW.inputStyle = Enum.InputDeviceInterfaceType.Gamepad
WoW.tempCVars.SoftTargetInteract = "1"                                                   -- Blizzard's Init
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
WoW.flushTimers(0)
removes = WoW.tempCount("remove", "SoftTargetInteract")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.tempCount("remove", "SoftTargetInteract"), removes, "  the regen after a transition removes nothing")
eq(WoW.tempCVars.SoftTargetInteract, "1", "  the gamepad's temp stays")
-- The same, with the pearl off.
WoW.inputStyle = Enum.InputDeviceInterfaceType.Mkb
WoW.tempCVars = {}
start()
WoW.tempRemoveThrows.SoftTargetInteract = true
stop()
P.Set("fishing", false)
WoW.tempRemoveThrows.SoftTargetInteract = nil
WoW.inputStyle = Enum.InputDeviceInterfaceType.Gamepad
WoW.tempCVars.SoftTargetInteract = "1"
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
WoW.flushTimers(0)
removes = WoW.tempCount("remove", "SoftTargetInteract")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.tempCount("remove", "SoftTargetInteract"), removes, "  with the pearl off too")
eq(WoW.tempCVars.SoftTargetInteract, "1", "  the gamepad's temp stays")
WoW.inputStyle = Enum.InputDeviceInterfaceType.Mkb
WoW.tempCVars = {}
P.Set("fishing", true)

-- Disable with temps held: removed; a throw is retried at the regen while off.
start()
WoW.tempRemoveThrows.Sound_SFXVolume = true
P.Set("fishing", false)
WoW.channel = nil
check(not F.IsFishing(), "switched off: the session ends")
eq(WoW.tempCVars.Sound_SFXVolume, "0.50", "  a removal that throws stays")
eq(count(INTERACT), 0, "  the rest removed")
WoW.tempRemoveThrows.Sound_SFXVolume = nil
WoW.fire("PLAYER_REGEN_ENABLED")
check(none(), "  removed at the next regen, while off")
check(GP.failures["pearl fishing Sound_SFXVolume"] ~= nil, "  the throw recorded")
P.Set("fishing", true)

-- A silent refusal: held as refused, not retried this session, removal still attempted.
WoW.cvarValues.Sound_MusicVolume = "0.8"
WoW.tempRefused.Sound_MusicVolume = true
start()
eq(F.state.held.Sound_MusicVolume.status, "refused", "a set that silently did nothing: refused")
local refusedSets = WoW.tempCount("set", "Sound_MusicVolume")
WoW.fire("PLAYER_REGEN_ENABLED")
P.SetSetting("fishing", "names", true)
eq(WoW.tempCount("set", "Sound_MusicVolume"), refusedSets, "  not retried this session (regen, a setting change)")
stop()
eq(F.state.held.Sound_MusicVolume, nil, "  its removal attempted at the end")
WoW.tempRefused.Sound_MusicVolume = nil
P.SetSetting("fishing", "names", false)

-- A set that worked but can't be read back: unverified, still removed.
WoW.cvarRefuse.Sound_EnableAmbience = "throwRead"
start()
eq(F.state.held.Sound_EnableAmbience.status, "unverified", "a readback that throws: unverified")
eq(WoW.tempCVars.Sound_EnableAmbience, "0", "  the temp is there")
stop()
eq(WoW.tempCVars.Sound_EnableAmbience, nil, "  removed at the end all the same")
WoW.cvarRefuse.Sound_EnableAmbience = nil

-- The client's own number formatting is the same value.
WoW.tempReadAs.Sound_EnableSFX = "1.000"
start()
eq(F.state.held.Sound_EnableSFX.status, "applied", "\"1.000\" read back for \"1\": applied")
stop()
WoW.tempReadAs.Sound_EnableSFX = nil

-- Ineligible names: never set.
WoW.cvarInfo.Sound_EnablePetSounds = { secure = true }
WoW.cvarInfo.UnitNameNPC = { readOnly = true }
WoW.cvarValues.Sound_EnableAllSound = nil                 -- unknown to the client
local before = WoW.tempCount("set", "Sound_EnablePetSounds") + WoW.tempCount("set", "Sound_EnableAllSound")
start()
eq(WoW.tempCount("set", "Sound_EnablePetSounds") + WoW.tempCount("set", "Sound_EnableAllSound"), before,
    "a secure or unknown CVar: never set")
eq(F.state.ineligible.Sound_EnablePetSounds, "secure", "  why: secure")
eq(F.state.ineligible.Sound_EnableAllSound, "unknown to the client", "  why: unknown")
stop()
WoW.cvarInfo = {}
WoW.cvarValues.Sound_EnableAllSound = "0.5"

-- A set that throws: not held, tried again at the next reconcile.
WoW.tempThrows.Sound_EnableSFX = true
start()
eq(F.state.held.Sound_EnableSFX, nil, "a set that throws: not held")
WoW.tempThrows.Sound_EnableSFX = nil
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.tempCVars.Sound_EnableSFX, "1", "  set at the next reconcile")
stop()

-- A reload mid-cast with the temps still there: adopted, set again, removed at the end.
for _, n in ipairs(SOUNDS) do WoW.tempCVars[n] = "0" end
P.Set("fishing", false)
F.state.held = {}
WoW.channel = { id = 7620 }
local setsBefore = WoW.tempCount("set", "Sound_MusicVolume")
P.Set("fishing", true)
check(F.IsFishing(), "a channel running at Enable: adopted")
eq(WoW.tempCount("set", "Sound_MusicVolume"), setsBefore + 1, "  temps already there are set again")
stop()
check(none(), "  and removed at the end")

-- /gpearls fishing reset: every eligible name of ours, interact only on Mkb.
for _, list in ipairs({ INTERACT, SOUNDS, NAMES }) do for _, n in ipairs(list) do WoW.tempCVars[n] = "x" end end
WoW.inputStyle = Enum.InputDeviceInterfaceType.Gamepad
newChat()
SlashCmdList.GLASSPEARLS("fishing reset")
eq(count(SOUNDS) + count(NAMES), 0, "reset: the sounds and names temps removed")
eq(count(INTERACT), 5, "  in gamepad style the interact ones are left")
check(chatHas("12 fishing setting"), "  and says how many")
WoW.inputStyle = Enum.InputDeviceInterfaceType.Mkb
start()
newChat()
SlashCmdList.GLASSPEARLS("fishing reset")
check(chatHas("reset once the cast ends"), "reset while fishing: refused")
stop()

-- The report lists what is held.
start()
newChat()
SlashCmdList.GLASSPEARLS("fishing")
check(chatHas("Sound_MusicVolume = 0 %(applied%)"), "the report lists each held temp and its status")
stop()

done("test_fishing_temps")
