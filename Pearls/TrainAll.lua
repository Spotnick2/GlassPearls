-- Pearls/TrainAll.lua: train all (#39). A "Train all" button on the class
-- trainer's window that learns every class spell it offers, cheapest first,
-- while the money lasts.
--
-- Only a class trainer (C_Trainer.GetTrainerType() General, not a tradeskill
-- trainer) and only class spells: a service is ours when it is available, a
-- plain whole cost, not a profession, its tooltip data a Spell (type before
-- id, as Blizzard's TooltipUtil.GetDisplayedSpell) whose ID the training
-- reminder's curated list has for this class (Data/Training.lua: riding,
-- weapon masters and pet training are left out), and that spell plainly
-- unknown, so a learn can be proven.
--
-- One purchase in flight. A run is identified by itself (closing the trainer,
-- combat and Disable end it; its timers check it is still the run). Each step
-- reads the list again (indexes shift; the player's filter is never changed;
-- a learned spell reads known, so it is no longer ours), installs the pending
-- record, then BuyTrainerService. It is confirmed only when
-- the money reads exactly `before - cost` AND the spell reads known, checked
-- on TRAINER_UPDATE, PLAYER_MONEY and SPELLS_CHANGED (any order, also inside
-- the buy) and once more at the 2 s deadline; the next step waits a frame.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one: BuyTrainerService from
-- addon code outside a click).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local TA = {}
GP.TrainAll = TA

TA.KEY = "trainall"
TA.DEADLINE = 2

local events = CreateFrame("Frame")
local state = { run = nil }
TA.state = state

local function say(msg) API.Print(msg) end
local function Frame() return GP.TrainAllFrame end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

local function getMoney()
    local m = ask(GetMoney)
    return type(m) == "number" and m or nil
end

-- This class's trainer spells, by ID.
local classSpells
local function ours()
    if classSpells then return classSpells end
    classSpells = {}
    local _, class = UnitClass("player")
    local d = GP.TrainingData and not API.IsSecret(class) and GP.TrainingData.classes[class]
    for _, s in ipairs(d and d.spells or {}) do classSpells[s.id] = true end
    return classSpells
end

-- A class trainer: true, or false and why.
function TA.ClassTrainer()
    local kind = ask(C_Trainer.GetTrainerType)
    local general = Enum.TrainerType and Enum.TrainerType.General
    if kind == nil or kind ~= general then return false, "not a class trainer" end
    if ask(IsTradeskillTrainer) ~= false then return false, "a profession trainer" end
    return true
end

-- Service i: { index, id, cost, name } when ours, else nil and why.
function TA.Service(i)
    local okI, name, kind = pcall(GetTrainerServiceInfo, i)
    if not okI or API.IsSecret(kind) then return nil, "unreadable" end
    if kind ~= "available" then return nil, "not available" end
    local okC, cost, isProfession = pcall(GetTrainerServiceCost, i)
    if not okC or API.IsSecret(cost) or API.IsSecret(isProfession) then return nil, "unreadable" end
    if type(cost) ~= "number" or cost < 0 or cost % 1 ~= 0 then return nil, "unreadable" end
    if isProfession ~= false then return nil, "a profession" end
    local data = ask(C_TooltipInfo.GetTrainerService, i)
    if type(data) ~= "table" then return nil, "its spell unreadable" end
    local dtype, id = data.type, data.id
    if API.IsSecret(dtype) or dtype ~= Enum.TooltipDataType.Spell then return nil, "not a spell" end
    if API.IsSecret(id) or type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return nil, "its spell unreadable" end
    if not ours()[id] then return nil, "not a class spell" end
    if ask(IsPlayerSpell, id) ~= false then return nil, "already known" end
    return { index = i, id = id, cost = cost, name = (not API.IsSecret(name) and name) or nil }
end

