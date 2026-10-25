# Glass Pearls

Small quality-of-life touches for **World of Warcraft: Forever**, each one a *pearl* you switch on
or off on its own. Part of the Glass family of addons.

> **Status:** in development for v0.1.0. Built ahead of Forever's launch (2026-11-04); nothing has
> been checked in game yet, so the first release waits for that.

## The pearls

**Bags full helper** (Loot & Bags, on by default). When loot doesn't fit, it offers to destroy the
cheapest item in your bags and loot in one click.
- It only shows when an item really doesn't fit: a partial stack or a matching herb or mining bag
  counts as room. After "Inventory is full" at a node or quest object, it helps you make room.
- It offers grey items (or grey and white, in its options), cheapest first by vendor value times
  stack. Quest items, tools, equipment-set items, consumables, containers, reagents, ammunition,
  recipes, keys and items with a use are never offered. White items need a second click.
- `<` `>` browse the suggestions; the X never suggests an item again, on all your characters and
  accounts; quest loot is picked first. When the loot is worth less than anything in your bags it
  says so, and "Choose anyway" is there.

**Map landmarks** (Interface, on by default). Dungeon and raid entrances, boats, zeppelins, the
Deeprun Tram and flight points on the world map (zone and continent) and the minimap.
- Hover an icon: a dungeon's name and suggested levels, a boat's or zeppelin's destinations (the
  other faction's are marked), a flight master's name. Clicks go through to the map.
- Hover a zone on a continent map to see its level range, when the game shows none.
- Its gear switches each kind on the world map and minimap, and sets the icon size.

**Low spell ranks** (Combat, on by default). When a spell on your action bars, or one you cast,
is a lower rank than one you know, it lists it after combat and updates the buttons in one click.
- It checks at login, after you learn a spell (once the trainer window closes), and after a
  dual-spec swap, where each spec's bars can still hold old ranks.
- Keep a rank you use low on purpose: it isn't listed again, on any of your accounts. Spells in
  macros are listed, never edited.
- The rank data comes from the game's own tables, by spell ID, on the model of
  [RankSentinel](https://www.curseforge.com/wow/addons/ranksentinel) (MIT).

## Using it

- `/gpearls` opens the options window: each feature's checkbox, and a gear for its own options.
  Esc > Options > AddOns > Glass Pearls has a button to it too.
- `/gpearls <pearl> on/off` switches one; `/gpearls list` lists them.
- `/gpearls cheapest`: the item the bags full helper would suggest right now.
- `/gpearls ranks`: check your action bars for low spell ranks now.
- `/gpearls sync`: your settings follow you across your own WoW accounts on the same Battle.net
  account, automatically (Settings in the window turns it off).
- `/gpearls help` for the rest.

It wears WoW Forever's own look; with Glass UI installed, it follows Glass UI's glass.

## Built with

- [LibGlass-1.0](https://github.com/Spotnick2/LibGlass): the Glass suite's material.
- [LibAccountSync-1.0](https://github.com/Spotnick2/LibAccountSync): messages between your own
  accounts, with ownership proven before anything is sent or accepted.
- [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) (BSD) and CallbackHandler-1.0
  (BSD): the map pins.

All are embedded; nothing to install separately.

## Licence

MIT.
