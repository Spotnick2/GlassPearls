-- Options.lua: GlassPearls' own options window (#3), and the small page in
-- Esc > Options > AddOns that opens it.
--
-- The layout is the owner's choice, after Leatrix Plus (All Rights Reserved:
-- its layout is the model, nothing is copied): the categories on the left
-- (Home, each page that has pearls, Settings), the page on the right in two
-- columns of sections, one checkbox per pearl, a gear beside a pearl that has
-- options opening its Configuration Panel in the same window (Reset, Help,
-- Back to Main Menu), a `*` after a pearl that can't switch off without a
-- reload, a Reload button while one waits, and a search box over every pearl.
--
-- Built on first open, every value re-read on every show (the porting guide's
-- blank-page recipe). Esc closes it: its name goes into UISpecialFrames with
-- table.insert, never by reassigning the table (porting guide section 3).
--
-- Reload: the guide records ReloadUI() as protected, yet Leatrix Plus's
-- Forever build calls it from its button's click. Unmeasured until
-- 2026-11-04 (PearlsProbe): the button calls it from its own click, and if
-- ADDON_ACTION_FORBIDDEN names it, the button gives way to "Type /reload".

local ADDON = ...
GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Options = {}
GP.Options = Options

Options.NAME = "GlassPearlsOptionsFrame"
local W, H, NAV_W = 780, 520, 190
local ROW_H, HEADER_H, COL_W = 28, 34, 270

local win, body, pageTitle, pageSub, reloadButton, reloadText, search
local pages, navItems = {}, {}
local current, lastMain = nil, "home"
local reloadForbidden = false
local lookChoiceAtLoad

--------------------------------------------------------------------------------
-- Pending reload: a pearl switched off that can't stop live, or the look
-- choice changed since this session's look was built.

function Options.LookPending()
    if lookChoiceAtLoad == nil or not GP.db then return false end
    return (GP.db.useGlassUI ~= false) ~= lookChoiceAtLoad
end

function Options.PendingReload()
    return GP.Pearls.PendingReload() or Options.LookPending()
end

local function refreshReload()
    if not reloadButton then return end
    reloadButton:SetShown(not reloadForbidden)
    reloadText:SetShown(reloadForbidden and Options.PendingReload())
    reloadButton:SetEnabled(Options.PendingReload())
end

--------------------------------------------------------------------------------
-- Pages

local function newPage(name, title, build, sub)
    local f = CreateFrame("Frame", nil, body)
    f:SetAllPoints(body)
    f:Hide()
    local page = { name = name, title = title, sub = sub, frame = f, build = build, refreshers = {} }
    pages[name] = page
    return page
end

local function selectNav(name)
    for key, item in pairs(navItems) do item.selected:SetShown(key == name) end
end

local function showPage(name)
    local page = pages[name]
    if not page then return false end
    for _, p in pairs(pages) do p.frame:Hide() end
    if not page.built then
        page.built = true
        page.build(page)
    end
    page.frame:Show()
    for _, refresh in ipairs(page.refreshers) do refresh() end
    pageTitle:SetText(page.title)
    pageSub:SetText(page.sub or "")
    current = name
    if not name:find("^config:") and name ~= "search" then lastMain = name end
    selectNav(page.nav or name)
    refreshReload()
    return true
end
Options.ShowPage = showPage

--------------------------------------------------------------------------------
-- The pearl list: sections in two columns, a row per pearl. Rows and headers
-- come from a pool on the page, so the search page can lay out again on every
-- keystroke without making frames each time.

