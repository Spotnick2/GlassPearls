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
- **Uncrushable** (Combat, on by default): a line at the bottom of the character panel's stats
  says whether a boss three levels above you can crush you, with miss, dodge, parry and block
  against it in its tooltip (they must reach 100%: the usual 102.4% rule). Shown when you carry a
  shield, or always. `/gpearls uncrushable` prints it in chat.
- **Buff alerts** (Combat, on by default): an alert when Clearcasting, Innervate, Power Infusion
  or a paladin's Blessing of Protection, Sacrifice or Freedom lands on you, from yourself or another
  player: its icon, its name in your game's language, who gave it, and its time left ("~" when
  only estimated). Each buff has its own switch and sound (Clearcasting's sound off by default).
  `/gpearls buffs test` shows them to place them.
- **Paladin tank reminders** (Combat, on by default, paladins only): out of combat, with a shield, a
  reminder when Righteous Fury is off (and a heads-up a minute before it ends), and when Salvation
  is on you, with its time left and who cast it. In any client language. In combat, Blizzard's
  Cooldown Manager can alert when Righteous Fury drops.
- **Training reminder** (Combat, on by default): when you level, a toast lists the spells and ranks
  your class trainer now teaches you, what was already waiting, the talent points you have to
  spend (Talented's early ones included) and what it costs. Only what you can really learn. Spell
  tooltips say when the next ranks come. With dual spec, your other spec's waiting talent ranks.
  Trainer lists from WhatsTraining (thanks, Sveng).
- **Restock** (Loot & Bags, on by default): at a merchant, after selling junk and repairing, tops up
  your food, water (if you use mana), arrows or bullets (hunters) and class reagents, with the best
  the merchant has that you can use. Only what's at least as good counts toward a target, so you
  move up as you level. At most half your money and 5 gold a visit (both settings); "Ask first" to
  confirm each time; Shift skips it. Leaves to Buffy the reagents Buffy restocks.
- **Raid mark wheel** (Social, on by default): a wheel of the eight raid marks at your cursor. Bind
  its key in Key Bindings > Glass Pearls, point at a unit (in the world, on its nameplate or on a
  group frame) and press it, or pick "Raid mark wheel" in a unit's right-click menu. Click a mark to
  set it (the same mark again removes it), the centre to clear it, outside or Esc to close. Out of
  combat; in a raid, as the leader or an assistant. It opens and closes with a short animation, in
  WoW Forever's own wheel art or Glass UI's glass. Pings are the game's own: its Ping key.
- **Auto gossip** (Automation, on by default): when an NPC has a single gossip option, it's picked for
  you (never the hearthstone binding or the spirit healer, by default; a setting chooses). When you
  keep choosing the same option at an NPC, it offers to always pick it for you, on all your
  characters. Never in combat, with Shift held, or while the NPC has a quest for you; anything
  that costs money, binds your hearthstone or resets talents still asks you first. `/gpearls
  gossip` shows the NPC's options.
- **Faster loot** (Loot & Bags, on by default): with auto loot on, everything that will fit in your
  bags is taken the moment the loot window opens. Bind-on-pickup still asks you; a group's rolls and
  master loot, and anything that may not fit, are left to the game. When a corpse has only money,
  the amount floats up where you clicked (a setting). `/gpearls fastloot` shows the last pass.
- **Low-rank buffs** (Social, on by default): when another player's Fortitude, Arcane Intellect,
  Mark of the Wild, Thorns, Blessing, Divine Spirit or Shadow Protection lands on you at a lower
  rank than they could cast, a chat line says so, once per person and buff a session. A lower rank
  on a lower-level player is the game's rule and never said, and book ranks are never expected.
  Casters from level 60 by default (a setting). Optionally a polite whisper, only to your group,
  guild or friends. `/gpearls lowbuffs` shows what was said.
- **Instance gear reminders** (Combat, on by default): entering Scholomance or Stratholme without
  an Argent Dawn trinket equipped (Scourgestones drop only while one is), below Exalted, a line in
  your chat and a short text in the middle of the screen say "Equip your Argent Dawn Commission",
  or that it's in your bank. Once per entry, not after a `/reload` inside. "Also at Exalted" is a
  setting. `/gpearls instancegear` shows what it reads.
- LibGlass r11 and LibAccountSync r5 embedded; HereBeDragons 2.18 and CallbackHandler-1.0 included.
