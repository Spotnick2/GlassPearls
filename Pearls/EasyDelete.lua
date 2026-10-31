-- Pearls/EasyDelete.lua: easy delete (#40). When the client asks you to type
-- DELETE to destroy a good item, it is filled in for you and the item named
-- in chat (its link), so one click on Yes confirms. Only up to the quality
-- you choose (`upTo`, epic by default): above it, the typing stays yours.
--
-- Forever's handler (Camelot/EventImplementation.lua:47) shows DELETE_GOOD_ITEM
-- (or its quest variant) for Rare and better, not Heirloom, with the item's
-- GUID as the dialog's data; its edit box enables Yes once the text reads
-- DELETE_ITEM_CONFIRM_STRING (StaticPopup.lua:140, any text change). So the
-- fill is the edit box's own SetText, a frame after the event (after
-- Blizzard's handler showed the popup), only when that dialog, its data and
-- the cursor all name the same item and the box is still empty. Nothing is
-- ever written on the dialog or its data, the delete is never called (Yes
-- and Enter are Blizzard's), and the gamepad popups (no edit box) are left.
-- Unmeasured until 2026-11-04 (docs/PLAN.md, day one: the fill and taint).

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local API = GP.API
local ED = {}
GP.EasyDelete = ED

ED.KEY = "easydelete"
ED.LEVELS = { rare = 3, epic = 4, legendary = 5 }
ED.CHOICES = { "rare", "epic", "legendary" }
ED.POPUP, ED.QUEST_POPUP = "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM"

local events = CreateFrame("Frame")
local state = { token = 0, last = "nothing yet" }
ED.state = state

local function say(msg) API.Print(msg) end
local function setting(name) return GP.Pearls.Setting(ED.KEY, name) end

local function plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

local function text(v)
    v = plain(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

-- The highest quality filled in, by the current setting.
local function limit() return ED.LEVELS[setting("upTo")] or ED.LEVELS.epic end

local function eligible(quality)
    -- Heirloom (7) is above every limit.
    return type(quality) == "number" and quality % 1 == 0 and quality >= ED.LEVELS.rare and quality <= limit()
end

local function skip(why) state.last = why end

-- One frame after the event: fill the box, or nothing.
local function fill(token, quality, quest, guid)
    if state.token ~= token then return end        -- Disable stales it too
    if not eligible(quality) then return skip("above your chosen quality now") end
    local ok, dialog = pcall(StaticPopup_FindVisible, quest and ED.QUEST_POPUP or ED.POPUP)
    if type(dialog) ~= "table" then return skip("no delete popup") end   -- a throw leaves a string
    local data = plain(dialog.data)
    if type(data) ~= "table" or text(data.itemGUID) ~= guid then return skip("the popup names another item") end
    local okC, loc = pcall(C_Cursor.GetCursorItem)
    local okG, cursorGUID = false, nil
    if okC and type(plain(loc)) == "table" then okG, cursorGUID = pcall(C_Item.GetItemGUID, loc) end
    if not okG or text(cursorGUID) ~= guid then return skip("the cursor holds another item") end
    local okB, box = pcall(dialog.GetEditBox, dialog)
    if not okB or type(plain(box)) ~= "table" then return skip("no edit box") end
    local okT, typed = pcall(box.GetText, box)
    if not okT or plain(typed) ~= "" then return skip("you have started typing") end
    local okL, link = pcall(C_Item.GetItemLinkByGUID, guid)
    link = okL and text(link) or nil
    if not link then return skip("the item's link unreadable") end
    local okS, err = pcall(box.SetText, box, DELETE_ITEM_CONFIRM_STRING)
    if not okS then
        API.Fail("pearl easydelete fill", err)
        return skip("the fill failed")
    end
    skip("filled in for " .. link)
    say(("Easy delete: %s filled in for %s: Yes destroys it."):format(DELETE_ITEM_CONFIRM_STRING, link))
end

events:SetScript("OnEvent", function(_, event, ...)
    if event ~= "DELETE_ITEM_CONFIRM" then return end
    state.token = state.token + 1                 -- a new event stales the last, whatever it is
    local token = state.token
    local _, quality, _, questWarn, guid = ...
    quality, questWarn, guid = plain(quality), plain(questWarn), text(guid)
    if questWarn ~= 0 and questWarn ~= 1 then return skip("the quest flag unreadable") end
    local okP, pad = pcall(InputUtil.IsGamepadUIEnabled)
    if not okP or plain(pad) ~= false then return skip("the gamepad popup") end
    C_Timer.After(0, function() fill(token, quality, questWarn == 1, guid) end)
end)

function ED.Report()
    say(("Easy delete: %s, up to %s. Last: %s."):format(ED.enabled and "on" or "off", setting("upTo"), state.last))
end

local function configure(panel, refreshers)
    local KEY, P = ED.KEY, GP.Pearls
    local head = GP.UI.Header(panel, "Fill in DELETE for items up to")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local last, _, refresh = GP.UI.Radios(panel, head,
        { { "rare", "Rare" }, { "epic", "Epic" }, { "legendary", "Legendary" } },
        function() return P.Setting(KEY, "upTo") end, function(v) P.SetSetting(KEY, "upTo", v) end)
    refreshers[#refreshers + 1] = refresh
    local note = GP.UI.Label(panel,
        "Above that quality you still type it yourself. Once filled in, Yes or Enter destroys the item. "
            .. "Unverified until the game is live.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    note:SetWidth(380)
    note:SetWordWrap(true)
end

local function enable()
    ED.enabled = true
    API.RegisterEvents(events, { "DELETE_ITEM_CONFIRM" })
end

local function disable()
    ED.enabled = false
    state.token = state.token + 1
    events:UnregisterAllEvents()
end

GP.Pearls.Register({
    key = ED.KEY,
    name = "Easy delete",
    desc = "Fills in DELETE when destroying a good item, and names it in chat.",
    help = "When the game asks you to type DELETE to destroy a Rare or better item, it is filled in for you and "
        .. "the item's link is said in your chat, so one click on Yes confirms. Only up to the quality you choose "
        .. "(Epic by default): above it, you still type it. Once filled in, Yes or Enter destroys the item. "
        .. "/gpearls easydelete shows the last fill. Unverified until the game is live.",
    default = false,
    category = "Loot & Bags",
    section = "Bags",
    defaults = { upTo = "epic" },
    choices = { upTo = ED.CHOICES },
    Enable = enable,
    Disable = disable,
    configure = configure,
    commands = { easydelete = { help = "- what easy delete last filled in or skipped",
        run = function() ED.Report() end } },
})

ED._test = { events = events }
