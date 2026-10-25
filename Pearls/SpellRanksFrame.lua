-- Pearls/SpellRanksFrame.lua: the low spell ranks popup and its Configuration
-- Panel (#12). The logic is Pearls/SpellRanks.lua; this file draws the rows it
-- gives and forwards clicks.
--
-- The popup: "Low spell ranks", a line under it, pages of MAX_ROWS rows (the
-- spell's icon, its name, "Rank 1 > Rank 4", what it is: "(3 buttons)", "in a
-- macro: edit by hand", "was cast: not on your bars", a Keep button) with
-- < n/N > past one page, then Later and Update all. Esc closes it (UISpecialFrames); it drags
-- and remembers where (per character); above the centre otherwise. Each row's
-- tooltip is the rank it would get.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.SpellRanksFrame = Frame

Frame.NAME = "GlassPearlsSpellRanksFrame"
Frame.MAX_ROWS = 8
local W, ROW_H, TOP, BOTTOM = 440, 30, 62, 50
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f   -- built on first show

local function SR() return GP.SpellRanks end
local function rankWord() return rawget(_G, "RANK") or "Rank" end

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function Frame.SpellName(id)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and plainString(n) or ("Spell " .. id)
end

local function icon(id)
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(t) and (type(t) == "number" or type(t) == "string") then return t end
    return QUESTION
end

-- What a row says after its ranks.
function Frame.RowNote(r)
    if r.kind == "macro" then
        return "in a macro" .. (r.macro and (" (" .. r.macro .. ")") or "") .. ": edit by hand"
    elseif r.kind == "cast" then
        return "was cast: not on your bars"
    end
    local n = #r.slots
    local note = n > 1 and (n .. " buttons") or ""
    if r.stance then note = note .. (note ~= "" and ", " or "") .. "a stance or form bar" end
    return note
end

function Frame.RowText(r)
    local note = Frame.RowNote(r)
    return Frame.SpellName(r.id) .. "   |cff9d9d9d" .. rankWord() .. " " .. r.rank .. "|r  >  |cffffd35a"
        .. rankWord() .. " " .. r.bestRank .. "|r" .. (note ~= "" and ("  |cff9d9d9d(" .. note .. ")|r") or "")
end

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.spellranks
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function newRow(i)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 36, ROW_H - 2)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -TOP - (i - 1) * ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = GP.UI.Label(r, "")
    r.text:SetPoint("LEFT", r, "LEFT", 34, 0)
    r.text:SetWidth(W - 36 - 34 - 74)
    r.keep = GP.UI.Button(r, "Keep", 64, function() SR().Keep(r.entry) end)
    r.keep:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    GP.UI.Tooltip(r.keep, "Keep this rank",
        "For a spell you use in a low rank on purpose. This rank isn't listed again, on any of your accounts; "
        .. "the gear on Glass Pearls' Combat page lists the kept ones.")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.entry.best) then
            GameTooltip:SetText(Frame.SpellName(self.entry.best))
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, TOP + BOTTOM + ROW_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.spellranks = { x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 52 })
    f.title = GP.UI.Header(f, "Low spell ranks")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    f.sub = GP.UI.Label(f, "", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sub:SetWidth(W - 60)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() SR().Later() end)
    f.rows = {}
    -- Pages of MAX_ROWS: every finding reachable, each with its Keep.
    f.prev = GP.UI.Button(f, "<", 24, function() Frame.Page(-1) end)
    f.prev:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
    f.pageText = GP.UI.Label(f, "", "GameFontHighlightSmall")
    f.pageText:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
    f.next = GP.UI.Button(f, ">", 24, function() Frame.Page(1) end)
    f.next:SetPoint("LEFT", f.pageText, "RIGHT", 6, 0)
    f.update = GP.UI.Button(f, "Update all", 120, function()
        -- The change runs inside this click (Pearls/SpellRanks.lua).
        SR().Update(f.entries)
    end)
    f.update:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    GP.UI.Tooltip(f.update, "Update all",
        "Puts the highest rank you know on these buttons (same place, same key). Macros aren't changed.")
    f.later = GP.UI.Button(f, "Later", 90, function() SR().Later() end)
    f.later:SetPoint("RIGHT", f.update, "LEFT", -8, 0)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Frame.NAME) end
end

