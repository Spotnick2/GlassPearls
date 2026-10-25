-- Pearls/BagsFull.lua: the bags-full helper (#6). When loot doesn't fit,
-- offer to destroy the lowest-value item in your bags and loot it, in one
-- click. The window is Pearls/BagsFullFrame.lua; bag facts, room and the
-- candidates are Core/Bags.lua.
--
-- When it shows: a loot row that really doesn't fit (partial stacks and
-- specialty bags count as room; uncached never prompts), or a full-bags error
-- with no loot window open ("make room": destroy only, then loot again). One
-- coalesced re-evaluation per frame. Hidden on LOOT_CLOSED (except make-room),
-- when room appears, and in combat (back afterwards if still relevant). Closed
-- by the player, it stays quiet until the next loot window or error.
--
-- The action runs inside our own button's click, a hardware event: the delete
-- path is unmeasured until 2026-11-04. DeleteCursorItem is flagged
-- HasRestrictions like functions measured forbidden to addons; Forever addons
-- call it from their own clicks, never from a popup's. The stack is checked
-- again first; grey goes in one click, white needs a second click within 3 s.
-- Then pick up, confirm the cursor holds that item and that slot is locked,
-- delete. If the cursor still holds it, or ADDON_ACTION_FORBIDDEN names us,
-- the item goes back (ClearCursor), the loot is cancelled, and the session
-- switches to "by hand": the window points at the item, the player drags it
-- out. The loot follows only once the slot is empty (a moved item doesn't
-- count), in the same loot window, with the row still holding that item.

local ADDON = ...
GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Bags = GP.Bags
local BF = {}
GP.BagsFull = BF

BF.KEY = "bagsfull"
BF.KEEP = "bagsfull.keep"           -- the never-suggest list, a sync set
BF.ARM_SECONDS = 3
BF.PENDING_SECONDS = 2
BF.MAKE_ROOM_SECONDS = 60
-- UI error names (GetGameMessageInfo) that mean "no room". Blizzard's own
-- loot frame compares the text with ERR_INV_FULL (LootFrame.lua:192), the
-- fallback here; the names actually sent are on the day-one list.
BF.FULL_ERRORS = { ERR_INV_FULL = true }

local events = CreateFrame("Frame")
local state = {
    lootOpen = false, session = 0, dismissed = nil,
    makeRoom = nil,             -- { at = GetTime() } after a full-bags error with no loot window
    byHand = false,             -- the delete was refused this session
    pending = nil,              -- { bag, slot, id, lootSlot, lootLink }, cleared by LOOT_CLOSED
    armed = nil,                -- { key, at }
    combatWait = false,
    choice = { loot = nil, index = 1, anyway = false },
}
BF.state = state
local dirty = false

local function say(msg) API.Print(msg) end
local function clock() return GetTime() end

local function setting(name) return GP.Pearls.Setting(BF.KEY, name) end

local function options()
    return {
        scope = setting("scope"), greysFirst = setting("greysFirst"),
        keep = function(id) return GP.SettingsSync.SetHas(BF.KEEP, id) end,
        tools = GP.ToolItems,
    }
end

function BF.Candidates() return Bags.Candidates(options()) end

