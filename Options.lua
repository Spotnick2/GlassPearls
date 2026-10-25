-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered once at PLAYER_LOGIN from GlassPearls.lua.
--
-- One checkbox per registered pearl, then the own-account sync switch. A pearl
-- with settings of its own gets a sub-page when it needs one.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Options = {}
GP.Options = Options

local panel = CreateFrame("Frame")
panel.name = "Glass Pearls"
panel:Hide()

local category
local refreshers = {}

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

-- An on/off setting under `anchor`: our own label beside the template's box.
local function checkbox(parent, anchor, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    refreshers[#refreshers + 1] = sync
    return cb
end

local function build()
    local title = label(panel, "Glass Pearls", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local version = label(panel, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function()
        version:SetText("Version " .. GP.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end

    local header = label(panel, "Pearls", "GameFontNormal")
    header:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    local last = header
    Options._test.pearls = {}
    local list = GP.Pearls.List()
    for _, def in ipairs(list) do
        local key = def.key
        last = checkbox(panel, last, def.desc and (def.name .. ": " .. def.desc) or def.name,
            function() return GP.Pearls.IsOn(key) end,
            function(on) GP.Pearls.Set(key, on) end)
        Options._test.pearls[key] = last
    end
    if #list == 0 then
        local none = label(panel, "No pearls yet.", "GameFontDisable")
        none:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
        last = none
    end

    local sync = label(panel, "Your other accounts", "GameFontNormal")
    sync:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
    Options._test.sync = checkbox(panel, sync, "Share with my own other WoW accounts on this Battle.net account",
        GP.AccountSync.IsEnabled, GP.AccountSync.SetEnabled)

    local hint = label(panel, "Type /gpearls help for every command.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", Options._test.sync, "BOTTOMLEFT", 0, -16)
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        build()
    end
    for _, refresh in ipairs(refreshers) do refresh() end
end)

-- Called once at PLAYER_LOGIN by GlassPearls.lua.
function Options.Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = { panel = panel, refreshers = refreshers }
