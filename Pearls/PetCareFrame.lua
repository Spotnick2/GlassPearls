-- Pearls/PetCareFrame.lua: hunter pet care's feed window with its Feed
-- button, the "your pet eats this" tooltip line and bag marks, and the
-- Configuration Panel (#38). The logic is Pearls/PetCare.lua.
--
-- The Feed button is Blizzard's secure path, no macro text: a
-- SecureActionButtonTemplate with type "spell", spell 6991 (Feed Pet) and
-- target-bag / target-slot, which OnActionButtonClick uses while the spell
-- awaits an item (SecureTemplates.lua:772). That block runs after the action
-- whatever the action was, none included, so the button is DISARMED (type,
-- spell and both targets cleared) whenever no click is in progress. Both
-- edges registered, useOnKeyDown false (the mark wheel's pattern): the down
-- edge does nothing; the release's insecure PreClick checks everything again
-- (PetCare.CanFeed) and arms it, type last; PostClick disarms.
--
-- The button is a child of the window, so the window counts as protected in
-- combat: it is shown and hidden only out of combat (hidden inside
-- PLAYER_REGEN_DISABLED, before lockdown), and never in UISpecialFrames.
--
-- Bag marks: a hooksecurefunc on each of Blizzard's bag frames' UpdateItems
-- (Mainline/ContainerFrame.lua:1191; the combined bags too). The mark is our
-- own child frame, kept in a weak table keyed by Blizzard's button: nothing
-- is written on Blizzard's buttons. None is created in combat; a button met
-- then is decorated after the fight.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.PetCareFrame = Frame

Frame.NAME = "GlassPearlsPetCareWindow"
Frame.BUTTON = "GlassPearlsPetCareFeedButton"
Frame.TIP = "Your pet eats this"
Frame.MARK_ATLAS = "UI-PetHappiness"         -- PetHappiness.lua:23
local W, H, PAD = 320, 132, 14

local f, feed          -- built on first show
local pressed, armed = false, nil
local pendingClose, pendingDisarm = false, false
local marks = setmetatable({}, { __mode = "k" })     -- Blizzard's button -> our mark
local pending = setmetatable({}, { __mode = "k" })   -- buttons met in combat
local bagFrames = {}
local bagsHooked, tooltipHooked = false, false

local function PC() return GP.PetCare end
local function setting(name) return GP.Pearls.Setting("petcare", name) end

local function ask(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

local function live() return PC().enabled and PC().state.hunter end

-- A hunter pet out now, plainly.
local function petOut()
    if ask(UnitExists, "pet") ~= true then return false end
    local ok, _, isHunter = pcall(HasPetUI)
    return ok and not API.IsSecret(isHunter) and isHunter == true
end

--------------------------------------------------------------------------------
-- The Feed button

local function disarm()
    if not feed then return end
    if InCombatLockdown() then
        pendingDisarm = true
        return
    end
    feed:SetAttribute("type", nil)
    feed:SetAttribute("spell", nil)
    feed:SetAttribute("target-bag", nil)
    feed:SetAttribute("target-slot", nil)
end

local function preClick(self, mouseButton, down)
    armed = nil
    if down then
        pressed = f ~= nil and f:IsShown()
        return
    end
    if not pressed or InCombatLockdown() then return end
    pressed = false
    disarm()
    if mouseButton ~= "LeftButton" then return end
    local choice = f.choice
    local ok, why = PC().CanFeed(choice)
    if not ok then
        PC().Refused(why)                         -- chooses again and refreshes the window
        if f:IsShown() then f.status:SetText("Couldn't feed: " .. why .. ".") end
        return
    end
    self:SetAttribute("target-bag", choice.bag)
    self:SetAttribute("target-slot", choice.slot)
    self:SetAttribute("spell", PC().FEED_PET)
    self:SetAttribute("type", "spell")            -- last: armed only now
    armed = choice
end

local function postClick(self, mouseButton, down)
    if down then return end
    local choice = armed
    armed = nil
    disarm()
    if choice then PC().Fed(choice) end
end

--------------------------------------------------------------------------------
-- The window

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.petcareWindow
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -300)
    end
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.petcareWindow = { x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 36 })
    f.title = GP.UI.Header(f, "Hunter pet care", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -14)
    f.mood = GP.UI.Label(f, "")
    f.mood:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(24, 24)
    f.icon:SetPoint("TOPLEFT", f.mood, "BOTTOMLEFT", 0, -6)
    f.food = GP.UI.Label(f, "")
    f.food:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.food:SetWidth(W - 2 * PAD - 32)
    f.food:SetWordWrap(true)
    f.status = GP.UI.Label(f, "", "GameFontDisableSmall")
    f.status:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -4)
    feed = CreateFrame("Button", Frame.BUTTON, f, "UIPanelButtonTemplate, SecureActionButtonTemplate")
    feed:SetSize(80, 22)
    feed:SetText("Feed")
    feed:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 12)
    feed:RegisterForClicks("AnyDown", "AnyUp")
    feed:SetAttribute("useOnKeyDown", false)
    feed:SetScript("PreClick", preClick)
    feed:SetScript("PostClick", postClick)
    GP.UI.Tooltip(feed, "Feed", "Casts Feed Pet on the food shown. Out of combat only.")
    f.never = GP.UI.Button(f, "Never feed this", 120, function()
        if f.choice then PC().Never(f.choice.id) end
    end)
    f.never:SetPoint("LEFT", feed, "RIGHT", 8, 0)
    GP.UI.Tooltip(f.never, "Never feed this", "Leave this food out of the choice, on all your characters "
        .. "(/gpearls petcare forget puts it back).")
    f.close = GP.UI.Button(f, "Close", 72, function() PC().Dismiss() end)
    f.close:SetPoint("LEFT", f.never, "RIGHT", 8, 0)
    GP.UI.Tooltip(f.close, "Close", "Not again until your pet has been happy.")