-- The loot window's item rows: { slot, link, id, qty, quality, icon, name,
-- value (nil when unknown), mustTake, fits }.
function BF.LootRows(snap)
    local rows = {}
    local ok, n = pcall(GetNumLootItems)
    if not ok or type(n) ~= "number" or API.IsSecret(n) then return rows end
    for i = 1, n do
        local okT, kind = pcall(GetLootSlotType, i)
        local okH, has = pcall(LootSlotHasItem, i)
        if okT and okH and kind == Enum.LootSlotType.Item and has == true then
            local okI, icon, name, qty, _, quality, _, isQuest, questID = pcall(GetLootSlotInfo, i)
            local link = select(2, pcall(GetLootSlotLink, i))
            if okI and type(link) == "string" and not API.IsSecret(link) then
                local id = select(2, pcall(C_Item.GetItemInfoInstant, link))
                -- Known data only: a row whose quantity can't be read is left
                -- out until it can (Codex review of #9).
                if type(id) == "number" and not API.IsSecret(id)
                    and not API.IsSecret(qty) and type(qty) == "number" and qty >= 1 then
                    local f = Bags.ItemFacts(id)
                    rows[#rows + 1] = {
                        slot = i, link = link, id = id, qty = qty, icon = icon,
                        name = (type(name) == "string" and not API.IsSecret(name)) and name or nil,
                        quality = (type(quality) == "number" and not API.IsSecret(quality)) and quality or nil,
                        value = f and f.price * qty or nil,
                        mustTake = (not API.IsSecret(isQuest) and isQuest == true)
                            or (not API.IsSecret(questID) and type(questID) == "number" and questID > 0),
                        fits = Bags.Fits(id, qty, snap),
                    }
                end
            end
        end
    end
    return rows
end

-- What the window shows now, or nil to hide it.
--   { mode = "loot" | "room", rows = rows needing room, target, targetIndex,
--     candidates, notWorth (loot worth less than every candidate), byHand }
function BF.Decide()
    if not GP.Pearls.IsLive(BF.KEY) or not GP.Pearls.IsOn(BF.KEY) then return nil end
    if API.InCombat() then
        state.combatWait = true
        return nil
    end
    local snap = Bags.Snapshot()
    local view = { byHand = state.byHand }
    if state.lootOpen then
        if state.dismissed == state.session then return nil end
        local rows = {}
        for _, r in ipairs(BF.LootRows(snap)) do
            if r.fits == false then rows[#rows + 1] = r end
        end
        if #rows == 0 then return nil end
        -- Keep the player's choice while it's there; else quest loot first, then the most valuable known.
        local pick
        for i, r in ipairs(rows) do
            if state.choice.loot == r.slot then pick = i end
        end
        if not pick then
            state.choice.anyway = false
            for i, r in ipairs(rows) do
                local best = rows[pick or 0]
                if not best
                    or (r.mustTake and not best.mustTake)
                    or (r.mustTake == best.mustTake and (r.value or -1) > (best.value or -1)) then
                    pick = i
                end
            end
        end
        view.mode, view.rows, view.targetIndex, view.target = "loot", rows, pick, rows[pick]
        state.choice.loot = rows[pick].slot
    elseif state.makeRoom then
        if clock() - state.makeRoom.at > BF.MAKE_ROOM_SECONDS or snap.general > 0 then
            state.makeRoom = nil
            return nil
        end
        view.mode = "room"
    else
        return nil
    end
    view.candidates = BF.Candidates()
    local first = view.candidates[1]
    local t = view.target
    view.notWorth = t ~= nil and first ~= nil and not t.mustTake and t.value ~= nil
        and t.value < first.value and not state.choice.anyway
    if state.choice.index > #view.candidates then state.choice.index = 1 end
    view.candidate = view.candidates[state.choice.index]
    return view
end

function BF.Evaluate()
    dirty = false
    local ok, view = pcall(BF.Decide)
    if not ok then
        API.Fail("pearl bagsfull evaluate", view)
        view = nil
    end
    BF.view = view
    if view then GP.BagsFullFrame.Show(view) else GP.BagsFullFrame.Hide() end
    return view
end

-- One re-evaluation per frame, however many events asked for it.
local function soon()
    if dirty then return end
    dirty = true
    C_Timer.After(0, function() if dirty then BF.Evaluate() end end)
end
BF.Soon = soon

--------------------------------------------------------------------------------
-- The window's choices.

function BF.NextCandidate(step)
    local n = BF.view and #BF.view.candidates or 0
    if n == 0 then return end
    state.choice.index = (state.choice.index - 1 + step) % n + 1
    state.armed = nil
    BF.Evaluate()
end

function BF.NextLoot()
    local v = BF.view
    if not v or not v.rows or #v.rows < 2 then return end
    local i = v.targetIndex % #v.rows + 1
    state.choice.loot, state.choice.anyway = v.rows[i].slot, false
    state.armed = nil
    BF.Evaluate()
end

function BF.ChooseAnyway()
    state.choice.anyway = true
    BF.Evaluate()
end

-- The X: never suggest this item again (synced across your accounts).
function BF.Never(cand)
    if not cand then return false end
    local ok, why = GP.SettingsSync.SetAdd(BF.KEEP, cand.id)
    if not ok then
        say(why == "full" and "The never-suggest list is full: remove some first (the gear on Glass Pearls' page)."
            or "That item can't be added to the list.")
        return false
    end
    say(cand.link .. " won't be suggested again.")
    state.choice.index, state.armed = 1, nil
    BF.Evaluate()
    return true
end

function BF.Dismiss()
    if state.lootOpen then state.dismissed = state.session end
    state.makeRoom, state.armed = nil, nil
    GP.BagsFullFrame.Hide()
end

--------------------------------------------------------------------------------
-- The action. Called from the window's button OnClick only.

local forbidden = false

local function armKey(c) return c.bag .. ":" .. c.slot .. ":" .. c.id .. ":" .. c.count end

local function sameStack(a, b)
    return a.bag == b.bag and a.slot == b.slot and a.id == b.id and a.count == b.count
        and a.link == b.link and a.value == b.value
end

-- The shown window may be a frame old: LOOT_CLOSED, a looted row, room that
-- appeared, a moved stack all queue a re-evaluation that hasn't run yet. So
-- decide again now, and go on only if the fresh decision still has the same
-- target row (slot, link, quantity, still not fitting) and the same stack
-- (Codex review of #9). Returns the fresh view and its candidate, or nil.
local function confirm(shown, cand)
    local ok, fresh = pcall(BF.Decide)
    if not ok or not fresh or fresh.mode ~= shown.mode or fresh.notWorth or fresh.byHand then return nil end
    local a, b = shown.target, fresh.target
    if (a == nil) ~= (b == nil) then return nil end
    if a and not (a.slot == b.slot and a.link == b.link and a.qty == b.qty) then return nil end
    for _, c in ipairs(fresh.candidates) do
        if sameStack(c, cand) then return fresh, c end
    end
end

-- Returns what happened: "combat", "cursor", "changed", "armed", "pickup",
-- "refused", "destroyed".
function BF.Destroy()
    local shown = BF.view
    local cand = shown and shown.candidate
    if not cand or state.byHand then return "changed" end
    if API.InCombat() then
        say("Not in combat.")
        return "combat"
    end
    if CursorHasItem() or GetCursorInfo() then
        say("Put down what's on your cursor first.")
        return "cursor"
    end
    local v
    v, cand = confirm(shown, cand)
    if not v then
        BF.Evaluate()
        return "changed"
    end
    BF.view = v
    -- White and better: a second click on the same stack, within 3 s.
    if cand.quality >= 1 then
        local key = armKey(cand)
        if not (state.armed and state.armed.key == key and clock() - state.armed.at <= BF.ARM_SECONDS) then
            state.armed = { key = key, at = clock() }
            GP.BagsFullFrame.Show(v)
            C_Timer.After(BF.ARM_SECONDS, function()
                if state.armed and state.armed.key == key then
                    state.armed = nil
                    if BF.view then GP.BagsFullFrame.Show(BF.view) end
                end
            end)
            return "armed"
        end
    end
    state.armed = nil
    C_Container.PickupContainerItem(cand.bag, cand.slot)
    local kind, id = GetCursorInfo()
    local after = Bags.Slot(cand.bag, cand.slot)
    if kind ~= "item" or id ~= cand.id or not (after and after.locked) then
        ClearCursor()
        say("Couldn't pick " .. cand.link .. " up; nothing was destroyed.")
        BF.Evaluate()
        return "pickup"
    end
    forbidden = false
    DeleteCursorItem()
    if forbidden or CursorHasItem() then
        ClearCursor()
        state.byHand, state.pending = true, nil
        say("The game didn't let Glass Pearls destroy it: drag " .. cand.link .. " out of your bag yourself.")
        BF.Evaluate()
        return "refused"
    end
    local t = v.target
    if v.mode == "loot" and t then
        local p = { bag = cand.bag, slot = cand.slot, id = cand.id, lootSlot = t.slot, lootLink = t.link }
        state.pending = p
        C_Timer.After(BF.PENDING_SECONDS, function() if state.pending == p then state.pending = nil end end)
    else
        say("Made room: loot it again.")
    end
    state.choice.index = 1
    return "destroyed"
end

-- The bags changed: if the destroyed stack's slot is empty, loot the row.
local function lootPending()
    local p = state.pending
    if not p then return end
    -- Only a confirmed empty slot proves the delete: an item there (not deleted
    -- yet, or something moved in) or an unreadable slot waits (then times out).
    local s, why = Bags.Slot(p.bag, p.slot)
    if s or why ~= "empty" then return end
    state.pending = nil
    -- The same loot window: LOOT_CLOSED clears `pending`, and a new window
    -- only opens after a close.
    if not state.lootOpen then return end
    local link = select(2, pcall(GetLootSlotLink, p.lootSlot))
    if link ~= p.lootLink or not LootSlotHasItem(p.lootSlot) then return end
    local ok, err = pcall(LootSlot, p.lootSlot)
    if not ok then API.Fail("pearl bagsfull loot", err) end
end

--------------------------------------------------------------------------------
-- Events.

local function isFullError(errorType, message)
    if not API.IsSecret(errorType) and type(errorType) == "number" then
        local ok, name = pcall(GetGameMessageInfo, errorType)
        if ok and not API.IsSecret(name) and BF.FULL_ERRORS[name] then return true end
    end
    return not API.IsSecret(message) and type(message) == "string" and message == ERR_INV_FULL
end

local EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
                 "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED",
                 "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_FORBIDDEN" }

events:SetScript("OnEvent", function(_, event, a1, a2)
    API.NoteCombat(event)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        if not state.lootOpen then
            state.lootOpen = true
            state.session = state.session + 1
            state.makeRoom = nil
            state.choice.loot, state.choice.index, state.choice.anyway = nil, 1, false
        end
        soon()
    elseif event == "LOOT_CLOSED" then
        state.lootOpen, state.pending, state.armed = false, nil, nil
        soon()
    elseif event == "BAG_UPDATE_DELAYED" then
        lootPending()
        soon()
    elseif event == "UI_ERROR_MESSAGE" then
        if isFullError(a1, a2) then
            if not state.lootOpen then state.makeRoom = { at = clock() } end
            state.dismissed = nil
            soon()
        end
    elseif event == "ADDON_ACTION_FORBIDDEN" then
        if a1 == ADDON and type(a2) == "string" and a2:find("DeleteCursorItem", 1, true) then
            forbidden = true
            state.byHand = true
            API.Fail("pearl bagsfull delete", "ADDON_ACTION_FORBIDDEN " .. a2)
            if CursorHasItem() then ClearCursor() end
            soon()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        soon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.combatWait then
            state.combatWait = false
            soon()
        end
    else   -- LOOT_SLOT_CHANGED, LOOT_SLOT_CLEARED, GET_ITEM_INFO_RECEIVED
        if state.lootOpen or state.makeRoom then soon() end
    end
end)

--------------------------------------------------------------------------------
-- The pearl.

local function enable()
    API.RegisterEvents(events, EVENTS)
end

local function disable()
    events:UnregisterAllEvents()
    state.pending, state.armed, state.makeRoom = nil, nil, nil
    GP.BagsFullFrame.Hide()
end

-- /gpearls cheapest
function BF.Cheapest()
    local c = BF.Candidates()[1]
    if not c then return say("Nothing in your bags can be suggested (" .. setting("scope") .. " items only).") end
    say("Cheapest: " .. (c.count > 1 and (c.count .. "x ") or "") .. c.link .. " ("
        .. C_CurrencyInfo.GetCoinTextureString(c.value) .. ")")
end

GP.SettingsSync.RegisterSet(BF.KEEP)

GP.Pearls.Register({
    key = BF.KEY,
    name = "Bags full helper",
    desc = "When loot doesn't fit, offers to destroy the cheapest item in your bags and loot it in one click.",
    help = "Shows beside the loot window when an item really doesn't fit (a partial stack or a matching bag counts "
        .. "as room). It offers the cheapest item in your bags by vendor value times stack: grey items only, or grey "
        .. "and white. Quest items, tools, equipment-set items, consumables, containers, reagents, ammunition, "
        .. "recipes, keys and items with a use are never offered, nor anything on your never-suggest list (the X). "
        .. "White items need a second click. /gpearls cheapest shows the first suggestion any time.",
    default = true,
    category = "Loot & Bags",
    section = "Bags",
    defaults = { scope = "grey", greysFirst = true },
    choices = { scope = { "grey", "white" } },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.BagsFullFrame.Configure(panel, refreshers) end,
    onReset = function() if BF.view then BF.Evaluate() end end,
    commands = { cheapest = { help = "the first item the bags full helper would suggest", run = BF.Cheapest } },
})

BF._test = {
    events = events, state = state,
    reset = function()
        state.lootOpen, state.session, state.dismissed, state.makeRoom = false, 0, nil, nil
        state.byHand, state.pending, state.armed, state.combatWait = false, nil, nil, false
        state.choice = { loot = nil, index = 1, anyway = false }
        dirty, forbidden = false, false
        BF.view = nil
    end,
}