-- Show these rows. opts.byHand: the game refused a change this session;
-- opts.focus: the index of the first new finding, whose page is shown.
function Frame.Show(rows, opts)
    opts = opts or {}
    if not f then build() end
    f.entries, f.opts = rows, { byHand = opts.byHand }   -- a page click re-shows without focus
    local bars, others = 0, 0
    for _, r in ipairs(rows) do
        if r.kind == "bar" then bars = bars + 1 else others = others + 1 end
    end
    if opts.byHand then
        f.sub:SetText("Drag the highest rank from your spellbook onto each button: the game refused a change.")
    elseif bars > 0 then
        f.sub:SetText("These action buttons use a lower rank than you know.")
    else
        f.sub:SetText("These spells were used in a lower rank than you know.")
    end
    local per = Frame.MAX_ROWS
    local pages = math.max(1, math.ceil(#rows / per))
    -- A new finding: its page. Opening afresh: page 1. A refresh of the open
    -- popup (after Keep, a page click): the page it was on.
    if opts.focus then
        f.page = math.ceil(opts.focus / per)
    elseif not f:IsShown() then
        f.page = 1
    end
    f.page = math.min(math.max(f.page or 1, 1), pages)
    local first = (f.page - 1) * per
    for i = 1, per do
        local row = f.rows[i]
        local e = rows[first + i]
        if e then
            if not row then
                row = newRow(i)
                f.rows[i] = row
            end
            row.entry = e
            row.icon:SetTexture(icon(e.best))
            row.text:SetText(Frame.RowText(e))
            row:Show()
        elseif row then
            row.entry = nil
            row:Hide()
        end
    end
    f.pageText:SetText(pages > 1 and (f.page .. "/" .. pages) or "")
    f.prev:SetShown(pages > 1)
    f.next:SetShown(pages > 1)
    f.prev:SetEnabled(f.page > 1)
    f.next:SetEnabled(f.page < pages)
    f.update:SetShown(bars > 0)
    f.update:SetEnabled(bars > 0 and not opts.byHand)
    -- As tall as a full page, so paging doesn't move the buttons.
    f:SetHeight(TOP + BOTTOM + math.min(#rows, per) * ROW_H)
    place()
    f:Show()
end

function Frame.Page(delta)
    if not (f and f.entries) then return end
    f.page = (f.page or 1) + delta
    Frame.Show(f.entries, f.opts)
end

function Frame.Hide()
    if f then f:Hide() end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end

--------------------------------------------------------------------------------
-- The Configuration Panel: when it checks, what it lists, the kept ranks.

local PAGE = 6

function Frame.Configure(panel, refreshers)
    local KEY, P, SS = "spellranks", GP.Pearls, GP.SettingsSync
    local function check(anchor, text, name, tip, x, y)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(on) P.SetSetting(KEY, name, on) end, { tip = tip })
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local when = GP.UI.Header(panel, "When it checks")
    when:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(when, "After you learn a spell", "afterLearning",
        "A few seconds after, or when the class trainer's window closes.", -4, -6)
    a = check(a, "After a dual-spec swap", "afterSpecSwap", "Each spec has its own bars.")
    a = check(a, "At login", "atLogin")
    local what = GP.UI.Header(panel, "What it lists")
    what:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -14)
    a = check(what, "Low ranks you cast", "warnCasts",
        "A lower rank you cast from a key, a macro or anywhere: listed after combat.", -4, -6)
    a = check(a, "Low ranks in macros", "macros", "Listed only: a macro is yours to edit.")
    local now = GP.UI.Button(panel, "Check now", 110, function() SR().CheckNow() end)
    now:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -10)

    local listHead = GP.UI.Header(panel, "Kept ranks")
    listHead:SetPoint("TOPLEFT", now, "BOTTOMLEFT", 0, -16)
    local count = GP.UI.Label(panel, "", "GameFontDisableSmall")
    count:SetPoint("LEFT", listHead, "RIGHT", 10, 0)
    local note = GP.UI.Label(panel, "Removing a rank lists it again; the room it took on the shared list stays used.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -4)
    local rows, page = {}, 1
    local function refreshList()
        local ids = SS.SetMembers(SR().KEEP)
        local pages = math.max(1, math.ceil(#ids / PAGE))
        if page > pages then page = pages end
        count:SetText(#ids == 0 and "Keep in the list adds a rank here" or (#ids .. " rank(s)"))
        for i = 1, PAGE do
            local row = rows[i]
            local id = ids[(page - 1) * PAGE + i]
            row.id = id
            if id then
                local e = SR().Entry(id)
                row.label:SetText(Frame.SpellName(id) .. (e and ("  |cff9d9d9d(" .. rankWord() .. " " .. e[2] .. ")|r") or ""))
                row.label:Show()
                row.remove:Show()
            else
                row.label:Hide()
                row.remove:Hide()
            end
        end
        panel.pageText:SetText(pages > 1 and (page .. "/" .. pages) or "")
        panel.prevPage:SetShown(pages > 1)
        panel.nextPage:SetShown(pages > 1)
        panel.clear:SetEnabled(#ids > 0)
    end
    for i = 1, PAGE do
        local row = {}
        row.remove = GP.UI.Button(panel, "Remove", 70, function()
            if row.id then SS.SetRemove(SR().KEEP, row.id) end
            refreshList()
        end)
        row.remove:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6 - (i - 1) * 24)
        row.label = GP.UI.Label(panel, "")
        row.label:SetPoint("LEFT", row.remove, "RIGHT", 8, 0)
        rows[i] = row
    end
    panel.rows = rows
    panel.prevPage = GP.UI.Button(panel, "<", 24, function() page = math.max(1, page - 1); refreshList() end)
    panel.prevPage:SetPoint("TOPLEFT", rows[PAGE].remove, "BOTTOMLEFT", 0, -8)
    panel.pageText = GP.UI.Label(panel, "", "GameFontHighlightSmall")
    panel.pageText:SetPoint("LEFT", panel.prevPage, "RIGHT", 6, 0)
    panel.nextPage = GP.UI.Button(panel, ">", 24, function() page = page + 1; refreshList() end)
    panel.nextPage:SetPoint("LEFT", panel.pageText, "RIGHT", 6, 0)
    panel.clear = GP.UI.Button(panel, "Clear all", 90, function()
        SS.SetClear(SR().KEEP)
        refreshList()
    end)
    panel.clear:SetPoint("LEFT", panel.nextPage, "RIGHT", 16, 0)
    refreshers[#refreshers + 1] = refreshList
    panel.refreshList = refreshList
end

Frame._test = { frame = function() return f end }
