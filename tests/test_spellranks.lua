-- The low spell ranks pearl (#12): judging (known, castable as itself, kept,
-- outside the table, unreadable), the scan (the player's own pages only,
-- stance bars, macros, cast-only rows), the scheduler (login, learning and the
-- class trainer, the spec swap's two passes, combat, the debounce, slot
-- events), the cast warning, Update all (every slot x cursor outcome, the
-- restore only into an empty slot, refusals), Keep and the shared set cap,
-- settings, /gpearls ranks, and switching off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A shaman who knows Earth Shock to rank 4 and Lightning Bolt to rank 2.
for _, id in ipairs({ 8042, 8044, 8045, 8046 }) do WoW.spells[id] = { name = "Earth Shock" } end
for _, id in ipairs({ 403, 529, 548 }) do WoW.spells[id] = { name = "Lightning Bolt" } end
for _, id in ipairs({ 8042, 8044, 8045, 8046, 403, 529 }) do WoW.known[id] = true end
local function setBars()
    WoW.actions = {
        [1] = { kind = "spell", id = 8042 }, [2] = { kind = "spell", id = 8042 },
        [3] = { kind = "macro", id = 7 }, [4] = { kind = "item", id = 6948 },
        [5] = { kind = "spell", id = 403 }, [13] = { kind = "spell", id = 8046 },
    }
end
setBars()
WoW.macros[7] = { name = "Shock", spell = 8044 }

