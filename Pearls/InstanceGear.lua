-- Pearls/InstanceGear.lua: instance gear reminders (#43). On entering an
-- instance, a reminder for the gear it calls for: a chat line and a short
-- centre text (Core/Notice.lua), nothing to click.
--
-- The first case: Scholomance (map 289) and Stratholme (329) without an
-- Argent Dawn trinket worn, below Exalted with the Argent Dawn (faction 529;
-- "also at Exalted" is a setting), when one is carried ("equip it") or in
-- the bank ("it's in your bank"). The items are every trinket whose spell
-- allows Scourgestones (the client's Spell table): the Commission 12846
-- (spell 17670), the Seal 13209 (23930) and Rune 19812 (24198) of the Dawn,
-- and the two Marks of the Champion 23206 / 23207 (29112 / 29113). The Seal
-- and the Rune aren't in ItemSparse yet; listed, they can only ever silence.
--
-- One check per entry: an entry runs from PLAYER_ENTERING_WORLD to the next
-- PLAYER_LEAVING_WORLD; a duplicate PEW is ignored; the check runs DELAY s
-- after the PEW, only when isReloadingUi is plainly false, and re-reads
-- everything then. Every read is plain or the answer is silence.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local IG = {}
GP.InstanceGear = IG

IG.KEY = "instancegear"
IG.DELAY = 5
IG.CASES = {
    { key = "argentdawn", label = "Argent Dawn trinket", instances = { 289, 329 },
      faction = { id = 529, below = 8 }, always = "exalted",
      items = { 23206, 23207, 19812, 13209, 12846 }, slots = { 13, 14 },
      fallback = "Argent Dawn trinket", factionFallback = "Argent Dawn",
      equipWhy = "Scourgestones drop only while it's on", bankWhy = "Scourgestones drop only while it's equipped" },
}

local events = CreateFrame("Frame")
local state = { entry = nil, seq = 0 }
IG.state = state

local function setting(name) return GP.Pearls.Setting(IG.KEY, name) end

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

local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- A count, plain, whole and not negative; nil when it can't be told.
local function count(id, bank)
    local ok, n = pcall(C_Item.GetItemCount, id, bank)
    if not ok or API.IsSecret(n) or type(n) ~= "number" or n < 0 or n % 1 ~= 0 then return nil end
    return n
end

-- The instance: name, type, map ID (each plain or nil).
function IG.Instance()
    local ok, name, kind, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if not ok then return nil end
    return plain(name), plain(kind), plain(id)
end

-- The faction's reaction (1-8) and name, or nil.
local function standing(id)
    local data = ask(C_Reputation.GetFactionDataByID, id)
    if type(data) ~= "table" then return nil end
    local reaction, name = plain(data.reaction), plain(data.name)
    if type(reaction) ~= "number" or reaction % 1 ~= 0 or reaction < 1 or reaction > 8 then return nil end
    return reaction, type(name) == "string" and name ~= "" and name or nil
end

-- What to say for `case` now: { kind = "equip" | "bank", item, reaction,
-- faction } or nil and why not.
function IG.Evaluate(case)
    if not setting(case.key) then return nil, "switched off" end
    local _, kind, map = IG.Instance()
    if type(kind) ~= "string" or kind == "none" then return nil, "not in an instance" end
    if not has(case.instances, map) then return nil, "not one of its instances" end
    local reaction, faction
    if case.faction then
        reaction, faction = standing(case.faction.id)
        if not reaction then return nil, "standing unreadable" end
        if reaction >= case.faction.below and not setting(case.always) then return nil, "Exalted" end
    end
    for _, slot in ipairs(case.slots) do
        local ok, worn = pcall(GetInventoryItemID, "player", slot)
        if not ok or API.IsSecret(worn) or (worn ~= nil and type(worn) ~= "number") then
            return nil, "slot " .. slot .. " unreadable"
        end
        if has(case.items, worn) then return nil, "worn" end
    end
    -- Nothing listed is worn, so a count (carried and worn) is what's carried.
    for _, item in ipairs(case.items) do
        local n = count(item, false)
        if n and n > 0 then return { kind = "equip", item = item, reaction = reaction, faction = faction } end
    end
    for _, item in ipairs(case.items) do
        local n, all = count(item, false), count(item, true)
        if n and all and all - n > 0 then return { kind = "bank", item = item, reaction = reaction, faction = faction } end
    end
    return nil, "none carried or in the bank"
end

-- The chat line and the centre text for a result.
function IG.Texts(case, r)
    local name = ask(C_Item.GetItemNameByID, r.item)
    if type(name) ~= "string" or name == "" then name = case.fallback end
    if r.kind == "bank" then
        local short = ("Your %s is in your bank"):format(name)
        return short .. ": " .. case.bankWhy .. ".", short
    end
    local short = ("Equip your %s"):format(name)
    local line = short .. ": " .. case.equipWhy
    if case.faction and r.reaction and r.reaction < case.faction.below then
        line = line .. (" (you're below Exalted with the %s)"):format(r.faction or case.factionFallback)
    end
    return line .. ".", short
end

function IG.Check(token)
    if state.entry ~= token then return end           -- left, a newer entry, or switched off
    for _, case in ipairs(IG.CASES) do
        local r = IG.Evaluate(case)
        if r then
            local line, short = IG.Texts(case, r)
            API.Print(line)
            GP.Notice.Show(short)
        end
    end
end

events:SetScript("OnEvent", function(_, event, _, isReloadingUi)
    if event == "PLAYER_LEAVING_WORLD" then
        state.entry = nil
        return
    end
    if state.entry then return end                     -- a duplicate PEW
    state.seq = state.seq + 1
    local token = state.seq
    state.entry = token
    if API.IsSecret(isReloadingUi) or isReloadingUi ~= false then return end
    C_Timer.After(IG.DELAY, function() IG.Check(token) end)
end)

--------------------------------------------------------------------------------
-- The report

local function report(arg)
    if arg == "test" then
        GP.Notice.Show("Equip your " .. IG.CASES[1].fallback)
        API.Print("Instance gear: the centre text, as a test.")
        return
    end
    local name, kind, map = IG.Instance()
    API.Print(("Instance gear: %s; here: %s (%s, %s)."):format(IG.enabled and "on" or "off", tostring(name),
        tostring(kind), tostring(map)))
    for _, case in ipairs(IG.CASES) do
        local parts = {}
        if case.faction then
            local reaction, fname = standing(case.faction.id)
            parts[#parts + 1] = ("standing %s (%s)"):format(tostring(reaction), tostring(fname))
        end
        for _, slot in ipairs(case.slots) do
            parts[#parts + 1] = ("slot %d %s"):format(slot, tostring(ask(GetInventoryItemID, "player", slot) or "empty"))
        end
        API.Print(("  %s (%s): %s."):format(case.label, setting(case.key) and "on" or "off", table.concat(parts, ", ")))
        for _, item in ipairs(case.items) do
            local n, all = count(item, false), count(item, true)
            API.Print(("    %d: carried + worn %s, with bank %s%s."):format(item, tostring(n), tostring(all),
                (n and all) and (", bank " .. (all - n)) or ""))
        end
        local r, why = IG.Evaluate(case)
        if r then
            API.Print("    Now: " .. (IG.Texts(case, r)))
        else
            API.Print("    Now: nothing (" .. why .. ").")
        end
    end
end

--------------------------------------------------------------------------------
-- The pearl

local function enable()
    IG.enabled = true
    API.RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD" })
end

local function disable()
    IG.enabled = false
    events:UnregisterAllEvents()
    state.entry = nil
end

GP.Pearls.Register({
    key = IG.KEY,
    name = "Instance gear reminders",
    desc = "Reminds you of the gear an instance calls for, as you enter it.",
    help = "In Scholomance and Stratholme, when no Argent Dawn trinket is equipped (Scourgestones drop only while one "
        .. "is) and you're below Exalted with the Argent Dawn: \"Equip your Argent Dawn Commission\" when it's in your "
        .. "bags, or \"it's in your bank\". A line in your chat and a short text in the middle of the screen, 5 seconds "
        .. "after the loading screen, once per entry; not after a /reload inside. \"Also at Exalted\" keeps it on "
        .. "for the Valor Tokens. /gpearls instancegear shows what it reads now. Unverified until the game is live.",
    default = true,
    category = "Combat",
    section = "Instances",
    defaults = { argentdawn = true, exalted = false },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) GP.InstanceGearFrame.Configure(panel, refreshers) end,
    commands = { instancegear = { help = "[test] - what the instance gear reminders read here, or show the text",
        run = report } },
})

IG._test = { events = events }
