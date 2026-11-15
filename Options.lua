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
local lookChoiceAtLoad, ownLookAtLoad

--------------------------------------------------------------------------------
-- Pending reload: a pearl switched off that can't stop live, or the look
-- choice changed since this session's look was built.

-- The own look as it applies (#119): unanswered reads as WoW Forever.
local function ownLook() return GP.db and rawget(GP.db, "look") or "forever" end

-- The Glass UI switch changed since load, or, while Glass UI isn't driving
-- this session's look, the own look did (#119: an own look received while
-- following stays inactive, so nothing waits for a reload).
function Options.LookPending()
    if lookChoiceAtLoad == nil or not GP.db then return false end
    if (GP.db.useGlassUI ~= false) ~= lookChoiceAtLoad then return true end
    return not GP.Theme.Following() and ownLook() ~= ownLookAtLoad
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
    assert(body, "Options: a page made before the window's body")
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
--
-- The panel (`content`) sits in a scroll frame that scrolls only when the
-- panel is taller than its space (#107): the scroll child's height is
-- measured from what is shown in the panel, on every show and a frame later
-- (text has its size then), so a panel that fits looks as before and the bar
-- stays hidden. The scroll frame clips, so it starts PANEL_INSET above and
-- left of the panel, for what a panel places past its own edge (a checkbox 4
-- left of its header); the bar takes PANEL_BAR on the right.

Options.PANEL_BOTTOM, Options.PANEL_INSET, Options.PANEL_BAR = 70, 8, 22

-- The lowest bottom of anything shown in `f`, its own children's included.
local function lowest(f, low)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsShown() then
            local b = r:GetBottom()
            if type(b) == "number" and b < low then low = b end
        end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        if c:IsShown() then
            local b = c:GetBottom()
            if type(b) == "number" and b < low then low = b end
            low = lowest(c, low)
        end
    end
    return low
end

-- The scroll child's height: the panel's own, measured, or the view's when
-- shorter or unreadable (a layout not resolved yet).
function Options.FitPanel(page)
    local scroll, holder = page.scroll, page.holder
    if not scroll then return end
    local view, top = scroll:GetHeight(), holder:GetTop()
    if type(view) ~= "number" or view <= 0 then return end
    local need = 0
    if type(top) == "number" then need = top - lowest(page.content, top) + Options.PANEL_INSET * 2 end
    holder:SetHeight(math.max(view, need))
end

local function panelArea(page)
    local inset = Options.PANEL_INSET
    local scroll = CreateFrame("ScrollFrame", nil, page.frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page.frame, "TOPLEFT", -inset, inset)
    scroll:SetPoint("BOTTOMRIGHT", page.frame, "BOTTOMRIGHT", -Options.PANEL_BAR, Options.PANEL_BOTTOM)
    local holder = CreateFrame("Frame", nil, scroll)
    holder:SetSize(1, 1)
    scroll:SetScrollChild(holder)
    local content = CreateFrame("Frame", nil, holder)
    content:SetPoint("TOPLEFT", holder, "TOPLEFT", inset, -inset)
    content:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -inset)
    local function size()
        local w, h = scroll:GetWidth(), scroll:GetHeight()
        if type(w) == "number" and w > 0 then holder:SetWidth(w) end
        if type(h) == "number" and h > inset then content:SetHeight(h - inset) end
    end
    scroll:HookScript("OnSizeChanged", function() size(); Options.FitPanel(page) end)
    size()
    API.AutoHideScrollBar(scroll)
    page.scroll, page.holder, page.content = scroll, holder, content
    return content
end

