-- Paladin tank reminders (#22) on another class: nothing registered, nothing
-- shown, whatever its auras (the old WeakAura nagged every class in a group).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.class = "WARRIOR"
WoW.known[25780] = true          -- even if the client said so
WoW.stats.shield = true
local GP = loadAddon()
local T = GP.PaladinTank

check(GP.Pearls.IsLive("paladintank"), "the pearl is on")
check(not T._test.events:IsEventRegistered("UNIT_AURA"), "a warrior: UNIT_AURA not registered")
check(not T._test.events:IsEventRegistered("PLAYER_REGEN_ENABLED"), "  nor any other event")
eq(#T.Lines(), 0, "  no reminder")
check(T.Frame() == nil, "  no frame built")
newChat()
SlashCmdList.GLASSPEARLS("paladintank")
check(table.concat(newChat(), "\n"):find("for paladins", 1, true), "/gpearls paladintank says it's for paladins")

done("test_paladintank_mage")
