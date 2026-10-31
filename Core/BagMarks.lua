-- Core/BagMarks.lua: small marks on Blizzard's bag buttons, for any pearl
-- (pet care's food #38, the junk spotlight #41). One set of hooks for all:
-- a hooksecurefunc on each of Blizzard's bag frames' UpdateItems
-- (Mainline/ContainerFrame.lua:1191; ContainerFrameContainer.ContainerFrames
-- and the combined bags), made once. Each kind of mark is its own child frame
-- per button, kept in a weak table keyed by Blizzard's button: nothing is
-- written on Blizzard's buttons. The buttons are pooled, so the bag and slot
-- are read every time. None is created in combat: a button met then is
-- decorated after the fight (this file's own PLAYER_REGEN_ENABLED listener).
--
-- BagMarks.Add(id, { anchor, x, y, size, atlas, color = { r, g, b, a },
--     active = function() -> bool, prepare = function() -> context,
--     shows = function(bag, slot, context) -> bool })
-- prepare runs once per decoration pass; its context is never kept between passes.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local BM = {}
GP.BagMarks = BM

local kinds, order = {}, {}
local marks = {}                                       -- id -> { [button] = mark } (weak)
local pending = setmetatable({}, { __mode = "k" })     -- buttons met in combat
local bagFrames = {}
local hooked = false
local events = CreateFrame("Frame")

local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

local function atlasKnown(name)
    local info = name and C_Texture and C_Texture.GetAtlasInfo and ask(C_Texture.GetAtlasInfo, name)
    return type(info) == "table"
end

function BM.Add(id, spec)
    if not kinds[id] then order[#order + 1] = id end
    kinds[id] = spec
    marks[id] = marks[id] or setmetatable({}, { __mode = "k" })
end

function BM.Marks(id) return marks[id] end

local function newMark(id, button)
    local spec = kinds[id]
    local m = CreateFrame("Frame", nil, button)
    m:SetSize(spec.size or 14, spec.size or 14)
    m:SetPoint(spec.anchor or "TOPRIGHT", button, spec.anchor or "TOPRIGHT", spec.x or -2, spec.y or -2)
    m:EnableMouse(false)
    local t = m:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(m)
    if atlasKnown(spec.atlas) then
        t:SetAtlas(spec.atlas)
    else
        local c = spec.color or { 1, 1, 1, 0.9 }
        t:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    m.texture = t
    marks[id][button] = m
    return m
end

-- The button's bag and slot, plain, or nil.
local function where(button)
    local okB, bag = pcall(button.GetBagID, button)
    local okS, slot = pcall(button.GetID, button)
    if not (okB and okS) or API.IsSecret(bag) or API.IsSecret(slot) then return nil end
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

-- One kind on one button; ctx is false when the kind is inactive.
local function decorate(id, button, ctx)
    local show = false
    if ctx ~= false then
        local bag, slot = where(button)
        if bag then show = kinds[id].shows(bag, slot, ctx) == true end
    end
    local mark = marks[id][button]
    if not mark then
        if not show then return end
        if API.InCombat() then
            pending[button] = true                     -- created after the fight
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        mark = newMark(id, button)
    end
    mark:SetShown(show)
end

local function context(id)
    local spec = kinds[id]
    if not spec.active() then return false end
    if spec.prepare then return spec.prepare() end
    return true
end

local function pass(cf, only)
    for _, id in ipairs(order) do
        if not only or only == id then
            local ctx = context(id)
            for _, button in cf:EnumerateValidItems() do decorate(id, button, ctx) end
        end
    end
end

local function onUpdateItems(cf)
    local ok, err = pcall(pass, cf)
    if not ok then API.Fail("bag marks", err) end
end

function BM.Hook()
    if hooked then return end
    hooked = true
    local list = {}
    local container = rawget(_G, "ContainerFrameContainer")
    if type(container) == "table" and type(container.ContainerFrames) == "table" then
        for _, cf in ipairs(container.ContainerFrames) do list[#list + 1] = cf end
    end
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then list[#list + 1] = combined end
    for _, cf in ipairs(list) do
        if type(cf.UpdateItems) == "function" and type(cf.EnumerateValidItems) == "function" then
            hooksecurefunc(cf, "UpdateItems", onUpdateItems)
            bagFrames[#bagFrames + 1] = cf
        end
    end
    if #bagFrames == 0 then API.Fail("bag marks", "Blizzard's bag frames missing") end
end

-- Our own decoration of one kind over the open bags (never Blizzard's
-- UpdateItems). Inactive: every mark of that kind hidden.
function BM.Refresh(id)
    if not kinds[id] then return end
    if not kinds[id].active() then
        for _, m in pairs(marks[id]) do m:Hide() end
        return
    end
    for _, cf in ipairs(bagFrames) do
        if cf:IsShown() then
            local ok, err = pcall(pass, cf, id)
            if not ok then API.Fail("bag marks", err) end
        end
    end
end

-- Combat ended: the buttons met in it, every kind.
function BM.AfterCombat()
    local ctx = {}
    for _, id in ipairs(order) do ctx[id] = context(id) end
    for button in pairs(pending) do
        pending[button] = nil
        for _, id in ipairs(order) do decorate(id, button, ctx[id]) end
    end
end

events:SetScript("OnEvent", function(_, event)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_ENABLED" then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local ok, err = pcall(BM.AfterCombat)
        if not ok then API.Fail("bag marks", err) end
    end
end)

BM._test = { pending = pending, bagFrames = bagFrames, events = events }