local GP = loadAddon()
local SR, P, SS, F = GP.SpellRanks, GP.Pearls, GP.SettingsSync, GP.SpellRanksFrame
local function flush() WoW.flushTimers() end
local function kinds(rows)
    local t = {}
    for _, r in ipairs(rows) do t[#t + 1] = r.kind .. ":" .. r.id .. ">" .. r.best .. "#" .. #r.slots end
    return table.concat(t, " ")
end
local function calls(name)
    local n = 0
    for _, c in ipairs(WoW.calls) do if c[1] == name then n = n + 1 end end
    return n
end

check(P.IsLive("spellranks"), "on by default")
eq(P.Get("spellranks").category, "Combat", "on the Combat page")

-- Login: one check after the delay, the popup with what's low.
check(not F.IsShown(), "nothing before the login delay")
flush()
check(F.IsShown(), "after the login delay: the popup")
eq(kinds(SR.state.rows), "bar:8042>8046#2 macro:8044>8046#1 bar:403>529#1",
    "Earth Shock on two buttons, the macro's, Lightning Bolt; the item and the best rank aren't listed")

-- Judging.
eq(SR.Judge(8042), 8046, "rank 1 with rank 4 known: rank 4")
eq(SR.Judge(8046), nil, "the best already: not low")
eq(SR.Judge(529), nil, "Lightning Bolt 2 with 3 unknown: not low")
eq(SR.Judge(12345), nil, "a spell outside the table: never judged")
eq(SR.Judge("8042"), nil, "not a number: can't tell")
WoW.overrides[8046] = 8045
eq(SR.Judge(8042), 8045, "rank 4 casts as rank 3: rank 3 is offered")
WoW.overrides[8046] = 10414
eq(SR.Judge(8042), 8046, "rank 4 casts as a higher rank: still rank 4")
WoW.overrides[8046] = 99999
eq(SR.Judge(8042), 8045, "rank 4 casts as another spell: the next rank down")
WoW.overrides[8046] = WoW.Secret("override")
eq(SR.Judge(8042), 8045, "an unreadable override: not offered")
WoW.overrides[8046] = nil
local realKnown = C_SpellBook.IsSpellKnown
C_SpellBook.IsSpellKnown = function() error("boom") end
eq(SR.Judge(8042), 8046, "IsSpellKnown failing: IsPlayerSpell answers")
C_SpellBook.IsSpellKnown = function() return WoW.Secret("known") end
eq(SR.Judge(8042), 8046, "  a secret answer: IsPlayerSpell answers")
C_SpellBook.IsSpellKnown = realKnown

-- Pages: only the player's own.
local special = { [11] = true, [16] = true, [17] = true, [18] = true, [19] = true }
check(SR.PlayerSlot(1, special), "the main bar's first page")
check(SR.PlayerSlot(72, special), "  its sixth (bottom left)")
local mine, stance = SR.PlayerSlot(80, special)
check(mine and stance, "a stance or form bar (73-120): scanned, labelled")
check(not SR.PlayerSlot(125, special), "the multicast page (11): never")
check(not SR.PlayerSlot(140, special), "page 12, no bar: never (allowlist)")
check(SR.PlayerSlot(150, special), "a multi bar (page 13)")
check(not SR.PlayerSlot(195, special), "the vehicle page (16): never")
WoW.pages.multicast = 13
check(not SR.PlayerSlot(150), "a special page read at scan time wins over a multi bar")
WoW.pages.multicast = 11
WoW.actions[80] = { kind = "spell", id = 8042 }
WoW.actions[125] = { kind = "spell", id = 8042 }
WoW.actions[150] = { kind = "spell", id = 403 }
local rows = SR.Scan()
eq(kinds(rows), "bar:8042>8046#3 macro:8044>8046#1 bar:403>529#2", "stance and multi bars counted, the multicast page not")
check(rows[1].stance, "  the stance slot labels its row")
WoW.actions[80], WoW.actions[125], WoW.actions[150] = nil, nil, nil
-- Unreadable slots are skipped.
WoW.actions[6] = { kind = WoW.Secret("kind"), id = 8042 }
WoW.actions[7] = { kind = "spell", id = WoW.Secret("id") }
eq(kinds(SR.Scan()), "bar:8042>8046#2 macro:8044>8046#1 bar:403>529#1", "secret slots: skipped, nothing thrown")
WoW.actions[6], WoW.actions[7] = nil, nil
P.SetSetting("spellranks", "macros", false)
eq(kinds(SR.Scan()), "bar:8042>8046#2 bar:403>529#1", "macros off: not listed")
P.ResetSettings("spellranks")

-- Later: quiet until something new.
SR.Later()
check(not F.IsShown(), "Later closes it")
WoW.fire("SPELLS_CHANGED")
flush()
check(not F.IsShown(), "the same findings don't pop up again")
WoW.actions[14] = { kind = "spell", id = 8044 }
WoW.fire("SPELLS_CHANGED")
flush()
check(F.IsShown(), "a new one does")
WoW.actions[14] = nil
SR.Later()

-- The debounce: a burst of events, one check.
local gen = SR.state.gen
for _ = 1, 5 do WoW.fire("LEARNED_SPELL_IN_SKILL_LINE", 8046, 1, false) end
eq(SR.state.gen, gen + 5, "each event bumps the generation")
local checks = 0
local realCheck = SR.Check
SR.Check = function(...) checks = checks + 1; return realCheck(...) end
flush()
eq(checks, 1, "  only the newest timer checks")
-- Slot events: only to settle a pending scan or refresh an open list.
checks = 0
WoW.fire("ACTIONBAR_SLOT_CHANGED", 1)
flush()
eq(checks, 0, "a slot change with nothing pending or shown: no check")
WoW.fire("SPELLS_CHANGED")
WoW.fire("ACTIONBAR_SLOT_CHANGED", 1)
WoW.fire("UPDATE_MACROS")
flush()
eq(checks, 1, "with a check pending, slot events push it back: still one")
-- The spec swap: the debounce and a second pass at 6 s.
checks = 0
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
WoW.flushTimers(SR.DEBOUNCE)
eq(checks, 1, "a spec swap: a check after the debounce")
WoW.flushTimers(SR.SWAP_SECOND_PASS)
eq(checks, 2, "  and a second pass, whatever the slot events do")
P.SetSetting("spellranks", "afterSpecSwap", false)
checks = 0
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
flush()
eq(checks, 0, "  the option off: no check")
P.SetSetting("spellranks", "afterLearning", false)
WoW.fire("SPELLS_CHANGED")
flush()
eq(checks, 0, "learning with the option off: no check")
P.ResetSettings("spellranks")
SR.Check = realCheck

-- The class trainer: held until it closes; a profession trainer doesn't hold.
SR.state.seen = {}
WoW.fire("TRAINER_SHOW")
WoW.fire("SPELLS_CHANGED")
flush()
check(not F.IsShown(), "a class trainer open: held")
check(SR.state.waitTrainer, "  and remembered")
WoW.fire("TRAINER_CLOSED")
flush()
check(F.IsShown(), "it closes: the check runs")
SR.Later()
SR.state.seen = {}
WoW.tradeTrainer = true
WoW.fire("TRAINER_SHOW")
WoW.fire("SPELLS_CHANGED")
flush()
check(F.IsShown(), "a profession trainer doesn't hold it")
WoW.fire("TRAINER_CLOSED")
WoW.tradeTrainer = false
SR.Later()

-- Combat: held, then after.
SR.state.seen = {}
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.fire("SPELLS_CHANGED")
flush()
check(not F.IsShown(), "in combat: nothing shows")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
flush()
check(F.IsShown(), "after combat: it shows")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not F.IsShown(), "entering combat hides it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
flush()
check(F.IsShown(), "  and it comes back after")
SR.Later()

-- The cast warning.
SR.state.seen = {}
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8045)
flush()
check(F.IsShown(), "a low rank cast that's on no bar: shown")
check(kinds(SR.state.rows):find("cast:8045>8046#0", 1, true), "  as a cast row")
SR.Later()
gen = SR.state.gen
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 8045)
eq(SR.state.gen, gen, "the same spell again: once per session")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3", 8044)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", WoW.Secret("spell"))
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", WoW.Secret("unit"), "Cast-5", 8044)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 8046)
eq(SR.state.gen, gen, "another unit, a secret ID or unit, the best rank: ignored")
eq(SR.state.casts[8044], nil, "  nothing queued")
check(not kinds(SR.Scan()):find("cast:8042", 1, true), "a low rank cast that is on a bar: just the bar row")
SR.state.casts[8042] = true
check(not kinds(SR.Scan()):find("cast:8042", 1, true), "  even when queued")
SR.state.casts[8042] = nil
P.SetSetting("spellranks", "warnCasts", false)
check(not kinds(SR.Scan()):find("cast:", 1, true), "casts off: no cast rows")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 8044)
eq(SR.state.casts[8044], nil, "  and nothing queued")
P.ResetSettings("spellranks")
SR.state.casts = {}