function Options.ShowConfig(key)
    local def = GP.Pearls.Get(key)
    if not def or not def.configure then return false end
    local name = "config:" .. key
    if not pages[name] then
        local page = newPage(name, def.name, function(page)
            local content = panelArea(page)
            local ok, err = pcall(def.configure, content, page.refreshers)
            if not ok then
                API.Fail("pearl " .. key .. " configure", err)
                GP.UI.Label(content, "This panel failed to build: /gpearls failures"):SetPoint("TOPLEFT", content, "TOPLEFT")
            end
            -- Last of the refreshers, so it measures what they showed; again a frame later.
            page.refreshers[#page.refreshers + 1] = function()
                Options.FitPanel(page)
                C_Timer.After(0, function() Options.FitPanel(page) end)
            end
            page.help = GP.UI.Label(page.frame, def.help or def.desc or "", "GameFontHighlight")
            page.help:SetPoint("BOTTOMLEFT", page.frame, "BOTTOMLEFT", 0, 36)
            page.help:SetWidth(W - NAV_W - 60)
            page.help:SetWordWrap(true)
            page.help:Hide()
            page.reset = GP.UI.Button(page.frame, "Reset", 90, function()
                GP.Pearls.ResetSettings(key)
                for _, refresh in ipairs(page.refreshers) do refresh() end   -- the fit included
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
        local refreshLook   -- below: the radios follow the box at once
        if GP.Theme.SuiteAvailable() then
            local cb, refresh = GP.UI.Check(f, "Use Glass UI appearance",
                function() return GP.db.useGlassUI ~= false end,
                function(on) GP.Settings.SetUseGlassUI(on) end,
                { tip = "Glass UI's glass, tint and accent instead of the look chosen below. Takes effect after a reload.",
                  onChange = function() refreshReload(); refreshLook() end })
            cb:SetPoint("TOPLEFT", look, "BOTTOMLEFT", -4, -6)
            page.refreshers[#page.refreshers + 1] = refresh
            page.useGlass = cb
            last = cb
        end
        -- The own look (#119), used whenever Glass UI isn't driving it.
        local first, radios, refreshRadios = GP.UI.Radios(f, last,
            { { "forever", "WoW Forever" }, { "pearl", "Pearl" } }, ownLook,
            function(v) GP.Settings.SetLook(v); refreshReload() end, { across = true })
        if last ~= look then first:ClearAllPoints(); first:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -4) end
        local note = GP.UI.Label(f, "", "GameFontDisable")
        note:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -6)
        -- Greyed out, labels too, while the Glass UI box is ticked (the owner).
        refreshLook = function()
            refreshRadios()
            local driven = GP.Theme.SuiteAvailable() and GP.db.useGlassUI ~= false
            for _, rb in ipairs(radios) do
                rb:SetEnabled(not driven)
                local label = rb.text or rb.label
                if label then label:SetFontObject(driven and "GameFontDisable" or "GameFontHighlight") end
            end
            note:SetText(driven and "Set in Glass UI while Glass Pearls follows it."
                or "The look of Glass Pearls' windows without Glass UI. Takes effect after a reload.")
        end
        page.refreshers[#page.refreshers + 1] = refreshLook
        page.lookRadios, page.lookNote = radios, note
        last = note
        local share = GP.UI.Header(f, "Your other accounts")
        share:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -18)
        local cb, refresh = GP.UI.Check(f, "Share settings with my other WoW accounts",
            GP.AccountSync.IsEnabled, GP.AccountSync.SetEnabled,
            { tip = "Your own accounts on this Battle.net account only, proven before anything is sent or accepted." })
        cb:SetPoint("TOPLEFT", share, "BOTTOMLEFT", -4, -6)
        page.refreshers[#page.refreshers + 1] = refresh
        page.share = cb
        local mm, refreshMm = GP.UI.Check(f, "Show the minimap button", GP.Minimap.Shown, GP.Minimap.SetShown,
            { tip = "The glass pearl on the minimap: left-click opens this window, right-click Settings. On this account." })
        mm:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -4)
        page.refreshers[#page.refreshers + 1] = refreshMm
        page.minimap = mm
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

    -- The two columns: the nav on the left, `body` (every page's parent) on
    -- the right. Both before any page: a page is a child of `body` and
    -- anchored to it, and a nil parent would leave it loose on the screen,
    -- outliving the window (Codex review of #7).
    local nav = CreateFrame("Frame", nil, win)
    nav:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -12)
    nav:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 12)
    nav:SetWidth(NAV_W)
    GP.Theme.Reading(win, nav)
    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", nav, "TOPRIGHT", 24, -84)
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, 48)

    -- Left: the name, the version, the pages.
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

    -- Right: the page's title, the search box, the Reload button.
    pageTitle = GP.UI.Header(win, "", "GameFontNormalHuge")
    pageTitle:SetPoint("TOPLEFT", nav, "TOPRIGHT", 24, -16)
    pageSub = GP.UI.Label(win, "")
    pageSub:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -6)
    search = GP.UI.Search(win, 220, "Search options", onSearch)
    search:SetPoint("TOPRIGHT", win, "TOPRIGHT", -44, -18)
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

--------------------------------------------------------------------------------
-- The look question (#119, Codex three rounds): asked while no look is chosen
-- and Glass UI isn't driving the look, 10 s after a first login (settings
-- sync's login exchange may bring another account's answer first), after
-- combat if need be, once a session. One state, choosing: a button saves the
-- answer and closes; Pearl also says to /reload (never ReloadUI: protected).
-- Closed unanswered: asked again at the next login. Any chosen look (a
-- button, Settings, sync) closes it or cancels it.

Options.PROMPT_DELAY = 10
local prompt, promptPending, promptAsked = nil, false, false

local function promptEligible()
    return GP.db ~= nil and rawget(GP.db, "look") == nil and not GP.Theme.Following()
end

local function refreshPrompt()
    if promptEligible() then return end
    promptPending = false
    if prompt and prompt:IsShown() then prompt:Hide() end
end

local function choose(v)
    if not promptEligible() then
        if prompt then prompt:Hide() end
        return
    end
    GP.Settings.SetLook(v)            -- its refresh closes the window
    if prompt then prompt:Hide() end
    if v == "pearl" then API.Print("Pearl is saved; type /reload to apply.") end
end

local function buildPrompt()
    prompt = CreateFrame("Frame", "GlassPearlsLookPrompt", UIParent)
    prompt:SetSize(380, 150)
    prompt:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    prompt:SetFrameStrata("DIALOG")
    prompt:EnableMouse(true)
    prompt:Hide()
    GP.Theme.Window(prompt, { header = 36 })
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GlassPearlsLookPrompt") end
    local title = GP.UI.Header(prompt, "Glass Pearls")
    title:SetPoint("TOPLEFT", prompt, "TOPLEFT", 18, -16)
    local text = GP.UI.Label(prompt, "Choose a look for Glass Pearls' windows. Settings can change it later.")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetWidth(344)
    text:SetWordWrap(true)
    prompt.forever = GP.UI.Button(prompt, "WoW Forever", 150, function() choose("forever") end)
    prompt.forever:SetPoint("BOTTOMLEFT", prompt, "BOTTOMLEFT", 22, 18)
    prompt.pearl = GP.UI.Button(prompt, "Pearl", 150, function() choose("pearl") end)
    prompt.pearl:SetPoint("BOTTOMRIGHT", prompt, "BOTTOMRIGHT", -22, 18)
    local close = CreateFrame("Button", nil, prompt, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", prompt, "TOPRIGHT", -4, -4)
end

local function showPrompt()
    if not promptEligible() then promptPending = false return end
    if API.InCombat() then promptPending = true return end
    promptPending = false
    if not prompt then buildPrompt() end
    prompt:Show()
end

local promptEvents = CreateFrame("Frame")
promptEvents:SetScript("OnEvent", function(_, event, isInitialLogin)
    API.NoteCombat(event)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInitialLogin ~= true or promptAsked then return end
        promptAsked = true
        C_Timer.After(Options.PROMPT_DELAY, showPrompt)
    elseif event == "PLAYER_REGEN_ENABLED" and promptPending then
        showPrompt()
    end
end)

-- Refresh what's on screen (a slash command or a synced setting changed something).
function Options.Refresh()
    if win and win:IsShown() and current then showPage(current) end
    refreshPrompt()
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
    ownLookAtLoad = ownLook()
    API.RegisterEvents(promptEvents, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
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
    win = function() return win end, body = function() return body end, search = function() return search end,
    reloadButton = function() return reloadButton end, reloadText = function() return reloadText end,
    current = function() return current end, forbidden = function() return reloadForbidden end,
    prompt = function() return prompt end, promptPending = function() return promptPending end,
    resetPrompt = function()
        if prompt then prompt:Hide() end
        promptPending, promptAsked = false, false
    end,
    reset = function()
        win, body, current, lastMain, reloadForbidden = nil, nil, nil, "home", false
        for k in pairs(pages) do pages[k] = nil end
        for k in pairs(navItems) do navItems[k] = nil end
    end,
}
