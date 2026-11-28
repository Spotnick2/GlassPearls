-- The low spell ranks' Update ranks button in the spellbook (#162): made when
-- Blizzard_PlayerSpells loads (or at Enable when it already has), a child of
-- the spellbook kept out of the gamepad's smart navigation, shown only while
-- the pearl and its `spellbook` setting are on; its click checks and updates
-- the bars at once, shows what's left, says when nothing was low, and does
-- nothing in combat or while off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- tests/test_spellranks_book_loaded.lua runs this file again with arg[1] =
-- "loaded": the spellbook already loaded before the addon.
local preloaded = arg and arg[1] == "loaded"

-- A shaman who knows Earth Shock to rank 4.
for _, id in ipairs({ 8042, 8044, 8045, 8046 }) do WoW.spells[id] = { name = "Earth Shock" } end
for _, id in ipairs({ 8042, 8044, 8045, 8046 }) do WoW.known[id] = true end
WoW.macros[7] = { name = "Shock", spell = 8044 }
local function bars(withMacro)
    WoW.actions = { [1] = { kind = "spell", id = 8042 }, [2] = { kind = "spell", id = 8046 } }
    if withMacro then WoW.actions[3] = { kind = "macro", id = 7 } end
    WoW.cursor, WoW.calls = nil, {}
end
bars(false)
if preloaded then WoW.loadPlayerSpells() end

local GP = loadAddon()
local SR, F, P = GP.SpellRanks, GP.SpellRanksFrame, GP.Pearls
WoW.flushTimers()
SR.Later()

if not preloaded then
    check(F.BookButton() == nil, "no button before the spellbook loads")
    WoW.loadPlayerSpells()
end
local b = F.BookButton()
check(b ~= nil, preloaded and "the spellbook loaded before: made at Enable" or "made when the spellbook loads")
local book = PlayerSpellsFrame.SpellBookFrame
eq(b:GetParent(), book, "  a child of Blizzard's spellbook")
eq(b:GetName(), F.BOOK_BUTTON, "  named")
eq(b:GetText(), "Update ranks", "  'Update ranks'")
eq(b:GetFrameLevel(), book:GetFrameLevel() + 10, "  well above the book's art")
eq(b.smartNavigationIgnored, true, "  out of the gamepad's smart navigation")
check(b:IsShown(), "  shown while on")
eq(F.EnsureBookButton(), b, "made once")
eq(b:GetParent(), book, "  still on the same spellbook")

local function said(pattern)
    for _, l in ipairs(newChat()) do if l:find(pattern, 1, true) then return true end end
    return false
end
local function click() b._scripts.OnClick(b, "LeftButton", false) end

-- A low rank on a bar: updated in the click, nothing left to show.
newChat()
click()
eq(WoW.actions[1].id, 8046, "the click: slot 1 updated to rank 4")
check(not F.IsShown(), "  nothing left: no popup")
local lines = newChat()
local updated, none = false, false
for _, l in ipairs(lines) do
    if l:find("1 action button updated", 1, true) then updated = true end
    if l:find("No low spell ranks", 1, true) then none = true end
end
check(updated, "  said what it updated")
check(not none, "  and not also 'no low spell ranks'")

-- Nothing low: said, no popup.
click()
check(said("No low spell ranks on your action bars."), "nothing low: said")
check(not F.IsShown(), "  no popup")

-- A low bar rank and a macro: the bar updated, the popup lists the macro.
bars(true)
SR.state.seen = { ["macro:8044>8046"] = true }   -- even one seen before
click()
eq(WoW.actions[1].id, 8046, "with a macro: the bar updated")
eq(WoW.actions[3].kind, "macro", "  the macro untouched")
check(F.IsShown(), "  the popup shows what's left")
eq(#SR.state.rows, 1, "  one row")
eq(SR.state.rows[1].kind, "macro", "  the macro")
SR.Later()

-- With the class trainer open: still checks now.
bars(false)
WoW.fire("TRAINER_SHOW")
click()
eq(WoW.actions[1].id, 8046, "a class trainer open: updated anyway")
WoW.fire("TRAINER_CLOSED")
WoW.flushTimers()
SR.Later()

-- Combat: nothing changes, it says why.
bars(false)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
newChat()
click()
eq(WoW.actions[1].id, 8042, "in combat: nothing changes")
check(said("Spells can be updated after combat."), "  said")
check(not SR.state.waitCombat, "  and nothing checked or queued for after it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.flushTimers()
SR.Later()

-- The setting: hidden while off, back when on.
P.SetSetting("spellranks", "spellbook", false)
check(not b:IsShown(), "the setting off: hidden")
P.SetSetting("spellranks", "spellbook", true)
check(b:IsShown(), "  on: shown")

-- The pearl off: hidden, and a click does nothing.
P.Set("spellranks", false)
check(not b:IsShown(), "the pearl off: hidden")
bars(false)
newChat()
SR.UpdateNow()
eq(WoW.actions[1].id, 8042, "  a click while off changes nothing")
check(said("Low spell ranks is off"), "  and says so")
P.Set("spellranks", true)
check(b:IsShown(), "back on: shown")

done(preloaded and "test_spellranks_book_loaded" or "test_spellranks_book")