local function rowFor(page, i)
    page.rows = page.rows or {}
    local row = page.rows[i]
    if row then return row end
    row = {}
    row.check = CreateFrame("CheckButton", nil, page.frame, "UICheckButtonTemplate")
    row.check:SetSize(26, 26)
    row.label = GP.UI.Label(page.frame, "")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 1)
    row.check:SetScript("OnClick", function(self)
        GP.Pearls.Set(row.key, self:GetChecked() == true)
        self:SetChecked(GP.Pearls.IsOn(row.key))
        refreshReload()
    end)
    row.check:HookScript("OnEnter", function(self)
        local def = GP.Pearls.Get(row.key)
        if not def then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.name)
        if def.desc then GameTooltip:AddLine(def.desc, 1, 1, 1, true) end
        if not def.Disable then GameTooltip:AddLine("* Switching it off takes effect after a reload.", 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    row.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row.gear = GP.UI.Gear(page.frame, function() Options.ShowConfig(row.key) end)
    page.rows[i] = row
    return row
end

local function headerFor(page, i)
    page.headers = page.headers or {}
    local h = page.headers[i]
    if not h then
        h = GP.UI.Header(page.frame, "")
        page.headers[i] = h
    end
    return h
end

-- Sections by name, "General" last.
local function sections(defs)
    local by, names = {}, {}
    for _, def in ipairs(defs) do
        if not by[def.section] then
            by[def.section] = {}
            names[#names + 1] = def.section
        end
        table.insert(by[def.section], def)
    end
    table.sort(names, function(a, b)
        if (a == GP.Pearls.DEFAULT_SECTION) ~= (b == GP.Pearls.DEFAULT_SECTION) then
            return b == GP.Pearls.DEFAULT_SECTION
        end
        return a < b
    end)
    return names, by
end

-- Lay `defs` out on `page`. Each section goes to the column with less in it.
local function layoutPearls(page, defs)
    local names, by = sections(defs)
    local height = { 0, 0 }
    local nRows, nHeaders = 0, 0
    page.placed = {}
    for _, sec in ipairs(names) do
        local col = height[2] < height[1] and 2 or 1
        local x = (col - 1) * COL_W
        nHeaders = nHeaders + 1
        local h = headerFor(page, nHeaders)
        h:SetText(sec)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", page.frame, "TOPLEFT", x, -height[col])
        h:Show()
        local y = height[col] + HEADER_H
        for _, def in ipairs(by[sec]) do
            nRows = nRows + 1
            local row = rowFor(page, nRows)
            row.key = def.key
            row.check:ClearAllPoints()
            row.check:SetPoint("TOPLEFT", page.frame, "TOPLEFT", x - 4, -y)
            row.check:SetChecked(GP.Pearls.IsOn(def.key))
            row.label:SetText(def.Disable and def.name or (def.name .. "*"))
            row.gear:ClearAllPoints()
            row.gear:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
            row.gear:SetShown(def.configure ~= nil)
            row.check:Show()
            row.label:Show()
            page.placed[#page.placed + 1] = { key = def.key, column = col, section = sec, row = row }
            y = y + ROW_H
        end
        height[col] = y + 14
    end
    for i = nRows + 1, #(page.rows or {}) do
        local row = page.rows[i]
        row.key = nil
        row.check:Hide(); row.label:Hide(); row.gear:Hide()
    end
    for i = nHeaders + 1, #(page.headers or {}) do page.headers[i]:Hide() end
    return nRows
end

local function categoryPage(category)
    local page = newPage("cat:" .. category, category, function(page)
        layoutPearls(page, GP.Pearls.InCategory(category))
    end)
    -- Every show re-reads the boxes: a slash command or a synced setting may
    -- have changed one.
    page.refreshers[1] = function()
        for _, p in ipairs(page.placed or {}) do p.row.check:SetChecked(GP.Pearls.IsOn(p.key)) end
    end
    return page
end

local function searchPage()
    local page = newPage("search", "Search", function() end)
    page.empty = GP.UI.Label(page.frame, "Nothing matches.", "GameFontDisable")
    page.empty:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, 0)
    page.refreshers[1] = function()
        local n = layoutPearls(page, GP.Pearls.Search(page.query))
        page.empty:SetShown(n == 0)
    end
    return page
end

local function onSearch(text)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then
        if current == "search" then showPage(lastMain) end
        return
    end
    pages.search.query = text
    showPage("search")
end

--------------------------------------------------------------------------------
-- A pearl's Configuration Panel.

function Options.ShowConfig(key)
    local def = GP.Pearls.Get(key)
    if not def or not def.configure then return false end
    local name = "config:" .. key
    if not pages[name] then
        local page = newPage(name, def.name, function(page)
            local content = CreateFrame("Frame", nil, page.frame)
            content:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, 0)
            content:SetPoint("BOTTOMRIGHT", page.frame, "BOTTOMRIGHT", 0, 70)
            local ok, err = pcall(def.configure, content, page.refreshers)
            if not ok then
                API.Fail("pearl " .. key .. " configure", err)
                GP.UI.Label(content, "This panel failed to build: /gpearls failures"):SetPoint("TOPLEFT", content, "TOPLEFT")
            end
            page.help = GP.UI.Label(page.frame, def.help or def.desc or "", "GameFontHighlight")
            page.help:SetPoint("BOTTOMLEFT", page.frame, "BOTTOMLEFT", 0, 36)
            page.help:SetWidth(W - NAV_W - 60)
            page.help:SetWordWrap(true)
            page.help:Hide()
            page.reset = GP.UI.Button(page.frame, "Reset", 90, function()
                GP.Pearls.ResetSettings(key)
                for _, refresh in ipairs(page.refreshers) do refresh() end
            end)
            page.reset:SetPoint("BOTTOMLEFT", page.frame, "BOTTOMLEFT", 0, 0)
            page.helpButton = GP.UI.Button(page.frame, "Help", 90, function() page.help:SetShown(not page.help:IsShown()) end)
            page.helpButton:SetPoint("LEFT", page.reset, "RIGHT", 8, 0)
            page.back = GP.UI.Button(page.frame, "Back to Main Menu", 160, function() showPage("cat:" .. def.category) end)
            page.back:SetPoint("BOTTOMRIGHT", page.frame, "BOTTOMRIGHT", 0, 0)
        end, "Configuration Panel")
        page.nav = "cat:" .. def.category
    end
    return showPage(name)
end

--------------------------------------------------------------------------------
-- Home and Settings.

local function homePage()
    return newPage("home", "Home", function(page)
        local f = page.frame
        local intro = GP.UI.Label(f, "Small quality-of-life touches for WoW: Forever, each one switched on or off "
            .. "on its own. Pick a page on the left, tick what you want, and use a gear for that feature's own options.")
        intro:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        intro:SetWidth(W - NAV_W - 60)
        intro:SetWordWrap(true)
        local cmds = GP.UI.Label(f, "Type /gpearls help for the commands.", "GameFontDisable")
        cmds:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
        local sync = GP.UI.Label(f, "")
        sync:SetPoint("TOPLEFT", cmds, "BOTTOMLEFT", 0, -16)
        page.sync = sync
        page.refreshers[#page.refreshers + 1] = function()
            sync:SetText("Your other accounts: " .. (GP.AccountSync.IsEnabled() and "sharing on" or "sharing off"))
        end
    end)
end

local function settingsPage()
    return newPage("settings", "Settings", function(page)
        local f = page.frame
        local look = GP.UI.Header(f, "Appearance")
        look:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local last = look
        if GP.Theme.SuiteAvailable() then
            local cb, refresh = GP.UI.Check(f, "Use Glass UI appearance",
                function() return GP.db.useGlassUI ~= false end,
                function(on) GP.Settings.SetUseGlassUI(on) end,
                { tip = "Glass UI's glass instead of the WoW Forever look. Takes effect after a reload.",
                  onChange = refreshReload })
            cb:SetPoint("TOPLEFT", look, "BOTTOMLEFT", -4, -6)
            page.refreshers[#page.refreshers + 1] = refresh
            page.useGlass = cb
            last = cb
        else
            local note = GP.UI.Label(f, "The WoW Forever look. With Glass UI installed, GlassPearls can follow its glass.",
                "GameFontDisable")
            note:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 0, -8)
            last = note
        end
        local share = GP.UI.Header(f, "Your other accounts")
        share:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == look and 0 or 4, -18)
        local cb, refresh = GP.UI.Check(f, "Share settings with my other WoW accounts",
            GP.AccountSync.IsEnabled, GP.AccountSync.SetEnabled,
            { tip = "Your own accounts on this Battle.net account only, proven before anything is sent or accepted." })
        cb:SetPoint("TOPLEFT", share, "BOTTOMLEFT", -4, -6)
        page.refreshers[#page.refreshers + 1] = refresh
        page.share = cb
    end)
end

--------------------------------------------------------------------------------
-- The window.

local function navButton(parent, key, text, anchor, gap)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_W - 24, 26)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 2))
    b.text = GP.UI.Label(b, text, "GameFontNormalLarge")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints(b)
    b.selected:SetColorTexture(0.6, 0.55, 0.05, 0.55)
    b.selected:Hide()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b:SetScript("OnClick", function()
        if search then search:SetText("") end
        showPage(key)
    end)
    navItems[key] = b
    return b