end

-- Show (or refresh) the window: { word, choice, out, test }. Out of combat only.
function Frame.Show(view)
    if InCombatLockdown() then return end
    if not f then build() end
    f.choice = view.choice
    f.mood:SetText(("Your pet is %s."):format(view.word))
    local c = view.choice
    if c then
        f.icon:SetTexture(c.icon or 134400)
        f.icon:Show()
        f.food:SetText(("%s (%d in your bags)"):format(PC().ItemName(c.id, c.name), c.count or 0))
    else
        f.icon:Hide()
        local why = PC().NoFood(view.out)
        f.food:SetText(why:sub(1, 1):upper() .. why:sub(2) .. ".")
    end
    f.status:SetText(view.test and "A test: the Feed button acts only on real hunger." or "")
    feed:SetEnabled(c ~= nil)
    f.never:SetEnabled(c ~= nil)
    disarm()
    if not f:IsShown() then
        place()
        f:Show()
    end
end

-- Hide it, whatever the reason (combat, happy, dismissed, switched off).
function Frame.Close(reason)
    if not (f and f:IsShown()) then return end
    pressed, armed = false, nil
    if InCombatLockdown() then
        pendingClose = true
        return
    end
    disarm()
    f.choice = nil
    f:Hide()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Choice() return f and f:IsShown() and f.choice or nil end

--------------------------------------------------------------------------------
-- What the pet eats: the tooltip line and the bag marks

local function foodShows(where)
    local food = setting("food")
    return live() and (food == where or food == "both")
end

local function onTooltip(tooltip, data)
    if not foodShows("tooltip") or API.InCombat() then return end
    if API.IsSecret(data) or type(data) ~= "table" then return end
    local id = data.id
    if API.IsSecret(id) or type(id) ~= "number" then return end
    if not (tooltip and tooltip.AddLine) or not petOut() then return end
    if PC().Edible(id) ~= true then return end
    tooltip:AddLine(Frame.TIP, 0.25, 1, 0.25)
end

local function hookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    local TDP = rawget(_G, "TooltipDataProcessor")
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not (TDP and TDP.AddTooltipPostCall and kind) then
        return API.Fail("pearl petcare tooltip", "TooltipDataProcessor missing")
    end
    local ok, err = pcall(TDP.AddTooltipPostCall, kind, function(...)
        local ok2, err2 = pcall(onTooltip, ...)
        if not ok2 then API.Fail("pearl petcare tooltip", err2) end
    end)
    if not ok then API.Fail("pearl petcare tooltip", err) end
end

local function atlasKnown(name)
    local info = C_Texture and C_Texture.GetAtlasInfo and ask(C_Texture.GetAtlasInfo, name)
    return type(info) == "table"
end

local function newMark(button)
    local m = CreateFrame("Frame", nil, button)
    m:SetSize(14, 14)
    m:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    m:EnableMouse(false)
    local t = m:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(m)
    if atlasKnown(Frame.MARK_ATLAS) then
        t:SetAtlas(Frame.MARK_ATLAS)
    else
        t:SetColorTexture(0.3, 1, 0.3, 0.9)
    end
    m.texture = t
    marks[button] = m
    return m
end

-- One of Blizzard's bag buttons: its mark shown when its item (read now: the
-- buttons are pooled) is plainly edible for the pet out.
local function decorate(button, out)
    local show = false
    if out then
        local okB, bag = pcall(button.GetBagID, button)
        local okS, slot = pcall(button.GetID, button)
        if okB and okS and not API.IsSecret(bag) and not API.IsSecret(slot) then
            local id = ask(C_Container.GetContainerItemID, bag, slot)
            show = type(id) == "number" and PC().Edible(id) == true
        end
    end
    local mark = marks[button]
    if not mark then
        if not show then return end
        if API.InCombat() then
            pending[button] = true                 -- created after the fight
            return
        end
        mark = newMark(button)
    end
    mark:SetShown(show)
end

local function decorateFrame(cf)
    local out = foodShows("bags") and petOut()
    for _, button in cf:EnumerateValidItems() do decorate(button, out) end
end

local function onUpdateItems(cf)
    local ok, err = pcall(decorateFrame, cf)
    if not ok then API.Fail("pearl petcare bags", err) end
