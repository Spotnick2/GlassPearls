-- Pearls/Training.lua: the training reminder (#27). When you level, a toast
-- lists what your class trainer now teaches you (and, smaller, what was
-- already waiting), the talent points the client says are unspent, and what
-- your other spec could learn; spell tooltips say when the next ranks come.
-- The toast and the panel are Pearls/TrainingFrame.lua; the trainer lists are
-- Data/Training.lua (WhatsTraining's curated Forever lists, generated).
--
-- A spell is listed only when it is provably learnable: its level reached,
-- every required spell known, its talent known, no skill requirement (rogue
-- poisons need the Poisons skill, which isn't read), and itself provably not
-- known. Known = C_SpellBook.IsSpellKnown, IsSpellInSpellBook (no overrides)
-- or IsPlayerSpell, or a later member of its override group or rank group
-- known (druid forms and warrior stances hide lower ranks). A read that
-- throws or answers a secret is "can't tell": never listed. IDs only; the
-- names are the client's.
--
-- Dual spec, by remembering: while a spec group is active, the talents and
-- talent ranks it knows are recorded per character. Classic only lets you
-- change a spec's talents, or learn its talent ranks, while it is active, so
-- the record stays true; another group's waiting ranks are shown as last seen.
-- A group never seen active says nothing (measured: one group at 70245).
--
-- Talent points: C_Traits' tree currency for the active config, shown only
-- when plain and sane, so the Legacy talent "Talented" (points from an
-- earlier level) counts without our knowing its rank. Unmeasured until
-- 2026-11-04.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local T = {}
GP.Training = T

T.KEY = "training"
T.LEVEL_DELAY = 1                -- after PLAYER_LEVEL_UP
T.SWAP_DELAY = 2                 -- after a spec swap, for the spells to settle
T.REMEMBER_DELAY = 1             -- SPELLS_CHANGED, coalesced
T.MAX_POINTS = 51

local events = CreateFrame("Frame")
local state = {
    level = nil,        -- the level last seen
    pending = nil,      -- level-ups waiting for LEVEL_DELAY: { prev, level }
    held = nil,         -- a toast waiting for the end of combat: { kind, prev, level }
    shown = nil,        -- the open toast's { kind, prev, level }, for refreshes
    gen = 0,            -- the remember timer's generation
    hooked = false,     -- the tooltip post call is in (it can't be removed)
}
T.state = state

local function setting(name) return GP.Pearls.Setting(T.KEY, name) end
local function Frame() return GP.TrainingFrame end

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

--------------------------------------------------------------------------------
-- The player

function T.Class()
    local ok, _, classFile = pcall(UnitClass, "player")
    return ok and plain(classFile, "string") or nil
end

function T.Level()
    local ok, l = pcall(UnitLevel, "player")
    l = ok and plain(l, "number")
    return l and l > 0 and l or nil
end

local function race()
    local ok, _, _, id = pcall(UnitRace, "player")
    return ok and plain(id, "number") or nil
end

local function faction()
    local ok, f = pcall(UnitFactionGroup, "player")
    return ok and plain(f, "string") or nil
end

function T.SpecGroup()
    local SI = rawget(_G, "C_SpecializationInfo")
    if not (SI and SI.GetActiveSpecGroup) then return nil end
    local ok, g = pcall(SI.GetActiveSpecGroup)
    return ok and plain(g, "number") or nil
end

local function data()
    local d = GP.TrainingData
    local class = T.Class()
    return d and class and d.classes[class] or nil
end

--------------------------------------------------------------------------------
-- Knowing a spell

-- One spell, read directly: true (any route says so), false (every route
-- answered plainly false), or nil (can't tell: an error or a secret).
local function readKnown(id)
    local SB = rawget(_G, "C_SpellBook")
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local routes, falses = 0, 0
    local function ask(fn, ...)
        if not fn then return false end
        routes = routes + 1
        local ok, v = pcall(fn, ...)
        if not ok or API.IsSecret(v) then return false end
        if v == false then falses = falses + 1 end
        return v == true
    end
    if ask(SB and SB.IsSpellKnown, id, bank) or ask(SB and SB.IsSpellInSpellBook, id, bank, false)
        or ask(rawget(_G, "IsPlayerSpell"), id) then
        return true
    end
    if routes > 0 and falses == routes then return false end
    return nil
end

-- The spells after `id` whose knowledge implies it: later members of its
-- override groups and higher ranks of its rank group. Built per class.
local later, laterClass
local function laterOf(id)
    local class = T.Class()
    if laterClass ~= class then
        later, laterClass = {}, class
        local function add(list)
            for i, a in ipairs(list) do
                for j = i + 1, #list do
                    later[a] = later[a] or {}
                    table.insert(later[a], list[j])
                end
            end
        end
        local d = data()
        for _, g in ipairs(d and d.groups or {}) do add(g) end
        local ranks = GP.SpellRankData
        if ranks and d then
            local mine = {}
            for _, e in ipairs(d.spells) do mine[e.id] = true end
            for _, g in ipairs(ranks.groups) do
                for _, sid in ipairs(g) do
                    if mine[sid] then add(g) break end
                end
            end
        end
    end
    return later[id]
end

-- A memo for one evaluation: true / false / nil (can't tell), with the
-- later-known rule.
function T.KnownReader()
    local memo = {}
    local function direct(id)
        if memo[id] == nil then
            local v = readKnown(id)
            memo[id] = v == nil and "?" or v
        end
        local v = memo[id]
        if v == "?" then return nil end
        return v
    end
    return function(id)
        local v = direct(id)
        if v == true then return true end
        local anyUnknown = v == nil
        for _, l in ipairs(laterOf(id) or {}) do
            local lv = direct(l)
            if lv == true then return true end
            if lv == nil then anyUnknown = true end
        end
        if anyUnknown then return nil end
        return false
    end
end

--------------------------------------------------------------------------------
-- What a trainer entry is to you

-- ctx = { level, race, faction, known = T.KnownReader() }. nil: not for you
-- (race, faction); else "known", "available", "later", "talent", "req",
-- "skill" or "unknown" (can't tell: never listed).
function T.Status(e, ctx)
    if e.race and e.race ~= ctx.race then return nil end
    if e.faction and e.faction ~= ctx.faction then return nil end
    local k = ctx.known(e.id)
    if k == true then return "known" end
    if k == nil then return "unknown" end
    if e.level > ctx.level then return "later" end
    if e.talent then
        local t = ctx.known(e.talent)
        if t == nil then return "unknown" end
        if not t then return "talent" end
    end
    if e.skill then return "skill" end
    local unsure = false
    for _, r in ipairs(e.req or {}) do
        local rk = ctx.known(r)
        if rk == false then return "req" end
        if rk == nil then unsure = true end
    end
    return unsure and "unknown" or "available"
end

function T.Context(level)
    return { level = level or T.Level() or 1, race = race(), faction = faction(), known = T.KnownReader() }
end

local function byLevel(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.id < b.id
end

-- The rank number of a spell, from the client's rank groups, or nil.
function T.Rank(id)
    local r = GP.SpellRankData and GP.SpellRankData.ranks[id]
    return r and r[2] or nil
end

--------------------------------------------------------------------------------
-- Talent points and the other spec

-- Unspent talent points, or nil when the client doesn't say plainly.
function T.TalentPoints()
    local CT, TR = rawget(_G, "C_ClassTalents"), rawget(_G, "C_Traits")
    if not (CT and CT.GetActiveConfigID and TR and TR.GetConfigInfo and TR.GetTreeCurrencyInfo) then return nil end
    local ok, cfg = pcall(CT.GetActiveConfigID)
    cfg = ok and plain(cfg, "number")
    if not cfg then return nil end
    local ok2, info = pcall(TR.GetConfigInfo, cfg)
    if not ok2 or API.IsSecret(info) or type(info) ~= "table" then return nil end
    local trees = info.treeIDs
    if API.IsSecret(trees) or type(trees) ~= "table" then return nil end
    local tree = plain(trees[1], "number")
    if not tree then return nil end
    local ok3, cur = pcall(TR.GetTreeCurrencyInfo, cfg, tree, false)
    if not ok3 or API.IsSecret(cur) or type(cur) ~= "table" then return nil end
    local first = cur[1]
    if API.IsSecret(first) or type(first) ~= "table" then return nil end
    local q = plain(first.quantity, "number")
    if not q or q < 0 or q > T.MAX_POINTS or q ~= math.floor(q) then return nil end
    return q
end

local function memory()
    if not GP.charDB then return nil end
    local m = GP.charDB.training
    if type(m) ~= "table" then
        m = {}
        GP.charDB.training = m
    end
    if type(m.groups) ~= "table" then m.groups = {} end
    return m
end

-- Record what the active spec group knows of its talents and talent ranks.
-- Only plain answers change the record.
function T.Remember()
    local g, d, m = T.SpecGroup(), data(), memory()
    if not (g and d and m) then return end
    local rec = m.groups[g]
    if type(rec) ~= "table" then
        rec = { talents = {}, ranks = {} }
        m.groups[g] = rec
    end
    local known = T.KnownReader()
    for _, e in ipairs(d.spells) do
        if e.talent then
            local t = known(e.talent)
            if t == true then rec.talents[e.talent] = true elseif t == false then rec.talents[e.talent] = nil end
            local k = known(e.id)
            if k == true then rec.ranks[e.id] = true elseif k == false then rec.ranks[e.id] = nil end
        end
    end
end

-- Another spec group's waiting talent ranks, as last seen:
-- { { group, talent, spells = { entries } }, ... }.
function T.OtherSpec(ctx)
    local out = {}
    local g, d, m = T.SpecGroup(), data(), memory()
    if not (g and d and m) then return out end
    local groups = {}
    for h in pairs(m.groups) do
        if type(h) == "number" and h ~= g then groups[#groups + 1] = h end
    end
    table.sort(groups)
    for _, h in ipairs(groups) do
        local rec, byTalent, order = m.groups[h], {}, {}
        for _, e in ipairs(d.spells) do
            if e.talent and rec.talents[e.talent] and not rec.ranks[e.id] and e.level <= ctx.level
                and not (e.race and e.race ~= ctx.race) and not (e.faction and e.faction ~= ctx.faction) then
                if not byTalent[e.talent] then
                    byTalent[e.talent] = { group = h, talent = e.talent, spells = {} }
                    order[#order + 1] = e.talent
                end
                table.insert(byTalent[e.talent].spells, e)
            end
        end
        for _, t in ipairs(order) do
            table.sort(byTalent[t].spells, byLevel)
            out[#out + 1] = byTalent[t]
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The toast's contents

-- kind "level": new = learnable entries above `prev`, up to `level`; waiting
-- = learnable from before. kind "swap": new = learnable talent ranks.
-- kind "list": everything learnable as waiting.
function T.Collect(kind, prev, level)
    local d = data()
    local view = { kind = kind, level = level, new = {}, waiting = {}, other = {}, cost = 0 }
    if not d then return view end
    local ctx = T.Context(level)
    for _, e in ipairs(d.spells) do
        if T.Status(e, ctx) == "available" then
            local isNew = (kind == "level" and prev and e.level > prev) or (kind == "swap" and e.talent ~= nil)
            if isNew then view.new[#view.new + 1] = e else view.waiting[#view.waiting + 1] = e end
        end
    end
    table.sort(view.new, byLevel)
    table.sort(view.waiting, byLevel)
    if not setting("waiting") and kind ~= "list" then view.waiting = {} end
    for _, e in ipairs(view.new) do view.cost = view.cost + e.cost end
    for _, e in ipairs(view.waiting) do view.cost = view.cost + e.cost end
    view.other = T.OtherSpec(ctx)
    if setting("points") then view.points = T.TalentPoints() end
    if view.points == 0 then view.points = nil end
    return view
end

local function empty(view)
    return #view.new == 0 and #view.waiting == 0 and #view.other == 0 and not view.points
end

-- A level-up toast not yet seen through (held, or still open) is extended,
-- never replaced: the earliest prev and the latest level, so every spell of a
-- run of level-ups stays new. A swap never replaces a held level-up.
local function combine(old, kind, prev, level)
    if not (old and old.kind == "level") then return kind, prev, level end
    if kind ~= "level" then return old.kind, old.prev, old.level end
    return kind, math.min(old.prev, prev), math.max(old.level, level)
end

-- Show the toast now, or after combat. Nothing to say: no toast.
function T.Show(kind, prev, level)
    if not T.enabled then return end
    if API.InCombat() then
        kind, prev, level = combine(state.held, kind, prev, level)
        state.held = { kind = kind, prev = prev, level = level }
        return
    end
    if kind == "level" and Frame().IsShown() then
        kind, prev, level = combine(state.shown, kind, prev, level)
    end
    local view = T.Collect(kind, prev, level or T.Level())
    if empty(view) then return end
    state.shown = { kind = kind, prev = prev, level = view.level }
    Frame().Show(view)
end

-- The open toast, read again (a spell learned, a point spent).
function T.Refresh()
    local s = state.shown
    if not (s and Frame().IsShown()) then return end
    local view = T.Collect(s.kind, s.prev, s.level)
    if empty(view) then
        state.shown = nil
        return Frame().Hide()
    end
    Frame().Show(view, true)
end

--------------------------------------------------------------------------------
-- The tooltip

-- The lines for a spell's tooltip: { { text, r, g, b }, ... }.
function T.TooltipLines(id)
    local lines = {}
    local d, ranks = data(), GP.SpellRankData
    local r = ranks and ranks.ranks[id]
    if not (d and r) then return lines end
    local entries = {}
    for _, e in ipairs(d.spells) do entries[e.id] = e end
    local ctx = T.Context()
    local now, coming, talentNeed = {}, {}, nil
    for _, sid in ipairs(ranks.groups[r[1]]) do
        local e = entries[sid]
        local rank = T.Rank(sid)
        if e and rank and rank > r[2] then
            local s = T.Status(e, ctx)
            if s == "available" then
                now[#now + 1] = rank
            elseif s == "later" then
                coming[#coming + 1] = ("%d at %d"):format(rank, e.level)
            elseif s == "talent" and not talentNeed then
                talentNeed = { rank, e.talent }
            end
        end
    end
    local word = rawget(_G, "RANK") or "Rank"
    if #now > 0 then
        lines[#lines + 1] = { word .. " " .. table.concat(now, ", ") .. ": at your trainer now", 0.25, 1, 0.25 }
    end
    if talentNeed then
        local ok, n = pcall(C_Spell.GetSpellName, talentNeed[2])
        n = ok and plain(n, "string") or ("spell " .. talentNeed[2])
        lines[#lines + 1] = { word .. " " .. talentNeed[1] .. " needs " .. n, 1, 0.5, 0.25 }
    end
    if #coming > 0 then
        local text = "Next " .. word:lower() .. ": " .. coming[1]
        if #coming > 1 then text = text .. " (then " .. table.concat(coming, ", ", 2, math.min(#coming, 5)) .. ")" end
        lines[#lines + 1] = { text, 0.6, 0.8, 1 }
    end
    return lines
end

local function onTooltip(tooltip, tooltipData)
    if not (T.enabled and setting("tooltip")) then return end
    if API.IsSecret(tooltipData) or type(tooltipData) ~= "table" then return end
    local id = plain(tooltipData.id, "number")
    if not id or not tooltip or not tooltip.AddLine then return end
    for _, l in ipairs(T.TooltipLines(id)) do tooltip:AddLine(l[1], l[2], l[3], l[4]) end
end

local function hookTooltips()
    if state.hooked then return end
    local TDP = rawget(_G, "TooltipDataProcessor")
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell
    if not (TDP and TDP.AddTooltipPostCall and kind) then
        return API.Fail("pearl training tooltip", "TooltipDataProcessor missing")
    end
    local ok, err = pcall(TDP.AddTooltipPostCall, kind, function(...)
        local ok2, err2 = pcall(onTooltip, ...)
        if not ok2 then API.Fail("pearl training tooltip", err2) end
    end)
    if ok then state.hooked = true else API.Fail("pearl training tooltip", err) end
end

--------------------------------------------------------------------------------
-- Commands

local function label(e)
    local ok, n = pcall(C_Spell.GetSpellName, e.id)
    n = ok and plain(n, "string") or ("spell " .. e.id)
    local rank = T.Rank(e.id)
    return rank and (n .. " " .. rank) or n
end
T.Label = label

local function names(list, max)
    local out = {}
    for i, e in ipairs(list) do
        if i > max then
            out[#out + 1] = ("+%d more"):format(#list - max)
            break
        end
        out[#out + 1] = label(e)
    end
    return table.concat(out, ", ")
end

function T.Report()
    if not data() then return API.Print("Training reminder: no trainer list for your class.") end
    local level = T.Level() or 1
    local view = T.Collect("list", nil, level)
    API.Print(("Training reminder, level %d:"):format(level))
    if #view.waiting > 0 then
        API.Print("  At your trainer: " .. names(view.waiting, 20) .. "  (" .. Frame().Money(view.cost) .. ")")
    else
        API.Print("  Nothing to learn at your trainer right now.")
    end
    local ctx, needTalent, nextLevel = T.Context(level), {}, nil
    for _, e in ipairs(data().spells) do
        local s = T.Status(e, ctx)
        if s == "talent" then needTalent[#needTalent + 1] = e end
        if s == "later" and (not nextLevel or e.level < nextLevel) then nextLevel = e.level end
    end
    if nextLevel then
        local at = {}
        for _, e in ipairs(data().spells) do
            if e.level == nextLevel and T.Status(e, ctx) == "later" then at[#at + 1] = e end
        end
        API.Print(("  At level %d: %s"):format(nextLevel, names(at, 12)))
    end
    if #needTalent > 0 then API.Print("  Waiting for a talent: " .. names(needTalent, 8)) end
    for _, o in ipairs(view.other) do
        API.Print(("  Your other spec (last seen): %s"):format(names(o.spells, 8)))
    end
    if view.points then API.Print(("  Talent points to spend: %d"):format(view.points)) end
end

local function command(arg)
    if arg == "test" then return Frame().Test() end
    T.Report()
end

--------------------------------------------------------------------------------
-- The pearl

local function remember()
    state.gen = state.gen + 1
    local gen = state.gen
    C_Timer.After(T.REMEMBER_DELAY, function()
        if gen ~= state.gen or not T.enabled then return end
        T.Remember()
        T.Refresh()
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    API.NoteCombat(event)
    if event == "PLAYER_LEVEL_UP" then
        local level = plain((...), "number") or T.Level()
        local prev = state.level or (level and level - 1)
        state.level = level
        if level and setting("toast") then
            -- Level-ups within the delay are one toast: the first timer takes them all.
            local p = state.pending
            state.pending = p and { prev = math.min(p.prev, prev), level = math.max(p.level, level) }
                or { prev = prev, level = level }
            C_Timer.After(T.LEVEL_DELAY, function()
                local q = state.pending
                state.pending = nil
                if q then T.Show("level", q.prev, q.level) end
            end)
        end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        C_Timer.After(T.SWAP_DELAY, function()
            if not T.enabled then return end
            T.Remember()
            if setting("swap") then T.Show("swap", nil, T.Level()) end
        end)
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        remember()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
        T.Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" and state.held then
        local h = state.held
        state.held = nil
        T.Show(h.kind, h.prev, h.level)
    end
end)

local function enable()
    T.enabled = true
    state.level = T.Level()
    if not data() then return end   -- a class without a list: nothing registered
    hookTooltips()
    API.RegisterEvents(events, { "PLAYER_LEVEL_UP", "ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED",
        "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    remember()
end

local function disable()
    T.enabled = false
    events:UnregisterAllEvents()
    state.pending, state.held, state.shown = nil, nil, nil
    state.gen = state.gen + 1
    Frame().Hide()
end

GP.Pearls.Register({
    key = T.KEY,
    name = "Training reminder",
    desc = "When you level: what your trainer now teaches you. Spell tooltips show when the next ranks come.",
    help = "When you level, a toast lists the spells and ranks your class trainer now teaches you, and in smaller "
        .. "type what was already waiting, with what it costs, and the talent points you have to spend (Talented's "
        .. "early points included). A spell is listed only when you can really learn it: its level, the spells it "
        .. "needs and its talent. Spell tooltips (spellbook, bars) say when the next ranks come. With dual spec, "
        .. "the ranks your other spec's talents could learn, as last seen in that spec. /gpearls training lists "
        .. "everything now; /gpearls training test shows a sample toast to place it. Trainer lists: WhatsTraining's.",
    default = true,
    category = "Combat",
    section = "Spells",
    defaults = { toast = true, waiting = true, swap = true, points = true, cost = true, tooltip = true },
    Enable = enable,
    Disable = disable,
    configure = function(panel, refreshers) Frame().Configure(panel, refreshers) end,
    onSettingChanged = function() if T.enabled then T.Refresh() end end,
    commands = { training = { help = "[test] - what your trainer teaches you now, or a sample toast to place it", run = command } },
})

T._test = { events = events, onTooltip = onTooltip }
