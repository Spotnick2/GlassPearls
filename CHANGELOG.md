# Changelog

## v0.1.0

- **The options window** (`/gpearls`): pages on the left (Home, each category of features,
  Settings), the features in two columns with one checkbox each, a gear beside a feature with
  options that opens its own panel (Reset, Help, Back to Main Menu), a `*` on a feature that needs
  a reload to switch off and a Reload button while one waits, and a search box over every feature.
  Esc closes it; Esc > Options > AddOns > Glass Pearls has a button to it.
- **WoW Forever's own look** by default. With Glass UI installed, Glass Pearls follows its glass
  (Settings > "Use Glass UI appearance" turns that off).
- Each feature is switched on or off on its own, and only your choices are saved.
- **Your settings follow you across your own WoW accounts** on the same Battle.net account,
  automatically: change something on one and the others pick it up, including an account that was
  offline at the time. The most recent change wins, setting by setting. Settings > "Share settings
  with my other WoW accounts" turns it off; `/gpearls sync` shows what was last sent and received.
- **Bags full helper** (Loot & Bags, on by default): when loot doesn't fit, it offers to destroy
  the cheapest item in your bags and loot in one click.
  - It only shows when an item really doesn't fit: a partial stack or a matching herb / mining bag
    counts as room. After "Inventory is full" at a node or quest object, it helps make room.
  - It offers grey items, or grey and white (white needs a second click), cheapest first by vendor
    value times stack, greys first. Quest items, tools, equipment-set items, consumables,
    containers, reagents, ammunition, recipes, keys and items with a use are never offered.
  - Browse the suggestions with < >, or never suggest an item again with the X (on all your
    characters and accounts); quest loot is picked first. When the loot is worth less than
    anything in your bags it says so, and "Choose anyway" is there if you want it.
  - The gear: grey only or grey and white, greys first, and the never-suggest list.
    `/gpearls cheapest` shows the first suggestion any time.
- **Map landmarks** (Interface, on by default): dungeon and raid entrances, boats, zeppelins and
  the Deeprun Tram on the world map (zone and continent) and the minimap, and flight points where
  the game's map shows none.
  - Hover an icon for its tooltip: a dungeon's name and suggested levels (one icon for Blackrock
    Mountain's five and Dire Maul's three), a boat's or zeppelin's destinations (the other
    faction's are marked), a flight master's name. Clicks go through to the map.
  - Hover a zone on a continent map for its level range under its name, when the game shows none.
  - The gear: each kind on the world map and the minimap on its own, the zone levels, the icon size.
- **Low spell ranks** (Combat, on by default): tells you when a spell on your action bars, or one
  you cast, is a lower rank than one you know, and fixes the buttons in one click.
  - After combat, a list: "Earth Shock  Rank 1 > Rank 4 (2 buttons)", with **Keep** for a rank you
    use low on purpose (on all your accounts), **Later** and **Update all** (same place, same key).
  - It checks at login, after you learn a spell (once the trainer window closes) and after a
    dual-spec swap; `/gpearls ranks` any time. Spells in macros are listed, never edited.
  - The gear: when it checks, whether casts and macros are listed, and the kept ranks.
- **Sell junk & repair** (Loot & Bags, on by default): at a merchant, sells your junk, then
  repairs, guild funds first when your guild allows it.
  - Grey items with a price, and anything on your sell list (`/gpearls sell`, shift-click the
    item). Never your keep list (`/gpearls keep`), quest items, tools, equipment-set items or
    refundable purchases; not unbound grey gear or greys with a use unless you list them.
  - Cheapest first, one at a time, each checked just before it goes. Buyback-safe in the gear sells
    only what the buyback page can still hold. Hold Shift as you open the merchant to skip a visit.
  - Repair: guild funds first, then your money (like Blizzard's guild repair button), or your money
    only. A guild that says `[noautorepair]` is never charged.
- **Fixate alert** (Combat, on by default): a sound and an alert when a mob fixates on you, in any
  client language: it goes by spell ID, and the alert shows the spell's name in your game's
  language, its icon and a countdown. The game hides most aura details in combat, so the sound is
  played by the game itself when it allows it; `/gpearls fixate` tells what it allowed, and
  `/gpearls fixate test` shows the alert to place it.
- LibGlass r11 and LibAccountSync r5 embedded; HereBeDragons 2.18 and CallbackHandler-1.0 included.
