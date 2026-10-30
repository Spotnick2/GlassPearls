-- Pearls/InstanceGearFrame.lua: the instance gear reminders' centre text and
-- Configuration Panel (#43). The logic is Pearls/InstanceGear.lua.
--
-- The centre text is our own, not Blizzard's raid warning: adding a message
-- there from addon code would run its UpdateCenterScreenAnchors, which moves
-- DeadlyDebuffFrame and the private-aura anchor (RaidWarningUtil.lua:36).
-- Click-through, held, then faded; a new one replaces the old. The same in
-- both looks (text over the world).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Frame = {}
GP.InstanceGearFrame = Frame

Frame.NAME = "GlassPearlsInstanceGearText"
Frame.HOLD, Frame.FADE = 6, 1
Frame.Y = 200            -- below the fixate alert's default (+260)

local f    -- built on first show

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(600, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, Frame.Y)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER", f, "CENTER")
    f.text:SetShadowOffset(1, -1)
    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(Frame.HOLD)
    fade:SetDuration(Frame.FADE)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
end

function Frame.Show(text)
    if not f then build() end
    f.anim:Stop()
    f.text:SetText(text)
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Text() return f and f.text:GetText() end
Frame._test = { frame = function() return f end }

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local KEY, P = "instancegear", GP.Pearls
    local head = GP.UI.Header(panel, "On entering an instance")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local ad, refreshAD = GP.UI.Check(panel, "Argent Dawn trinket in Scholomance and Stratholme",
        function() return P.Setting(KEY, "argentdawn") end, function(on) P.SetSetting(KEY, "argentdawn", on) end,
        { tip = "Scourgestones drop only while an Argent Dawn trinket is equipped: a reminder when none is, and it's "
            .. "in your bags or your bank." })
    ad:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -6)
    refreshers[#refreshers + 1] = refreshAD
    local ex, refreshEx = GP.UI.Check(panel, "Also at Exalted",
        function() return P.Setting(KEY, "exalted") end, function(on) P.SetSetting(KEY, "exalted", on) end,
        { tip = "Scourgestones still drop at Exalted, for the Valor Tokens. Off: no reminder once you're Exalted." })
    ex:SetPoint("TOPLEFT", ad, "BOTTOMLEFT", 16, -4)
    refreshers[#refreshers + 1] = refreshEx
    local note = GP.UI.Label(panel,
        "A line in your chat and a short text in the middle of the screen, 5 seconds after the loading screen; not "
            .. "after a /reload inside. Unverified until the game is live.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", ex, "BOTTOMLEFT", -12, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end