end

local function hookBags()
    if bagsHooked then return end
    bagsHooked = true
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
    if #bagFrames == 0 then API.Fail("pearl petcare bags", "Blizzard's bag frames missing") end
end

-- Hook what the food setting needs, once each (hooks can't be removed: each
-- checks the pearl and the setting).
function Frame.Start()
    if foodShows("tooltip") then hookTooltip() end
    if foodShows("bags") then hookBags() end
end

-- Our own decoration over the open bags (a new pet, a setting change,
-- switched on or off); never Blizzard's UpdateItems. Off: every mark hidden.
function Frame.Marks()
    if not foodShows("bags") then
        for _, m in pairs(marks) do m:Hide() end
        return
    end
    for _, cf in ipairs(bagFrames) do
        if cf:IsShown() then onUpdateItems(cf) end
    end
end

-- Combat ended: finish what lockdown refused.
function Frame.AfterCombat()
    if pendingDisarm then
        pendingDisarm = false
        disarm()
    end
    if pendingClose then
        pendingClose = false
        Frame.Close("after combat")
    end
    local out = foodShows("bags") and petOut()
    for button in pairs(pending) do
        pending[button] = nil
        decorate(button, out)
    end
end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P = "petcare", GP.Pearls
    local function check(parent, text, name, tip)
        local cb, refresh = GP.UI.Check(parent, text,
            function() return P.Setting(KEY, name) end, function(on) P.SetSetting(KEY, name, on) end, { tip = tip })
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    -- Left: food and feeding.
    local head = GP.UI.Header(panel, "What your pet eats")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local lastFood, _, refreshFood = GP.UI.Radios(panel, head, {
        { "tooltip", "A line in item tooltips" },
        { "bags", "A mark on your bag buttons" },
        { "both", "Both" },
        { "off", "Neither" },
    }, function() return P.Setting(KEY, "food") end, function(v) P.SetSetting(KEY, "food", v) end)
    refreshers[#refreshers + 1] = refreshFood
    local fhead = GP.UI.Header(panel, "Feeding", "GameFontNormal")
    fhead:SetPoint("TOPLEFT", lastFood, "BOTTOMLEFT", -4, -16)
    local feedBox = check(panel, "Remind me to feed my pet", "feed",
        "A line in your chat and a window with a Feed button, out of combat.")
    feedBox:SetPoint("TOPLEFT", fhead, "BOTTOMLEFT", -4, -6)
    local lastAt, _, refreshAt = GP.UI.Radios(panel, feedBox, {
        { "content", "When it's Content or Unhappy" },
        { "unhappy", "Only when it's Unhappy" },
    }, function() return P.Setting(KEY, "feedAt") end, function(v) P.SetSetting(KEY, "feedAt", v) end)
    refreshers[#refreshers + 1] = refreshAt
    local note = GP.UI.Label(panel,
        "The food is a guess: the cheapest within 10 levels of your pet, else the highest level. Unverified until "
            .. "the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", lastAt, "BOTTOMLEFT", 0, -12)
    note:SetWidth(270)
    note:SetWordWrap(true)
    -- Right: the pet checks and the never-feed list.
    local chead = GP.UI.Header(panel, "Check my pet")
    chead:SetPoint("TOPLEFT", panel, "TOPLEFT", 300, 0)
    local missing = check(panel, "Missing or dead", "missing", "\"You have no pet out\" or \"Your pet is dead\".")
    missing:SetPoint("TOPLEFT", chead, "BOTTOMLEFT", -4, -6)
    local passive = check(panel, "On Passive", "passive", "\"Your pet is on Passive\" (a live pet).")
    passive:SetPoint("TOPLEFT", missing, "BOTTOMLEFT", 0, -2)
    local when = GP.UI.Label(panel, "When:", "GameFontNormal")
    when:SetPoint("TOPLEFT", passive, "BOTTOMLEFT", 4, -8)
    local atFight = check(panel, "At the start of a fight", "atFight")
    atFight:SetPoint("TOPLEFT", when, "BOTTOMLEFT", -4, -4)
    local atReady = check(panel, "At a ready check", "atReady", "Also in combat.")
    atReady:SetPoint("TOPLEFT", atFight, "BOTTOMLEFT", 0, -2)
    local away = check(panel, "Out of combat, when it disappears", "away",
        "10 seconds later; never on a taxi, mounted, feigning death or at the stable master. Missing or dead only. "
            .. "It also warns once after you dismiss your pet yourself.")
    away:SetPoint("TOPLEFT", atReady, "BOTTOMLEFT", 0, -2)
    local _, neverList = GP.UI.SetList(panel, away, "Never fed", PC().NEVER, "none", function(id)
        return PC().ItemName(id)
    end, "food(s)")
    refreshers[#refreshers + 1] = neverList.refresh
    panel.neverList = neverList
end

Frame._test = {
    frame = function() return f end,
    button = function() return feed end,
    marks = marks,
    pending = pending,
    bagFrames = bagFrames,
    preClick = preClick,
    postClick = postClick,
}
