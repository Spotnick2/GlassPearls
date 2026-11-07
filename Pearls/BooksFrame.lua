-- Pearls/BooksFrame.lua: the library books' toast and Configuration Panel
-- (#72). The logic is Pearls/Books.lua; this file draws the view it gives.
--
-- The toast: "Library book nearby", the book's icon and name, where it is,
-- about how far, a note. It stays until its OK button is clicked: no timeout,
-- not in UISpecialFrames (Esc leaves it), the owner's choice. A new book
-- replaces what it shows. Drags and remembers where (per character); top
-- centre otherwise.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local Frame = {}
GP.BooksFrame = Frame

Frame.NAME = "GlassPearlsBooksFrame"
local W, PAD, ICON = 360, 18, 36

local f   -- built on first show

local function place()
    f:ClearAllPoints()
    local db = GP.charDB and GP.charDB.booksToast
    if db and type(db.x) == "number" and type(db.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
end

local function build()
    f = CreateFrame("Frame", Frame.NAME, UIParent)
    f:SetSize(W, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if GP.charDB and type(left) == "number" and type(top) == "number" then
            GP.charDB.booksToast = { x = left, y = top }
        end
    end)
    f:Hide()
    GP.Theme.Window(f, { header = 44 })
    f.title = GP.UI.Header(f, "Library book nearby")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -16)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ICON, ICON)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -50)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.lines = {}
    local fonts = { "GameFontNormal", "GameFontHighlightSmall", "GameFontHighlightSmall", "GameFontDisableSmall",
                    "GameFontDisableSmall" }
    for i, font in ipairs(fonts) do
        local l = GP.UI.Label(f, "", font)
        l:SetWidth(W - 2 * PAD - ICON - 10)
        l:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ICON + 10, -50 - (i - 1) * 16)
        f.lines[i] = l
    end
    f.ok = GP.UI.Button(f, "OK", 70, function() Frame.Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 14)
end

-- view = { name, icon, where, distance, note, unconfirmed }
function Frame.Show(view)
    if not f then build() end
    f.icon:SetTexture(view.icon)
    local texts = { view.name, view.where, view.distance, view.note,
                    view.unconfirmed and "Not confirmed in WoW Forever" or nil }
    local n = 0   -- what's set, in order (nil entries leave holes)
    for i = 1, 5 do
        if texts[i] then
            n = n + 1
            f.lines[n]:SetText(texts[i])
            f.lines[n]:Show()
        end
    end
    for i = n + 1, #f.lines do f.lines[i]:Hide() end
    f:SetHeight(math.max(50 + ICON, 50 + n * 16) + 50)
    f.view = view
    if not f:IsShown() then place() end
    f:Show()
end

function Frame.Hide()
    if f then f:Hide() end
end

function Frame.IsShown() return f ~= nil and f:IsShown() end
function Frame.Get() return f end

--------------------------------------------------------------------------------
-- The Configuration Panel

function Frame.Configure(panel, refreshers)
    local P, KEY = GP.Pearls, GP.Books.KEY
    local function check(anchor, text, name, x, y)
        local cb, refresh = GP.UI.Check(panel, text,
            function() return P.Setting(KEY, name) end, function(v) P.SetSetting(KEY, name, v) end)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
        refreshers[#refreshers + 1] = refresh
        return cb
    end
    local head = GP.UI.Header(panel, "Library books")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local a = check(head, "On the world map", "worldmap", -4, -6)
    a = check(a, "On the minimap", "minimap")
    a = check(a, "A note when I come near one I still need", "nearby")
    a = check(a, "Then a compass pointing at it", "compass", 16)
    local test = GP.UI.Button(panel, "Test", 90, function()
        if not GP.Books.enabled then return API.Print("Library books is off: /gpearls books on.") end
        local book = GP.BookData.books[1]
        Frame.Show(GP.Books.View(book, book.spots[1], 42))
    end)
    test:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 4, -10)
    local note = GP.UI.Label(panel,
        "Books you carry, keep in your bank or have handed in aren't shown. The bank is read when you open it: "
            .. "until you have once, books can't be told apart from ones in your bank, so no note comes.",
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -8)
    note:SetWidth(380)
    note:SetWordWrap(true)
    panel.test = test
end