end

local function build()
    win = CreateFrame("Frame", Options.NAME, UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    GP.Theme.Window(win, { header = 60 })
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Options.NAME) end

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)

    -- Left: the name, the version, the pages.
    local nav = CreateFrame("Frame", nil, win)
    nav:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -12)
    nav:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 12)
    nav:SetWidth(NAV_W)
    GP.Theme.Reading(win, nav)
    local title = GP.UI.Header(nav, "Glass Pearls", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", nav, "TOPLEFT", 14, -16)
    local version = GP.UI.Label(nav, "Version " .. GP.VersionText())
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    local anchor = navButton(nav, "home", "Home", version, 34)
    for i, category in ipairs(GP.Pearls.Categories()) do
        categoryPage(category)
        anchor = navButton(nav, "cat:" .. category, category, anchor, i == 1 and 18 or 2)
    end
    navButton(nav, "settings", "Settings", anchor, 18)

    -- Right: the page's title, the search box, the page, the Reload button.
    pageTitle = GP.UI.Header(win, "", "GameFontNormalHuge")
    pageTitle:SetPoint("TOPLEFT", nav, "TOPRIGHT", 24, -16)
    pageSub = GP.UI.Label(win, "")
    pageSub:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -6)
    search = GP.UI.Search(win, 220, "Search options", onSearch)
    search:SetPoint("TOPRIGHT", win, "TOPRIGHT", -44, -18)
    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", nav, "TOPRIGHT", 24, -84)
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, 48)
    reloadButton = GP.UI.Button(win, "Reload", 100, function()
        -- From this click only (a hardware event); refused -> ADDON_ACTION_FORBIDDEN below.
        ReloadUI()
    end)
    reloadButton:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -20, 16)
    reloadText = GP.UI.Label(win, "Type /reload to apply.", "GameFontNormal")
    reloadText:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, 20)
    reloadText:Hide()

    homePage()
    settingsPage()
    searchPage()
    win:SetScript("OnShow", function() showPage(current or "home") end)
