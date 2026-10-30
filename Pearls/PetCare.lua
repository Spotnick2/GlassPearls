-- Pearls/PetCare.lua: hunter pet care (#38). For a hunter only: a feeding
-- reminder with a Feed button when the pet's happiness drops, what the pet
-- eats (a tooltip line, a mark on the bag buttons, or both), and a warning
-- when the pet is missing, dead or on Passive (at the start of a fight, at a
-- ready check, or out of combat when it disappears: each a checkbox). Its
-- window, Feed button, bag marks and panel are Pearls/PetCareFrame.lua.
--
-- Happiness: C_PetInfo.GetPetHappiness, a plain 1-3 (porting guide), only
-- for a hunter pet (HasPetUI's second return, as PetHappiness.lua does).
-- Edible: C_PetInfo.CanPetEatItem, Blizzard's own test. The Passive stance:
-- the pet bar's token slot whose texture key is "PET_PASSIVE_TEXTURE"
-- (PetActionBar.lua:362), an internal key, not a display string.
--
-- The food choice is a heuristic, never called optimal: food within
-- LEVEL_BAND levels of the pet (the Vanilla rule as remembered, unverified),
-- the cheapest per item first, else the highest item level; ties by bag and
-- slot. The client still decides what the pet eats.
--
-- Every read is plain or nothing is said. The fight-start and ready-check
-- warnings use their own reader, which doesn't refuse because combat was
-- noted (another frame may have noted it first: Compat.lua); feeding never
-- runs in combat. Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local PC = {}
GP.PetCare = PC

PC.KEY = "petcare"
PC.NEVER = "petcare.never"
PC.FEED_PET, PC.CALL_PET = 6991, 883
PC.FOOD = { "tooltip", "bags", "both", "off" }
PC.FEED_AT = { "content", "unhappy" }
PC.LIMIT = { content = 2, unhappy = 1 }        -- at or below: hungry
PC.LEVEL_BAND = 10
PC.AWAY_DELAY = 10
PC.PASSIVE_TEXTURE = "PET_PASSIVE_TEXTURE"
PC.SLOTS = 10                                  -- NUM_PET_ACTION_SLOTS
PC.WORDS = { "Unhappy", "Content", "Happy" }   -- fallbacks for PET_HAPPINESS1-3
PC.WARNINGS = { dead = "Your pet is dead", none = "You have no pet out", passive = "Your pet is on Passive" }

local events = CreateFrame("Frame")
local state = {
    hunter = false,     -- decided at Enable
    announced = false,  -- this drop's chat line was said
    dismissed = false,  -- the player closed this drop's window
    petGUID = nil,      -- the last pet seen, plain
    seq = 0,            -- away timers' tokens
    away = nil,         -- the pending away timer's token
    awayRetry = false,  -- an away timer expired in combat
    awaySaid = false,   -- this absence was said (out of combat only)
    stable = false,     -- the stable master's window is open
    waiting = {},       -- [itemID] = true: asked the cache for it
    last = "nothing yet",
}
PC.state = state

local function Frame() return GP.PetCareFrame end
local function SS() return GP.SettingsSync end
local function setting(name) return GP.Pearls.Setting(PC.KEY, name) end
local function say(msg) API.Print(msg) end

local function plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

-- One client call's first value, plain; nil when it threw or is secret.
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return plain(v)
end

-- A yes/no read: true, false (plain nil included), or nil when it threw or
-- is secret.
local function flag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v and true or false
end

local function hunterPet()
    local ok, _, isHunter = pcall(HasPetUI)
    if not ok or API.IsSecret(isHunter) then return nil end
    return isHunter and true or false
end

local function happiness()
    local h = ask(C_PetInfo.GetPetHappiness)
    if type(h) ~= "number" or h % 1 ~= 0 or h < 1 or h > 3 then return nil end
    return h
end

-- The pet, out of combat: { exists, dead, hunter, happiness, level, guid },
-- each true / false / a plain value, or nil when it can't be told.
function PC.Pet()
    local p = { exists = flag(UnitExists, "pet") }
    if p.exists ~= true then return p end
    p.dead = flag(UnitIsDead, "pet")
    p.hunter = hunterPet()
    p.happiness = happiness()
    local level = ask(UnitLevel, "pet")
    p.level = type(level) == "number" and level > 0 and level or nil
    local guid = ask(UnitGUID, "pet")
    p.guid = type(guid) == "string" and guid or nil
    return p
end

-- Is the item plainly edible for the pet out now? true, false or nil.
function PC.Edible(id)
    if type(id) ~= "number" then return nil end
    return flag(C_PetInfo.CanPetEatItem, id)
end

function PC.Word(h)
    local w = rawget(_G, "PET_HAPPINESS" .. tostring(h))
    if type(w) == "string" and not API.IsSecret(w) and w ~= "" then return w end
    return PC.WORDS[h] or "?"
end

local function itemName(id, fallback)
    local n = ask(C_Item.GetItemNameByID, id)
    if type(n) == "string" and n ~= "" then return n end
    if type(fallback) == "string" and fallback ~= "" then return fallback end
    return "item " .. id
end
PC.ItemName = itemName

--------------------------------------------------------------------------------
-- The food choice

local function numSlots(bag)
    local n = ask(C_Container.GetContainerNumSlots, bag)
    return type(n) == "number" and n or 0
end

-- Ask the cache once per item; GET_ITEM_INFO_RECEIVED chooses again.
local function request(id)
    if state.waiting[id] then return end
    state.waiting[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
end

-- The candidates in bags 0-4, best first, and what was left out:
-- { never = n, uncached = n, locked = n } (distinct item IDs), plus every
-- edible ID's total count in the bags. `pet.level` orders the band.
function PC.Candidates(pet)
    local list, edible, totals = {}, {}, {}
    local never, uncached, locked = {}, {}, {}
    local Bags = GP.Bags
    for bag = Bags.FIRST, Bags.LAST do
        for slot = 1, numSlots(bag) do
            local s = Bags.Slot(bag, slot)
            if s then
                if edible[s.id] == nil then edible[s.id] = PC.Edible(s.id) == true end
                if edible[s.id] then
                    totals[s.id] = (totals[s.id] or 0) + s.count
                    local facts = Bags.ItemFacts(s.id)
                    if SS().SetHas(PC.NEVER, s.id) then
                        never[s.id] = true
                    elseif not (facts and facts.level) then
                        uncached[s.id] = true
                        request(s.id)
                    elseif not s.lockKnown or s.locked then
                        locked[s.id] = true
                    else
                        list[#list + 1] = { bag = bag, slot = slot, id = s.id, level = facts.level,
                            price = facts.price, icon = s.icon, name = s.name }
                    end
                end
            end
        end
    end
    local floor = pet and pet.level and (pet.level - PC.LEVEL_BAND)
    for _, c in ipairs(list) do c.within = floor ~= nil and c.level >= floor end
    table.sort(list, function(a, b)
        if a.within ~= b.within then return a.within end
        if a.within then
            if a.price ~= b.price then return a.price < b.price end
        elseif a.level ~= b.level then
            return a.level > b.level
        end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    for _, c in ipairs(list) do c.count = totals[c.id] end
    local function n(t) local k = 0; for _ in pairs(t) do k = k + 1 end; return k end
    -- A listed ID that also has a usable stack isn't "left out".
    for _, c in ipairs(list) do uncached[c.id], locked[c.id] = nil, nil end
    return list, { never = n(never), uncached = n(uncached), locked = n(locked) }
end

-- The food for the Feed button, or nil and what was left out.
function PC.ChooseFood(pet)
    local list, out = PC.Candidates(pet)
    return list[1], out
end

--------------------------------------------------------------------------------
-- The feeding reminder

-- "hungry" (a live hunter pet at or below the threshold), "fine" (plainly
-- above it), "gone" (no live hunter pet, plainly), or nil (can't tell); and
-- the pet read.
function PC.Mood()
    local p = PC.Pet()
    if p.exists == false or p.dead == true or (p.exists and p.hunter == false) then return "gone", p end
    if p.exists ~= true or p.dead ~= false or p.hunter ~= true or not p.happiness then return nil, p end
    local limit = PC.LIMIT[setting("feedAt")] or PC.LIMIT.content
    return p.happiness <= limit and "hungry" or "fine", p
end

local function rearm()
    state.announced, state.dismissed = false, false
end

-- Why there's no food to offer. Never "nothing to eat" when food was only
-- left out.
function PC.NoFood(out)
    out = out or {}
    local parts = {}
    if (out.never or 0) > 0 then parts[#parts + 1] = out.never .. " left out by your never-feed list" end
    if (out.uncached or 0) > 0 then parts[#parts + 1] = out.uncached .. " not loaded yet" end
    if (out.locked or 0) > 0 then parts[#parts + 1] = out.locked .. " busy" end
    if #parts == 0 then return "no food it eats in your bags" end
    return "no eligible food in your bags: " .. table.concat(parts, ", ")
end

-- The chat line for this drop.
function PC.Line(p, choice, out)
    local head = ("Your pet is %s: feed it"):format(PC.Word(p.happiness))
    if choice then
        return ("%s (%s, %d in your bags)."):format(head, itemName(choice.id, choice.name), choice.count or 0)
    end
    return head .. " (" .. PC.NoFood(out) .. ")."
end

-- Decide the feeding reminder now. Out of combat only.
function PC.UpdateFeed()
    if not (PC.enabled and state.hunter) then return end
    if not setting("feed") then return Frame().Close() end
    if API.InCombat() then return end          -- hidden for the fight; offered again after it
    local mood, p = PC.Mood()
    if p.guid and p.guid ~= state.petGUID then
        if state.petGUID then rearm() end      -- a new pet
        state.petGUID = p.guid
    end
    if mood == "fine" or mood == "gone" then
        rearm()
        state.last = mood == "fine" and "happy enough" or "no live hunter pet"
        return Frame().Close()
    end
    if mood ~= "hungry" or state.dismissed then return end
    local choice, out = PC.ChooseFood(p)
    if not state.announced then
        state.announced = true
        say(PC.Line(p, choice, out))
    end
    state.last = choice and ("offered " .. itemName(choice.id, choice.name)) or "no eligible food"
    Frame().Show({ happiness = p.happiness, word = PC.Word(p.happiness), choice = choice, out = out })
end

-- The player closed the window: not again in this drop.
function PC.Dismiss()
    state.dismissed = true
    state.last = "dismissed"
    Frame().Close()
end

-- May the Feed button act on `choice` now? true, or false and why. Read
-- again at the click (PetCareFrame's PreClick, which has already refused
-- lockdown). The cursor: GetCursorInfo answers for an item too.
function PC.CanFeed(choice)
    if not (PC.enabled and state.hunter and setting("feed")) then return false, "switched off" end
    if not (choice and Frame().IsShown()) then return false, "nothing to feed" end
    local ok, kind = pcall(GetCursorInfo)
    if not ok or API.IsSecret(kind) or kind ~= nil then return false, "the cursor holds something" end
    if flag(SpellIsTargeting) ~= false then return false, "another spell is waiting for a target" end
    local p = PC.Pet()
    if not (p.exists == true and p.dead == false and p.hunter == true) then return false, "no live pet" end
    local s = GP.Bags.Slot(choice.bag, choice.slot)
    if not (s and s.id == choice.id) then return false, "the food moved" end
    if not s.lockKnown or s.locked then return false, "the food is busy" end
    if PC.Edible(choice.id) ~= true then return false, "your pet won't eat it" end
    if SS().SetHas(PC.NEVER, choice.id) then return false, "on your never-feed list" end
    if ask(C_Spell.IsSpellUsable, PC.FEED_PET) ~= true then return false, "Feed Pet can't be cast now" end
    return true
end

-- The click was refused: choose again.
function PC.Refused(why)
    state.last = "Feed refused: " .. tostring(why)
    PC.UpdateFeed()
end

function PC.Fed(choice)
    state.last = "fed " .. itemName(choice.id, choice.name)
end

-- Never feed `id`: on the synced list, then choose again.
function PC.Never(id)
    local ok, why = SS().SetAdd(PC.NEVER, id)
    if not ok then return false, why end
    PC.UpdateFeed()
    return true
end

function PC.Forget(id)
    SS().SetRemove(PC.NEVER, id)
    PC.UpdateFeed()
end

--------------------------------------------------------------------------------
-- The pet checks

-- The Passive stance: true (the Passive token is active), false (the bar
-- reads plainly without it), or nil (unreadable).
function PC.Passive()
    for i = 1, PC.SLOTS do
        local ok, _, texture, isToken, isActive = pcall(GetPetActionInfo, i)
        if not ok or API.IsSecret(texture) or API.IsSecret(isToken) or API.IsSecret(isActive) then return nil end
        if isToken and texture == PC.PASSIVE_TEXTURE then return isActive and true or false end
    end
    return false
end

-- What to warn about now: "dead", "none", "passive", or nil. Reads only what
-- it needs and never refuses because combat was noted: the fight start and
-- the ready check use it in combat. Anything unreadable is silence.
function PC.Warning(missing, passive)
    if not (missing or passive) then return nil end
    if flag(IsPlayerSpell, PC.CALL_PET) ~= true then return nil end
    local exists = flag(UnitExists, "pet")
    if exists == nil then return nil end
    if not exists then return missing and "none" or nil end
    local dead = flag(UnitIsDead, "pet")
    if dead == nil then return nil end
    if dead then return missing and "dead" or nil end
    if not passive or hunterPet() ~= true then return nil end
    return PC.Passive() == true and "passive" or nil
end

local function warn(w, trigger)
    state.last = ("%s (%s)"):format(PC.WARNINGS[w], trigger)
    say(PC.WARNINGS[w] .. ".")
    GP.Notice.Show(PC.WARNINGS[w])
end

-- One check at `trigger` ("fight" or "ready"); the warning said, or nil.
function PC.PetCheck(trigger)
    if not (PC.enabled and state.hunter) then return nil end
    local w = PC.Warning(setting("missing"), setting("passive"))
    if w then warn(w, trigger) end
    return w
end

-- Out of combat, is now a time the pet may plainly be away? true when any
-- reason to stay quiet is plainly true or can't be told.
function PC.Quiet()
    if state.stable then return true end
    if flag(UnitIsDeadOrGhost, "player") ~= false then return true end
    if flag(UnitOnTaxi, "player") ~= false then return true end
    if flag(IsMounted) ~= false then return true end
    if flag(UnitIsFeignDeath, "player") ~= false then return true end
    if flag(HasFullControl) ~= true then return true end
    if flag(UnitExists, "pet") == true and flag(UnitIsPossessed, "pet") ~= false then return true end
    return false
end

-- The away check: missing or dead only, once per absence.
function PC.AwayCheck()
    if not (PC.enabled and state.hunter and setting("away") and setting("missing")) then return nil end
    local exists, dead = flag(UnitExists, "pet"), flag(UnitIsDead, "pet")
    if exists == true and dead == false then
        state.awaySaid = false                 -- a live pet: the next absence is new
        return nil
    end
    if state.awaySaid or PC.Quiet() then return nil end
    local w = PC.Warning(true, false)
    if w then
        state.awaySaid = true
        warn(w, "away")
    end
    return w
end

local function awayTimer(token)
    if state.away ~= token then return end     -- replaced, switched off or left the world
    state.away = nil
    if API.InCombat() then
        state.awayRetry = true
        return
    end
    PC.AwayCheck()
end

-- (The timer reads the switch: AwayCheck.)
local function scheduleAway()
    state.seq = state.seq + 1
    local token = state.seq
    state.away, state.awayRetry = token, false
    C_Timer.After(PC.AWAY_DELAY, function() awayTimer(token) end)
end

local function stopAway()
    state.seq = state.seq + 1
    state.away, state.awayRetry = nil, false
end

--------------------------------------------------------------------------------
-- Events

local AWAY_TRIGGERS = { PLAYER_ENTERING_WORLD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true,
    PLAYER_CONTROL_GAINED = true }

local function unitIs(arg, unit) return not API.IsSecret(arg) and arg == unit end

events:SetScript("OnEvent", function(_, event, arg1)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Before lockdown: the window (and its secure button) can still be hidden.
        Frame().Close("combat")
        if setting("atFight") then PC.PetCheck("fight") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        Frame().AfterCombat()
        if state.awayRetry then
            state.awayRetry = false
            PC.AwayCheck()
        end
        PC.UpdateFeed()
    elseif event == "READY_CHECK" then
        if setting("atReady") then PC.PetCheck("ready") end
    elseif event == "UNIT_PET" then
        if not unitIs(arg1, "player") then return end
        if flag(UnitExists, "pet") == true and flag(UnitIsDead, "pet") == false then state.awaySaid = false end
        scheduleAway()
        Frame().Marks()
        PC.UpdateFeed()
    elseif event == "UNIT_HAPPINESS" then
        if unitIs(arg1, "pet") then PC.UpdateFeed() end
    elseif event == "UNIT_FLAGS" then
        if unitIs(arg1, "pet") then scheduleAway() end
    elseif event == "BAG_UPDATE_DELAYED" then
        PC.UpdateFeed()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if API.IsSecret(arg1) or not state.waiting[arg1] then return end
        state.waiting[arg1] = nil
        PC.UpdateFeed()
    elseif event == "PET_STABLE_SHOW" then
        state.stable = true
    elseif event == "PET_STABLE_CLOSED" then
        state.stable = false
    elseif event == "PLAYER_LEAVING_WORLD" then
        stopAway()
        state.stable = false
    elseif AWAY_TRIGGERS[event] then
        scheduleAway()
        if event == "PLAYER_ENTERING_WORLD" then PC.UpdateFeed() end
    end
end)

PC.EVENTS = { "UNIT_PET", "UNIT_HAPPINESS", "UNIT_FLAGS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "READY_CHECK", "PET_STABLE_SHOW", "PET_STABLE_CLOSED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_GAINED" }

--------------------------------------------------------------------------------
-- Commands

local function itemIDOf(arg)
    if type(arg) ~= "string" then return nil end
    return tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^%s*(%d+)%s*$"))
end

local function yesno(v) if v == nil then return "?" end return v and "yes" or "no" end

function PC.Report()
    if not state.hunter then return say("Hunter pet care: for hunters only.") end
    local p = PC.Pet()
    say(("Hunter pet care: %s. Pet: out %s, dead %s, hunter pet %s, happiness %s, level %s."):format(
        PC.enabled and "on" or "off", yesno(p.exists), yesno(p.dead), yesno(p.hunter),
        p.happiness and (p.happiness .. " " .. PC.Word(p.happiness)) or "?", tostring(p.level or "?")))
    say(("  Feed reminder %s, at %s or below; announced %s, dismissed %s."):format(
        setting("feed") and "on" or "off", PC.Word(PC.LIMIT[setting("feedAt")] or 2), yesno(state.announced),
        yesno(state.dismissed)))
    local list, out = PC.Candidates(p)
    if #list == 0 then
        say("  Food: none eligible.")
    else
        for i = 1, math.min(#list, 5) do
            local c = list[i]
            say(("  %d. %s (bag %d slot %d): level %d, %d each%s."):format(i, itemName(c.id, c.name), c.bag, c.slot,
                c.level, c.price, c.within and ", within the band" or ""))
        end
    end
    say(("  Left out: %d on the never-feed list, %d not loaded, %d busy."):format(out.never, out.uncached, out.locked))
    say(("  Passive: %s. Warning now: %s. Away: %s%s."):format(yesno(PC.Passive()),
        tostring(PC.Warning(true, true) or "none"), setting("away") and "on" or "off",
        state.awaySaid and " (said for this absence)" or ""))
    say("  Last: " .. state.last .. ".")
end

local function command(arg)
    arg = arg or ""
    local verb, rest = arg:match("^(%S*)%s*(.-)$")
    if verb == "test" then
        Frame().Show({ happiness = 2, word = PC.Word(2), choice = PC.ChooseFood(PC.Pet()),
            out = { never = 0, uncached = 0, locked = 0 }, test = true })
        return say("Hunter pet care: the feed window, as a test.")
    elseif verb == "never" then
        local id = itemIDOf(rest) or (Frame().Choice() and Frame().Choice().id)
        if not id then return say("Shift-click a food into chat after /gpearls petcare never.") end
        local ok, why = PC.Never(id)
        if not ok then
            return say(why == "full" and "The lists are full: remove some first." or "Couldn't list that item.")
        end
        return say(itemName(id) .. " will never be chosen for the Feed button.")
    elseif verb == "forget" then
        local id = itemIDOf(rest)
        if not id then return say("Shift-click a food into chat after /gpearls petcare forget.") end
        PC.Forget(id)
        return say(itemName(id) .. ": off the never-feed list.")
    end
    PC.Report()
end

--------------------------------------------------------------------------------
-- The pearl

local function isHunter()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and not API.IsSecret(class) and class == "HUNTER"
end

local function enable()
    PC.enabled = true
    state.hunter = isHunter()
    if not state.hunter then return end        -- other classes: nothing at all
    API.RegisterEvents(events, PC.EVENTS)
    Frame().Start()
    PC.UpdateFeed()
end

local function disable()
    PC.enabled = false
    events:UnregisterAllEvents()
    stopAway()
    state.stable = false
    rearm()
    if state.hunter then
        Frame().Close()
        Frame().Marks()
    end
end

GP.SettingsSync.RegisterSet(PC.NEVER)

GP.Pearls.Register({
    key = PC.KEY,
    name = "Hunter pet care",
    desc = "Reminds you to feed your pet, shows what it eats, and warns when it's missing, dead or on Passive.",
    help = "For hunters. When your pet drops to Content (or, by the setting, only Unhappy): a line in your chat and a "
        .. "small window with a Feed button that feeds it the food chosen from your bags (the cheapest within 10 "
        .. "levels of your pet, else the highest level; \"Never feed this\" leaves a food out on all your "
        .. "characters). Out of combat only. What your pet eats: a line in item tooltips, a mark on your bag "
        .. "buttons, or both. Pet checks: \"Your pet is dead\", \"You have no pet out\" or \"Your pet is on "
        .. "Passive\", at the start of a fight, at a ready check, or out of combat when it disappears (each a "
        .. "checkbox; the last warns once after a deliberate Dismiss Pet too). /gpearls petcare shows what it reads; "
        .. "never and forget manage the list. Unverified until the game is live.",
    default = true,
    category = "Combat",
    section = "Pets",
    defaults = { food = "tooltip", feed = true, feedAt = "content", missing = true, passive = true,
        atFight = true, atReady = true, away = false },
    choices = { food = PC.FOOD, feedAt = PC.FEED_AT },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.PetCareFrame.Configure(panel, refreshers) end,
    onSettingChanged = function(name)
        if not (PC.enabled and state.hunter) then return end
        if name == "food" then Frame().Start(); Frame().Marks() end
        if name == "away" and not setting("away") then stopAway() end
        PC.UpdateFeed()
    end,
    commands = { petcare = { help = "[never <item> | forget <item> | test] - what hunter pet care reads, its "
        .. "never-feed list, or show the feed window", run = command } },
})

PC._test = { events = events, awayTimer = awayTimer }
