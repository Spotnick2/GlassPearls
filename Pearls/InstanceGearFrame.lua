-- Pearls/InstanceGearFrame.lua: the instance gear reminders' Configuration
-- Panel (#43). The logic is Pearls/InstanceGear.lua; its centre text is
-- Core/Notice.lua.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Frame = {}
GP.InstanceGearFrame = Frame

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
