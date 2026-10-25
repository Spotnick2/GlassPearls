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
- LibGlass r11 and LibAccountSync r5 embedded.
