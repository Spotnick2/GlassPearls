-- Pearls/SpellRanks.lua: low spell ranks (#12). Spells on your action bars, or
-- cast, in a lower rank than one you know; after combat, a popup lists them
-- (Keep, Later, Update all). The popup and the gear's panel are
-- Pearls/SpellRanksFrame.lua; the rank groups are Data/SpellRanks.lua
-- (generated from the client's tables): everything here compares spell IDs.
--
-- Low: a spell S of a group, when a higher rank R of that group is known
-- (C_SpellBook.IsSpellKnown, else IsPlayerSpell) and castable as itself: its
-- override (C_Spell.GetOverrideSpell) is R, or a rank of the group at or
-- above R. The highest such R is the one offered. Kept spells (the sync set
-- spellranks.keep) and spells outside the table are never judged; anything
-- unreadable or secret means "can't tell", never "low".
--
-- The scan reads the player's own pages only: the main bar's six, the multi
-- bars (MultiActionBar_GetBarForPage), stance and form bars
-- (C_ActionBar.GetBonusBarIndexForSlot), minus the vehicle, override,
-- temporary-shapeshift, extra and multicast pages, read at scan time
-- (SecureTemplates.lua:671-679). Macros are reported, never edited.
--
-- When: one debounced scheduler (a generation counter) for login, learning,
-- a spec swap (plus a second pass), slot changes while something is pending
-- or shown, and a low-rank cast. Never in combat (released at
-- PLAYER_REGEN_ENABLED) and never while a class trainer is open (released at
-- TRAINER_CLOSED).
--
-- Update all runs in our button's click, out of combat, with the cursor
-- empty. For each button: pick up the best rank, place it, then read the
-- slot and the cursor again and act only on what was read. A slot read as the
-- best rank counts; a spell of this group on the cursor is cleared (spells are
-- lossless); anything else on the cursor is left alone and said. A failed
-- placement is undone only into an empty slot, never over another action. The
-- first unclean result stops the run. Unmeasured until 2026-11-04 (day one).

local ADDON = ...
GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local SR = {}
GP.SpellRanks = SR

SR.KEY = "spellranks"
SR.KEEP = "spellranks.keep"         -- spells kept low on purpose, a sync set
SR.MAX_SLOT = 180
SR.SLOTS_PER_PAGE = 12
SR.DEBOUNCE = 1.5
SR.LOGIN_DELAY = 8
SR.SWAP_SECOND_PASS = 6
SR.AFTER_COMBAT = 1

local events = CreateFrame("Frame")
local state = {
    gen = 0,                -- the scheduler's generation: only the newest timer runs
    pending = false,        -- a scan is scheduled
    waitCombat = false,     -- one is due after combat
    waitTrainer = false,    -- one is due when the class trainer closes
    trainerOpen = false,
    seen = {},              -- this session: "S>R" pairs already shown
    casts = {},             -- this session: low spell IDs seen cast
    byHand = false,         -- the game refused a change this session
    forbidden = false,      -- ADDON_ACTION_FORBIDDEN during our update
    rows = {},              -- the last scan
}
SR.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(SR.KEY, name) end
local function data() return GP.SpellRankData end
local function Frame() return GP.SpellRanksFrame end

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Judging

-- { group, rank, level } for a spell in the table, else nil.
function SR.Entry(id)
    local d = data()
    return d and type(id) == "number" and d.ranks[id] or nil
end

-- true / false / nil (can't tell).
local function known(id)
    local SB = rawget(_G, "C_SpellBook")
    if SB and SB.IsSpellKnown then
        local ok, v = pcall(SB.IsSpellKnown, id)
        if ok and not API.IsSecret(v) and v == true then return true end
    end
    local isPlayer = rawget(_G, "IsPlayerSpell")
    if isPlayer then
        local ok, v = pcall(isPlayer, id)
        if ok and not API.IsSecret(v) then return v == true end
    end
    return nil
end

-- R casts as itself, or as a rank of its group at or above R.
local function castsAsItself(id, entry)
    local S = rawget(_G, "C_Spell")
    if not (S and S.GetOverrideSpell) then return true end
    local ok, over = pcall(S.GetOverrideSpell, id)
    over = ok and plainNumber(over)
    if not over then return false end
    if over == id then return true end
    local e = SR.Entry(over)
    return e ~= nil and e[1] == entry[1] and e[2] >= entry[2]
end

-- The highest rank above `id`'s that is known and castable, or nil.
function SR.Best(id)
    local entry = SR.Entry(id)
    if not entry then return nil end
    local group = data().groups[entry[1]]
    for i = #group, 1, -1 do
        local r = group[i]
        local e = SR.Entry(r)
        if e[2] <= entry[2] then return nil end
        if known(r) and castsAsItself(r, e) then return r end
    end
    return nil
end

function SR.IsKept(id) return GP.SettingsSync.SetHas(SR.KEEP, id) end

-- The rank to offer instead of `id`, or nil (not low, kept, or can't tell).
function SR.Judge(id)
    if type(id) ~= "number" or SR.IsKept(id) then return nil end
    return SR.Best(id)
end

--------------------------------------------------------------------------------
-- The scan

-- Is this slot on one of the player's own pages? And is it a stance/form bar?
local function pageIndex(name)
    local AB = rawget(_G, "C_ActionBar")
    local fn = AB and AB[name]
    if not fn then return nil end
    local ok, v = pcall(fn)
    return ok and plainNumber(v) or nil
end

local function specialPages()
    local pages = {}
    for _, name in ipairs({ "GetVehicleBarIndex", "GetOverrideBarIndex", "GetTempShapeshiftBarIndex",
                            "GetExtraBarIndex", "GetMultiCastBarIndex" }) do
        local p = pageIndex(name)
        if p and p > 0 then pages[p] = true end
    end
    return pages
end

function SR.PlayerSlot(slot, special)
    local page = math.ceil(slot / SR.SLOTS_PER_PAGE)
    if (special or specialPages())[page] then return false end
    local AB = rawget(_G, "C_ActionBar")
    local bonus
    if AB and AB.GetBonusBarIndexForSlot then
        local ok, v = pcall(AB.GetBonusBarIndexForSlot, slot)
        bonus = ok and plainNumber(v) or nil
    end
    if bonus then return true, true end
    if page <= (rawget(_G, "NUM_ACTIONBAR_PAGES") or 6) then return true, false end
    local multi = rawget(_G, "MultiActionBar_GetBarForPage")
    if multi then
        local ok, bar = pcall(multi, page)
        if ok and bar ~= nil then return true, false end
    end
    return false
end

-- kind ("spell", "macro", other, or nil for empty), id; "unreadable" on a
-- secret or an error.
local function readSlot(slot)
    local okH, has = pcall(HasAction, slot)
    if not okH or API.IsSecret(has) then return "unreadable" end
    if not has then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or API.IsSecret(kind) or API.IsSecret(id) then return "unreadable" end
    return kind, id
end
SR.ReadSlot = readSlot

local function macroSpell(macroID)
    local fn = rawget(_G, "GetMacroSpell")
    if not fn then return nil end
    local ok, id = pcall(fn, macroID)
    return ok and plainNumber(id) or nil
end

local function macroName(macroID)
    local fn = rawget(_G, "GetMacroInfo")
    if not fn then return nil end
    local ok, name = pcall(fn, macroID)
    return ok and plainString(name) or nil
end

local function sortRows(rows)
    local function name(id)
        local S = rawget(_G, "C_Spell")
        local ok, n = pcall(S.GetSpellName, id)
        return ok and plainString(n) or ("~" .. id)
    end
    table.sort(rows, function(a, b)
        local na, nb = name(a.id), name(b.id)
        if na ~= nb then return na < nb end
        if a.id ~= b.id then return a.id < b.id end
        return a.kind < b.kind
    end)
    return rows
end

-- Rows: { kind = "bar" | "macro" | "cast", id, best, rank, bestRank,
-- slots = { ... }, stance = bool, macro = name }.
function SR.Scan()
    local rows, byKey = {}, {}
    if not data() then return rows end
    local special = specialPages()
    local function row(kind, id, best, extra)
        local k = kind .. ":" .. id .. ">" .. best .. (extra or "")
        local r = byKey[k]
        if not r then
            r = { kind = kind, id = id, best = best, rank = SR.Entry(id)[2], bestRank = SR.Entry(best)[2], slots = {} }
            byKey[k] = r
            rows[#rows + 1] = r
        end
        return r
    end
    local onBars = {}
    for slot = 1, SR.MAX_SLOT do
        local mine, stance = SR.PlayerSlot(slot, special)
        if mine then
            local kind, id = readSlot(slot)
            if kind == "spell" and type(id) == "number" then
                onBars[id] = true
                local best = SR.Judge(id)
                if best then
                    local r = row("bar", id, best)
                    r.slots[#r.slots + 1] = slot
                    if stance then r.stance = true end
                end
            elseif kind == "macro" and type(id) == "number" and setting("macros") then
                local sid = macroSpell(id)
                local best = sid and SR.Judge(sid)
                if best then
                    local r = row("macro", sid, best, "#" .. id)
                    r.macro = macroName(id)
                    r.slots[#r.slots + 1] = slot
                end
            end
        end
    end
    if setting("warnCasts") then
        for id in pairs(state.casts) do
            local best = not onBars[id] and SR.Judge(id)
            if best then row("cast", id, best) end
        end
    end
    return sortRows(rows)
end

--------------------------------------------------------------------------------
-- Checking and scheduling

local function rowKey(r) return r.kind .. ":" .. r.id .. ">" .. r.best end

-- force: "button" (asked for: always show, or say there's nothing), "after"
-- (after an update or Keep: refresh what's shown), nil (only what's new).
function SR.Check(force)
    if not SR.enabled then return end   -- switched off: nothing checks, shows or changes
    if API.InCombat() then state.waitCombat = true; return end
    if state.trainerOpen and not force then state.waitTrainer = true; return end
    state.pending = false
    local rows = SR.Scan()
    state.rows = rows
    local shown = Frame().IsShown()
    if #rows == 0 then
        if shown then Frame().Hide() end
        if force == "button" then say("No low spell ranks on your action bars.") end
        return rows
    end
    local new = state.reshow   -- hidden by combat: back after it
    state.reshow = false
    for _, r in ipairs(rows) do if not state.seen[rowKey(r)] then new = true end end
    if not new and not force and not shown then return rows end
    if force == "after" and not shown then return rows end
    for _, r in ipairs(rows) do state.seen[rowKey(r)] = true end
    Frame().Show(rows, { byHand = state.byHand })
    return rows
end

function SR.Schedule(delay)
    if not SR.enabled then return end
    state.gen = state.gen + 1
    state.pending = true
    local my = state.gen
    C_Timer.After(delay or SR.DEBOUNCE, function()
        if my == state.gen and SR.enabled then SR.Check() end
    end)
end

-- /gpearls ranks and the panel's Check now.
function SR.CheckNow()
    if not SR.enabled then
        say("Low spell ranks is off: switch it on in /gpearls (Combat).")
        return
    end
    if API.InCombat() then
        state.waitCombat, state.reshow = true, true   -- asked for: shown after, even if seen
        say("Spell ranks are checked after combat.")
        return
    end
    return SR.Check("button")
end

--------------------------------------------------------------------------------
-- Update all and Keep

-- The cursor: kind, spellID (for a spell), or "unreadable".
local function readCursor()
    local ok, kind, a, b, spellID = pcall(GetCursorInfo)
    if not ok or API.IsSecret(kind) then return "unreadable" end
    if kind == nil then return nil end
    if kind == "spell" then
        if API.IsSecret(spellID) then return "unreadable" end
        return "spell", plainNumber(spellID)
    end
    return kind
end

local function ofGroup(id, group)
    local e = SR.Entry(id)
    return e ~= nil and e[1] == group
end

local function spellLabel(id)
    local S = rawget(_G, "C_Spell")
    local ok, n = pcall(S.GetSpellName, id)
    local e = SR.Entry(id)
    local rank = rawget(_G, "RANK") or "Rank"
    return (ok and plainString(n) or ("spell " .. id)) .. (e and (" (" .. rank .. " " .. e[2] .. ")") or "")
end

-- Clear the cursor only when it holds a spell of this group (ours: lossless).
local function clearIfOurs(group)
    local kind, id = readCursor()
    if kind == "spell" and id and ofGroup(id, group) then
        ClearCursor()
        return true
    end
    return false
end

-- After a PlaceAction: read the slot and the cursor, act on what was read.
-- Returns "ok" (the slot holds `best`), or "stop".
local function settle(row, slot, best, group)
    local sk, sid = readSlot(slot)
    local slotBest = sk == "spell" and sid == best
    local slotOld = sk == "spell" and sid == row.id
    local slotEmpty = sk == nil
    if slotEmpty then
        -- Undo, only into an empty slot, only with the old rank on the cursor.
        local ck, cid = readCursor()
        if ck == "spell" and cid == row.id then
            pcall(PlaceAction, slot)
            sk, sid = readSlot(slot)
            slotOld = sk == "spell" and sid == row.id
            slotEmpty = sk == nil
        end
    end
    -- The cursor, after whatever happened. A spell of this group is ours and
    -- goes (lossless), except the old rank when its button lost it: then the
    -- player is told where it is. Anything else is left alone and said.
    local ck, cid = readCursor()
    local cursorLine
    local ours = ck == "spell" and cid ~= nil and ofGroup(cid, group)
    if ours and cid == row.id and not slotBest and not slotOld then
        cursorLine = spellLabel(row.id) .. " is on your cursor: put it back on its button."
    elseif ours then
        ClearCursor()
    elseif ck ~= nil then
        cursorLine = "Something is on your cursor: put it down."
    end
    if slotBest then
        if cursorLine then say(cursorLine) end
        return "ok"
    end
    if state.forbidden then
        state.byHand = true
        say("The game didn't let Glass Pearls change this button: drag " .. spellLabel(best)
            .. " from your spellbook onto it.")
    elseif not slotOld then
        say("Check this button: it changed while updating (action slot " .. slot .. ").")
    end
    if cursorLine then say(cursorLine) end
    return "stop"
end

local function updateSlot(row, slot)
    local kind, id = readSlot(slot)
    if kind ~= "spell" or id ~= row.id then return "skip" end   -- changed since the scan
    local best = SR.Judge(row.id)
    if not best then return "skip" end
    local group = SR.Entry(row.id)[1]
    if readCursor() ~= nil then
        say("Put down what you are holding first.")
        return "stop"
    end
    state.forbidden = false
    pcall(C_Spell.PickupSpell, best)
    local ck, cid = readCursor()
    if ck ~= "spell" or cid ~= best then
        clearIfOurs(group)
        if readCursor() ~= nil then say("Something is on your cursor: put it down.") end
        if state.forbidden then state.byHand = true end
        say("The game didn't let Glass Pearls pick up " .. spellLabel(best)
            .. ": drag it from your spellbook onto the button.")
        return "stop"
    end
    pcall(PlaceAction, slot)
    return settle(row, slot, best, group)
end

-- Update all: the bar rows given (the popup's), in our button's click.
function SR.Update(rows)
    if API.InCombat() then say("Spells can be updated after combat."); return 0 end
    if state.byHand then
        say("The game refused a change earlier: drag the higher ranks from your spellbook.")
        return 0
    end
    local n, stop = 0, false
    for _, row in ipairs(rows or state.rows) do
        if row.kind == "bar" then
            for _, slot in ipairs(row.slots) do
                local res = updateSlot(row, slot)
                if res == "ok" then n = n + 1 elseif res == "stop" then stop = true; break end
            end
        end
        if stop then break end
    end
    if n > 0 then
        say(n == 1 and "1 action button updated to the highest rank."
            or (n .. " action buttons updated to the highest rank."))
    end
    SR.Check("after")
    return n
end

function SR.Keep(row)
    if not row then return false end
    local ok, why = GP.SettingsSync.SetAdd(SR.KEEP, row.id)
    if not ok then
        say(why == "full" and "The kept list is full: remove some first (the gear on Glass Pearls' Combat page)."
            or "Couldn't keep that rank.")
        return false
    end
    SR.Check("after")
    return true
end

function SR.Later() Frame().Hide() end

--------------------------------------------------------------------------------
-- Events

local EVENTS = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
                 "ACTIVE_TALENT_GROUP_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS",
                 "TRAINER_SHOW", "TRAINER_CLOSED", "UNIT_SPELLCAST_SUCCEEDED",
                 "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_FORBIDDEN" }

local function onEvent(_, event, ...)
    API.NoteCombat(event)
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_LEVEL_UP" then
        if setting("afterLearning") then SR.Schedule() end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if setting("afterSpecSwap") then
            SR.Schedule()
            -- The bars may reload after the debounce: one more pass, whatever
            -- the slot events do.
            C_Timer.After(SR.SWAP_SECOND_PASS, function() if SR.enabled then SR.Check() end end)
        end
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" then
        -- Only to settle a scan already due, or to keep an open list current.
        if state.pending or Frame().IsShown() then SR.Schedule() end
    elseif event == "TRAINER_SHOW" then
        local ok, trade = pcall(IsTradeskillTrainer)
        state.trainerOpen = not (ok and trade == true)
    elseif event == "TRAINER_CLOSED" then
        if state.trainerOpen then
            state.trainerOpen = false
            if state.waitTrainer then
                state.waitTrainer = false
                SR.Schedule(1)
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if API.IsSecret(unit) or unit ~= "player" or not setting("warnCasts") then return end
        local id = plainNumber(spellID)
        if id and not state.casts[id] and SR.Entry(id) and SR.Judge(id) then
            state.casts[id] = true
            SR.Schedule()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Frame().IsShown() then
            Frame().Hide()
            state.waitCombat, state.reshow = true, true
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.waitCombat then
            state.waitCombat = false
            SR.Schedule(SR.AFTER_COMBAT)
        end
    elseif event == "ADDON_ACTION_FORBIDDEN" then
        local addon, fn = ...
        if addon == ADDON then
            state.forbidden = true
            API.Fail("pearl spellranks update", "ADDON_ACTION_FORBIDDEN " .. tostring(fn))
        end
    end
end
events:SetScript("OnEvent", onEvent)

local function enable()
    SR.enabled = true
    API.RegisterEvents(events, EVENTS)
    if setting("atLogin") then SR.Schedule(SR.LOGIN_DELAY) end
end

local function disable()
    SR.enabled = false
    events:UnregisterAllEvents()
    state.gen = state.gen + 1
    state.pending, state.waitCombat, state.waitTrainer = false, false, false
    Frame().Hide()
end

GP.SettingsSync.RegisterSet(SR.KEEP)

GP.Pearls.Register({
    key = SR.KEY,
    name = "Low spell ranks",
    desc = "Tells you when a spell on your action bars, or one you cast, is a lower rank than you know, "
        .. "and updates the buttons in one click.",
    help = "After combat, a list of the spells on your bars that use a lower rank than one you know: Update all "
        .. "puts the highest rank on those buttons (same place, same key). It checks at login, after you learn a "
        .. "spell (once the trainer window closes), and after a dual-spec swap. Spells in macros are listed, never "
        .. "edited. A low rank you cast is listed too. Keep a rank you use low on purpose: it's never listed again, "
        .. "on any of your accounts. /gpearls ranks checks now.",
    default = true,
    category = "Combat",
    section = "Spells",
    defaults = { afterLearning = true, afterSpecSwap = true, atLogin = true, warnCasts = true, macros = true },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.SpellRanksFrame.Configure(panel, refreshers) end,
    onSettingChanged = function()
        if SR.enabled and Frame().IsShown() then SR.Check("after") end
    end,
    commands = { ranks = { help = "check your action bars for low spell ranks now", run = SR.CheckNow } },
})

SR._test = { events = events, onEvent = onEvent, readCursor = readCursor, known = known }