--------------------------------------------------------------------------------
-- Update all.
local function fresh()
    setBars()
    WoW.cursor, WoW.calls = nil, {}
    WoW.placeHook, WoW.placeForbidden, WoW.pickupSpellFails = nil, nil, nil
    SR.state.byHand, SR.state.forbidden = false, false
    newChat()
    return SR.Scan()
end
local function said(pattern)
    for _, l in ipairs(newChat()) do if l:find(pattern, 1, true) then return true end end
    return false
end

-- The clean run.
rows = fresh()
eq(SR.Update(rows), 3, "three buttons updated")
eq(WoW.actions[1].id, 8046, "slot 1: rank 4")
eq(WoW.actions[2].id, 8046, "slot 2: rank 4")
eq(WoW.actions[5].id, 529, "slot 5: Lightning Bolt 2")
eq(WoW.actions[3].kind, "macro", "the macro untouched")
eq(WoW.cursor, nil, "the cursor ends empty")
eq(calls("ClearCursor"), 3, "  each displaced old rank cleared (ours)")
check(said("3 action buttons updated to the highest rank."), "  and said")

-- Refusals before anything moves.
rows = fresh()
WoW.cursor = { bag = 0, slot = 1, id = 6948 }
eq(SR.Update(rows), 0, "something on the cursor: refused")
eq(WoW.actions[1].id, 8042, "  nothing changed")
eq(calls("ClearCursor"), 0, "  the player's cursor never cleared")
check(said("Put down what you are holding first."), "  and said")
rows = fresh()
WoW.combat = true
eq(SR.Update(rows), 0, "in combat: refused")
check(said("after combat"), "  and said")
WoW.combat = false
-- A slot changed since the scan: skipped.
rows = fresh()
WoW.actions[1] = { kind = "spell", id = 8045 }
eq(SR.Update(rows), 2, "a slot changed since the scan is skipped, the others updated")
eq(WoW.actions[1].id, 8045, "  that slot untouched")

-- The pickup fails.
rows = fresh()
WoW.pickupSpellFails = true
eq(SR.Update(rows), 0, "the pickup failing: nothing updated")
eq(calls("PlaceAction"), 0, "  nothing placed")
check(said("didn't let Glass Pearls pick up"), "  and said")

