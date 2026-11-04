-- Data/Books.lua (#72): the generated library books are well formed and match
-- their source (Tools/books/books.csv): every book once, with its quest, a
-- known status and faction, world positions on Azeroth with their zone map
-- and coordinates, hand spots where the CSV gives them, and the build.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GP = loadAddon({ pearls = false })
local D = GP.BookData
check(type(D) == "table", "the data loads")
eq(D.build, "1.60.1.70532", "built from the measured client build's tables")

local function isNum(v) return type(v) == "number" and v == v end
local CONTINENTS = { [0] = true, [1] = true }
local STATUS = { unconfirmed = true, absent = true }
local FACTION = { Alliance = true, Horde = true }

local seen, quests = {}, {}
for _, b in ipairs(D.books) do
    local id = tostring(b.item)
    check(isNum(b.item) and not seen[b.item], "a book once: " .. id)
    seen[b.item] = b
    check(isNum(b.quest) and b.quest > 0 and not quests[b.quest], id .. ": its own quest")
    quests[b.quest] = true
    check(b.status == nil or STATUS[b.status], id .. ": a known status")
    check(b.faction == nil or FACTION[b.faction], id .. ": a known faction")
    check(b.note == nil or (type(b.note) == "string" and b.note ~= ""), id .. ": a note or none")
    check(#b.spots >= 1, id .. ": at least one spot")
    for _, s in ipairs(b.spots) do
        check(CONTINENTS[s.c] and isNum(s.x) and isNum(s.y), id .. ": a world position on Azeroth")
        check(isNum(s.zone) and isNum(s.mx) and isNum(s.my) and s.mx > 0 and s.mx < 100 and s.my > 0 and s.my < 100,
            id .. ": its zone map and coordinates")
    end
end
eq(#D.books, 40, "40 books")

-- Every CSV row is there, with its status, faction, hand spot and entrance.
local rows = 0
for line in io.lines("Tools/books/books.csv") do
    local item, quest, faction, status, spots, zone, x, y, entrance =
        line:match("^(%d+),(%d+),(%a*),(%a+),(%a+),(%d*),([%d.]*),([%d.]*),(%d*),")
    if item then
        rows = rows + 1
        local b = seen[tonumber(item)]
        check(b ~= nil, item .. ": in the data")
        if b then
            eq(b.quest, tonumber(quest), item .. ": the CSV's quest")
            eq(b.faction, faction ~= "" and faction or nil, item .. ": the CSV's faction")
            eq(b.status, status ~= "ok" and status or nil, item .. ": the CSV's status")
            eq(b.hand == true, spots == "hand", item .. ": hand spots as the CSV says")
            eq(b.entrance == true, entrance == "1", item .. ": the entrance flag")
            if spots == "hand" then
                eq(#b.spots, 1, item .. ": one hand spot")
                eq(b.spots[1].zone, tonumber(zone), item .. ": in the CSV's zone")
                eq(b.spots[1].mx, tonumber(x), item .. ": at its x")
                eq(b.spots[1].my, tonumber(y), item .. ": and y")
            end
        end
    end
end
eq(rows, #D.books, "the CSV and the data have the same books")

-- The two books by faction, the absent one, the cave.
eq(seen[208860].faction, "Alliance", "Rumi of Gnomeregan: the Alliance's")
eq(seen[207972].faction, "Horde", "The Lessons of Ta'zo: the Horde's")
eq(seen[220347].status, "absent", "The Liminal and the Arcane: absent from Forever")
check(seen[209846].entrance, "Secrets of the Dreamers: a cave entrance")
eq(#seen[228135].spots, 2, "A Study of the Light: two places")

done("test_books_data")
