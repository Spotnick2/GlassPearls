-- Core/Notice.lua: one short text in the middle of the screen, for any pearl
-- (instance gear #43, pet care #38).
--
-- Our own, not Blizzard's raid warning: adding a message there from addon code
-- would run its UpdateCenterScreenAnchors, which moves DeadlyDebuffFrame and
-- the private-aura anchor (RaidWarningUtil.lua:36). Click-through, held, then
-- faded; a new one replaces the old. The same in both looks (text over the
-- world).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Notice = {}
GP.Notice = Notice

Notice.NAME = "GlassPearlsNoticeText"
Notice.HOLD, Notice.FADE = 6, 1
Notice.Y = 200            -- below the fixate alert's default (+260)

local f    -- built on first show

local function build()
    f = CreateFrame("Frame", Notice.NAME, UIParent)
    f:SetSize(600, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, Notice.Y)
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
    fade:SetStartDelay(Notice.HOLD)
    fade:SetDuration(Notice.FADE)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
end

function Notice.Show(text)
    if not f then build() end
    f.anim:Stop()
    f.text:SetText(text)
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
end

function Notice.IsShown() return f ~= nil and f:IsShown() end
function Notice.Text() return f and f.text:GetText() end
Notice._test = { frame = function() return f end }