-- The client picks up another rank than asked (an automatic upgrade, say):
-- never placed, our spell cleared.
rows = fresh()
local realPickup = C_Spell.PickupSpell
C_Spell.PickupSpell = function(id) WoW.cursor = { kind = "spell", id = 8045 } end
eq(SR.Update(rows), 0, "the cursor holding another rank than asked: nothing updated")
eq(calls("PlaceAction"), 0, "  never placed")
eq(WoW.cursor, nil, "  that rank (ours) cleared")
C_Spell.PickupSpell = realPickup

-- PlaceAction forbidden: by hand for the session.
rows = fresh()
WoW.placeForbidden = true
eq(SR.Update(rows), 0, "PlaceAction forbidden: nothing updated")
eq(WoW.cursor, nil, "  our pickup cleared (a spell of the group)")
eq(WoW.actions[1].id, 8042, "  the slot as it was")
check(SR.state.byHand, "  by hand for the session")
check(said("drag Earth Shock (Rank 4) from your spellbook"), "  says how")
check(GP.failures["pearl spellranks update"] ~= nil, "  recorded")
WoW.placeForbidden = nil
eq(SR.Update(rows), 0, "by hand: Update all refuses after")
SR.state.byHand, SR.state.forbidden = false, false
WoW.fire("ADDON_ACTION_FORBIDDEN", "OtherAddon", "PlaceAction()")
check(not SR.state.forbidden, "another addon's forbidden action isn't ours")

-- Slot right, cursor holding something not ours: counted, cursor left, said.
rows = fresh()
WoW.placeHook = function(slot)
    WoW.actions[slot] = { kind = "spell", id = WoW.cursor.id }
    WoW.cursor = { kind = "macro", id = 9 }
    return true
end
eq(SR.Update({ rows[1] }), 1, "the slot reads as the best rank: counted, whatever the cursor holds")
eq(WoW.actions[1].id, 8046, "  slot 1 updated")
eq(WoW.cursor and WoW.cursor.kind, "macro", "  the macro on the cursor left alone")
eq(WoW.actions[2].id, 8042, "  the next button refused: the cursor isn't empty (the run stops)")
local text = table.concat(newChat(), "\n")
check(text:find("Something is on your cursor: put it down.", 1, true), "  and said")

-- The slot emptied, the old rank on the cursor: put back into the empty slot.
rows = fresh()
local first = true
WoW.placeHook = function(slot)
    if not first then return false end
    first = false
    WoW.actions[slot] = nil
    WoW.cursor = { kind = "spell", id = 8042 }
    return true
end
eq(SR.Update({ rows[1] }), 0, "the slot came back empty: not counted")
eq(WoW.actions[1] and WoW.actions[1].id, 8042, "  the old rank put back into the empty slot")
eq(WoW.cursor, nil, "  the cursor ends empty")
eq(WoW.actions[2].id, 8042, "  the run stopped: slot 2 untouched")
-- The slot emptied, something else on the cursor: nothing is put back.
rows = fresh()
WoW.placeHook = function(slot)
    WoW.actions[slot] = nil
    WoW.cursor = { bag = 0, slot = 1, id = 6948 }
    return true
end
eq(SR.Update({ rows[1] }), 0, "the slot emptied with an item on the cursor: not counted")
eq(calls("PlaceAction"), 1, "  only the old rank is ever put back: no second placement")
eq(WoW.cursor and WoW.cursor.id, 6948, "  the item left on the cursor")
check(said("Something is on your cursor: put it down."), "  and said")
-- The restore fails too: the old rank stays on the cursor, and it's said.
rows = fresh()
WoW.placeHook = function(slot)
    WoW.actions[slot] = nil
    WoW.cursor = { kind = "spell", id = 8042 }
    return true
end
eq(SR.Update({ rows[1] }), 0, "the restore failing: not counted")
eq(WoW.cursor and WoW.cursor.id, 8042, "  the old rank left on the cursor (never cleared)")
check(said("Earth Shock (Rank 1) is on your cursor: put it back on its button."), "  and the player told")
eq(calls("PlaceAction"), 2, "  one placement, one restore: no more")
-- Another action in the slot: never placed into.
rows = fresh()
WoW.placeHook = function(slot)
    WoW.actions[slot] = { kind = "item", id = 5 }
    WoW.cursor = { kind = "spell", id = 8042 }
    return true