end

-- The pearls register at load, so the pages are known by the first open.
function Options.Open(page)
    if not win then build() end
    win:Show()
    if page then showPage(page) end
    return true
end

function Options.Toggle()
    if win and win:IsShown() then win:Hide() return end
    Options.Open()
end

function Options.IsOpen() return win ~= nil and win:IsShown() end

-- Refresh what's on screen (a slash command or a synced setting changed something).
function Options.Refresh()
    if win and win:IsShown() and current then showPage(current) end
end

-- The Reload button refused by the client: say "/reload" instead for the session.
local watch = CreateFrame("Frame")
watch:SetScript("OnEvent", function(_, _, addon, fn)
    if addon == ADDON and type(fn) == "string" and fn:find("^ReloadUI") then
        reloadForbidden = true
        API.Fail("reload button", "ADDON_ACTION_FORBIDDEN " .. fn)
        refreshReload()
    end
end)
API.RegisterEvents(watch, { "ADDON_ACTION_FORBIDDEN" })

--------------------------------------------------------------------------------
-- Esc > Options > AddOns: the version and a button to the window. Hidden at
-- creation and built on its first show (else the first visit is blank).

local panel = CreateFrame("Frame")
panel.name = "Glass Pearls"
panel:Hide()
local category

panel:SetScript("OnShow", function(self)
    if self.built then return end
    self.built = true
    local title = GP.UI.Label(self, "Glass Pearls", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -16)
    local version = GP.UI.Label(self, "Version " .. GP.VersionText() .. " for World of Warcraft: Forever, by Spotnick",
        "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    -- Opens over Blizzard's settings (DIALOG strata); never closes them from
    -- here: HideUIPanel from addon code would taint the panel manager.
    local open = GP.UI.Button(self, "Open Glass Pearls", 160, function() Options.Open() end)
    open:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    self.open = open
    local hint = GP.UI.Label(self, "Or type /gpearls.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
end)

-- Called once at PLAYER_LOGIN by GlassPearls.lua, after the look was fixed.
function Options.Register()
    lookChoiceAtLoad = GP.db and GP.db.useGlassUI ~= false
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open Esc > Options > AddOns > Glass Pearls; false when the framework can't.
function Options.OpenSettingsPage()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = {
    panel = panel, pages = pages, navItems = navItems,
    win = function() return win end, search = function() return search end,
    reloadButton = function() return reloadButton end, reloadText = function() return reloadText end,
    current = function() return current end, forbidden = function() return reloadForbidden end,
    reset = function()
        win, body, current, lastMain, reloadForbidden = nil, nil, nil, "home", false
        for k in pairs(pages) do pages[k] = nil end
        for k in pairs(navItems) do navItems[k] = nil end
    end,
}