-- Every service of ours now, cheapest first (cost, then index), and the
-- reasons for the others.
function TA.List()
    local list, why = {}, {}
    local ok, why0 = TA.ClassTrainer()
    if not ok then return list, why, why0 end
    local n = ask(GetNumTrainerServices)
    if type(n) ~= "number" then return list, why, "the list unreadable" end
    for i = 1, n do
        local s, reason = TA.Service(i)
        if s then
            list[#list + 1] = s
        elseif reason then
            why[reason] = (why[reason] or 0) + 1
        end
    end
    table.sort(list, function(a, b)
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.index < b.index
    end)
    return list, why
end

--------------------------------------------------------------------------------
-- The run

local step

local function finish(run, reason)
    if state.run ~= run then return end
    state.run = nil
    run.pending = nil
    local n = #run.learned
    local text = n == 0 and "Train all: nothing trained" or ("Train all: trained %d spell%s for %s"):format(n,
        n == 1 and "" or "s", GP.TrainingFrame.Money(run.spent))
    say(text .. (reason and (": " .. reason) or "") .. ".")
    if Frame() then Frame().Refresh() end
end

-- Check the pending purchase: confirmed, failed, or still waiting.
local function check(run, final)
    if state.run ~= run or not run.pending then return end
    local p = run.pending
    local m = getMoney()
    local known = ask(IsPlayerSpell, p.id) == true
    if m == p.before - p.cost and known then
        run.pending = nil
        run.learned[#run.learned + 1] = p.id
        run.spent = run.spent + p.cost
        C_Timer.After(0, function() step(run) end)        -- never a purchase from inside a callback
        return
    end
    if m ~= nil and m ~= p.before and m ~= p.before - p.cost then
        return finish(run, "the money changed otherwise")
    end
    if final then finish(run, "a purchase wasn't confirmed") end
end

step = function(run)
    if state.run ~= run then return end               -- ended: closed, combat, switched off
    local list, _, notTrainer = TA.List()
    if notTrainer then return finish(run, notTrainer) end
    local s = list[1]
    if not s then return finish(run, nil) end
    local m = getMoney()
    if not m then return finish(run, "your money unreadable") end
    if s.cost > m then return finish(run, "not enough money for the next") end
    local p = { id = s.id, cost = s.cost, before = m }
    run.pending = p                                        -- installed before the buy
    C_Timer.After(TA.DEADLINE, function()
        if state.run == run and run.pending == p then check(run, true) end
    end)
    local ok, err = pcall(BuyTrainerService, s.index)
    if not ok then
        API.Fail("pearl trainall buy", err)
        return finish(run, "the purchase was refused")
    end
    check(run, false)                                      -- it may have settled inside the buy
end

-- From the button's click.
function TA.Start()
    if not TA.enabled or state.run then return end
    if API.InCombat() then return say("Train all: not in combat.") end
    local run = { learned = {}, spent = 0 }
    state.run = run
    step(run)
end

local function stale(reason)
    if state.run then finish(state.run, reason) end
end

events:SetScript("OnEvent", function(_, event, arg1)
    API.NoteCombat(event)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TrainerUI" and Frame() then Frame().Ensure() end
    elseif event == "TRAINER_SHOW" then
        if Frame() then Frame().Ensure(); Frame().Refresh() end
    elseif event == "TRAINER_CLOSED" then
        stale("the trainer closed")
    elseif event == "PLAYER_REGEN_DISABLED" then
        stale("combat")
    else                                                   -- TRAINER_UPDATE, PLAYER_MONEY, SPELLS_CHANGED
        if state.run then check(state.run, false) end
        if Frame() then Frame().Refresh() end
    end
end)

function TA.Report()
    local list, why, notTrainer = TA.List()
    if notTrainer then return say("Train all: " .. notTrainer .. " here.") end
    local total = 0
    for _, s in ipairs(list) do total = total + s.cost end
    say(("Train all: %d spell%s here for %s."):format(#list, #list == 1 and "" or "s", GP.TrainingFrame.Money(total)))
    local parts = {}
    for reason, n in pairs(why) do parts[#parts + 1] = reason .. " " .. n end
    table.sort(parts)
    if #parts > 0 then say("  Left out: " .. table.concat(parts, ", ") .. ".") end
end

local function enable()
    TA.enabled = true
    API.RegisterEvents(events, { "ADDON_LOADED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED",
        "SPELLS_CHANGED", "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    if Frame() then Frame().Ensure(); Frame().Refresh() end
end

local function disable()
    TA.enabled = false
    stale("switched off")
    events:UnregisterAllEvents()
    if Frame() then Frame().Refresh() end
end

GP.Pearls.Register({
    key = TA.KEY,
    name = "Train all",
    desc = "A Train all button at your class trainer: every class spell it offers, cheapest first.",
    default = false,
    category = "Combat",
    section = "Spells",
    Enable = enable,
    Disable = disable,
    commands = { trainall = { help = "- what Train all would learn at this trainer, and what it leaves",
        run = function() TA.Report() end } },
})

TA._test = { events = events }
