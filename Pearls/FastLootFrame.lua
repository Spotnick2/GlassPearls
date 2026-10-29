-- Pearls/FastLootFrame.lua: faster loot's floating coin text and its
-- Configuration Panel (#36). The logic is Pearls/FastLoot.lua.
--
-- The coin text: "+12s 40c" with the client's coin icons, where the player
-- clicked, rising and fading out, then hidden. Click-through; a new one
-- replaces the old. The same in both looks (text over the world).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Frame = {}
GP.FastLootFrame = Frame

Frame.NAME = "GlassPearlsCoinText"
Frame.RISE, Frame.SECONDS = 40, 1.5

local f    -- built on first show

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(200, 30)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(false)
    f:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("CENTER", f, "CENTER")
    f.text:SetShadowOffset(1, -1)
    local ag = f:CreateAnimationGroup()
    local rise = ag:CreateAnimation("Translation")
    rise:SetOffset(0, Frame.RISE)
    rise:SetDuration(Frame.SECONDS)
    rise:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(Frame.SECONDS / 2)
    fade:SetDuration(Frame.SECONDS / 2)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
end

-- Show `copper` gained at (x, y) in UIParent's bottom-left coordinates (the
-- screen's centre when unknown).
function Frame.Show(copper, x, y)
    if not f then build() end
    f.anim:Stop()
    f:ClearAllPoints()
    if type(x) == "number" and type(y) == "number" then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    f.amount = copper
    f.text:SetText("+" .. GP.TrainingFrame.Money(copper))
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P = "fastloot", GP.Pearls
    local head = GP.UI.Header(panel, "Faster loot")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local coins, refresh = GP.UI.Check(panel, "Show the money from a corpse with only coins",
        function() return P.Setting(KEY, "coins") end, function(on) P.SetSetting(KEY, "coins", on) end,
        { tip = "The amount floats up where you clicked, then fades: the money gained while the loot money came in." })
    coins:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -6)
    refreshers[#refreshers + 1] = refresh
    local note = GP.UI.Label(panel,
        "Works with the game's auto loot (its setting, or the auto-loot key, Shift by default). Bind-on-pickup still "
            .. "asks you; a group's rolls and master loot, and anything that may not fit, are left to the game. "
            .. "Unverified until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", coins, "BOTTOMLEFT", 4, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

Frame._test = { frame = function() return f end }