end
eq(SR.Update({ rows[1] }), 0, "another action in the slot: not counted")
eq(calls("PlaceAction"), 1, "  never placed into (no restore over it)")
eq(WoW.actions[1].kind, "item", "  that action stays")
local lines = newChat()
local joined = table.concat(lines, "\n")
check(joined:find("Check this button", 1, true), "  the button flagged")
check(joined:find("is on your cursor", 1, true), "  and the old rank on the cursor said")
-- The slot unchanged (the client did nothing): our pickup cleared, stopped.
rows = fresh()
WoW.placeHook = function() return true end
eq(SR.Update({ rows[1] }), 0, "PlaceAction doing nothing: not counted")
eq(WoW.cursor, nil, "  our pickup cleared")
eq(WoW.actions[1].id, 8042, "  the slot as it was")
-- An unreadable cursor afterwards: left alone.
rows = fresh()
local realCursor = GetCursorInfo
WoW.placeHook = function(slot)
    WoW.actions[slot] = { kind = "spell", id = 8046 }
    WoW.cursor = { kind = "spell", id = 8042 }
    GetCursorInfo = function() return WoW.Secret("cursor") end
    return true
end
eq(SR.Update({ rows[1] }), 1, "the slot right, the cursor unreadable: counted once")
GetCursorInfo = realCursor
check(WoW.cursor ~= nil, "  the unreadable cursor never cleared")
WoW.cursor = nil
fresh()

--------------------------------------------------------------------------------
-- Keep, and the shared set cap.
rows = SR.Scan()
check(SR.Keep(rows[1]), "Keep")
check(SS.SetHas(SR.KEEP, 8042), "  the rank is on the kept list")
eq(SR.Judge(8042), nil, "  never judged low again")
check(not kinds(SR.Scan()):find("8042", 1, true), "  gone from the scan")
SS.SetRemove(SR.KEEP, 8042)
eq(SR.Judge(8042), 8046, "removed: listed again")
-- Fill the sets (with tombstones) to the shared cap: both features refuse cleanly.
local i = 0
while SS.Core.SetEntries(GP.db.sync) < SS.SET_MAX do
    i = i + 1
    SS.SetAdd(GP.BagsFull.KEEP, 100000 + i)
    if i % 2 == 0 then SS.SetRemove(GP.BagsFull.KEEP, 100000 + i) end
end
newChat()
local lightning
for _, r in ipairs(SR.Scan()) do if r.id == 403 then lightning = r end end
check(not SR.Keep(lightning), "the shared cap reached: Keep of a new rank refused")
check(said("The kept list is full"), "  and said")
eq(SR.Judge(403), 529, "  the rank still listed")
check(SR.Keep({ id = 8042 }), "a rank kept before (its entry kept as a tombstone) can be kept again")
SS.SetRemove(SR.KEEP, 8042)
local ok, why = SS.SetAdd(GP.BagsFull.KEEP, 999999)
check(not ok and why == "full", "the bags-full list refuses too")
local body = SS.Encode()
check(#body <= SS.BUDGET, "the full snapshot still fits its budget (" .. #body .. " B)")
SS.SetClear(GP.BagsFull.KEEP)

-- /gpearls ranks.
SR.Later()
WoW.actions = { [1] = { kind = "spell", id = 8046 } }
newChat()
SlashCmdList.GLASSPEARLS("ranks")
check(said("No low spell ranks on your action bars."), "/gpearls ranks with nothing low: says so")
setBars()
SlashCmdList.GLASSPEARLS("ranks")
check(F.IsShown(), "  with something low: the popup, even if seen before")
SR.Later()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
SlashCmdList.GLASSPEARLS("ranks")
check(said("checked after combat"), "  in combat: after combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
flush()
check(F.IsShown(), "  and it runs then")
SR.Later()

-- Switched off: hidden, nothing scheduled, events ignored.
SlashCmdList.GLASSPEARLS("ranks")
check(F.IsShown(), "shown before switching off")
P.Set("spellranks", false)
check(not F.IsShown(), "off: hidden")
SR.state.seen = {}
WoW.fire("SPELLS_CHANGED")
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
flush()
check(not F.IsShown(), "  and events do nothing")
P.Set("spellranks", true)
flush()
check(F.IsShown(), "back on: it checks again")

done("test_spellranks")
