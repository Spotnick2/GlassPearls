# Glass Pearls

Small quality-of-life touches for **World of Warcraft: Forever**, each one a *pearl* you switch on
or off on its own. Part of the Glass family of addons.

> **Status:** in development for v0.1.0. Built ahead of Forever's launch (2026-11-04); nothing has
> been checked in game yet, so the first release waits for that.

## The pearls

Listed as the options window groups them. Most are on by default; the ones that act for you in ways
you might not expect stay off until you switch them on.

### Loot & Bags

**Bags full helper** (on by default). When loot doesn't fit, it offers to destroy the cheapest item
in your bags and loot in one click.
- It only shows when an item really doesn't fit: a partial stack or a matching herb or mining bag
  counts as room. After "Inventory is full" at a node or quest object, it helps you make room.
- It offers grey items (or grey and white, in its options), cheapest first by vendor value times
  stack. Quest items, tools, equipment-set items, consumables, containers, reagents, ammunition,
  recipes, keys and items with a use are never offered. White items need a second click.
- `<` `>` browse the suggestions; the X never suggests an item again, on all your characters and
  accounts; quest loot is picked first. When the loot is worth less than anything in your bags it
  says so, and "Choose anyway" is there.

**Easy delete** (off by default). When the game asks you to type DELETE to destroy a Rare or better
item, it is filled in and the item named in your chat, so one click on Yes confirms. Up to Epic by
default (a setting: Rare, Epic or Legendary); above it you still type it.

**Faster loot** (on by default). With auto loot on, everything that will fit in your bags is taken
the moment the loot window opens.
- Bind-on-pickup still asks you; a group's rolls and master loot, and anything that may not fit,
  are left to the game.
- When a corpse has only money, the amount floats up where you clicked (a setting).

**Quest loot sparkle** (off by default). Keeps the game's sparkle on lootable quest items by turning
the outline mode off, and again after a graphics preset puts it back. Switched off, your own outline
settings come back (the game may need a restart to show them).

**Sell junk & repair** (on by default). At a merchant, it sells your junk, then repairs, guild funds
first when your guild allows it.
- Grey items with a price, and anything you list with `/gpearls sell` (shift-click the item).
  Never what you list with `/gpearls keep`, quest items, tools, equipment-set items or refundable
  purchases; not unbound grey gear or greys with a use unless listed.
- Cheapest first, so the ones you can still buy back are the most valuable; buyback-safe in the
  gear sells only what the buyback page can hold. Hold Shift as you open the merchant to skip.

**Junk spotlight** (off by default). A coin on the bag items Sell junk & repair may sell at the next
merchant, and a tooltip line ("Eligible for automatic sale", with its value, or "Kept: on your keep
list"). By the seller's own rules and lists; nothing while the seller doesn't sell.

**Restock** (on by default). At a merchant, after junk is sold, tops up your food, water,
ammunition and class reagents with the best you can use, within a spending limit per visit. Only
what's at least as good counts toward a target, so you move up as you level. "Ask first" to confirm
each time; hold Shift to skip. Below the level cap it asks before buying food (or never buys it, or
buys it as the rest: a setting).

### Interface

**Map landmarks** (on by default). Dungeon and raid entrances, boats, zeppelins, the Deeprun Tram
and flight points on the world map (zone and continent) and the minimap.
- Hover an icon: a dungeon's name and suggested levels, a boat's or zeppelin's destinations (the
  other faction's are marked), a flight master's name. Clicks go through to the map.
- Hover a zone on a continent map to see its level range, when the game shows none.
- Its gear switches each kind on the world map and minimap, and sets the icon size.

**Library books** (on by default). WoW Forever's 40 library books on the world map (zone and
continent) and the minimap, at each place a book you still need can be found.
- Hover an icon for the book and where it is. Books you carry, keep in your bank or have handed in
  aren't shown; the other faction's two books neither.
- Within 100 yards of a book you still need, a note shows the book, where it is and how far, and
  stays until you click OK; a line in chat too. It comes again only after you've gone 150 yards
  away. No notes in instances, while dead or on a flight.
- The bank is read when you open it: open it once so the notes can start.
- Its gear switches the world map, the minimap and the notes. `/gpearls books` counts what's left
  and names the nearest.

### Combat

**Fixate alert** (on by default). A sound and an alert when a mob fixates on you, in any client
language: the alert shows the spell's name in your game's language, its icon and a countdown.

**Buff alerts** (on by default). An alert when Clearcasting, Innervate, Power Infusion or a
paladin's Blessing of Protection, Sacrifice or Freedom lands on you: its icon and name, who gave
it, and its time left. Each buff has its own switch and sound.

**Uncrushable** (on by default). A line at the bottom of the character panel's stats says whether a
boss three levels above you can crush you; its tooltip shows miss, dodge, parry and block against
it. Shown when you carry a shield.

**Paladin tank reminders** (on by default, paladins only). Out of combat, with a shield: a reminder
when Righteous Fury is off, a heads-up before it ends, and when Salvation is on you, with its time
left and who cast it.

**Low spell ranks** (on by default). When a spell on your action bars, or one you cast, is a lower
rank than one you know, it lists it after combat and updates the buttons in one click: all of them,
or one spell at a time from its row.
- It checks at login, after you learn a spell (once the trainer window closes), and after a
  dual-spec swap, where each spec's bars can still hold old ranks.
- Keep a rank you use low on purpose: it isn't listed again, on any of your accounts. Spells in
  macros are listed, never edited.
- The rank data comes from the game's own tables, by spell ID, on the model of
  [RankSentinel](https://www.curseforge.com/wow/addons/ranksentinel) (MIT).

**Training reminder** (on by default). When you level, a toast lists what your class trainer now
teaches you, what was already waiting, your talent points to spend and the cost. Spell tooltips say
when the next ranks come; with dual spec, your other spec's waiting talent ranks.

**Train all** (off by default). A Train all button on your class trainer's window learns every class
spell it offers, cheapest first, while your money lasts; its tooltip shows the count and the cost.
Only class spells: never riding, weapon skills, pet training or professions.

**Instance gear reminders** (on by default). Entering Scholomance or Stratholme without an Argent
Dawn trinket equipped (Scourgestones drop only while one is), below Exalted: a line in your chat and
a short text in the middle of the screen say "Equip your Argent Dawn Commission", or that it's in
your bank. Once per entry. "Also at Exalted" is a setting.

**Hunter pet care** (on by default, hunters only).
- **Feeding:** when your pet drops to Content (or, by a setting, only Unhappy), a line in your chat
  and a small window with a **Feed** button that feeds it the food chosen from your bags: the
  cheapest within 10 levels of your pet, else the highest level. "Never feed this" leaves a food
  out, on all your characters. Out of combat only.
- **What your pet eats:** a line in item tooltips (the default), a mark on your bag buttons, both,
  or neither.
- **Pet checks:** "Your pet is dead", "You have no pet out" or "Your pet is on Passive", at the
  start of a fight and at a ready check, or (a setting) out of combat when it disappears.

### Professions

**Easy fishing** (on by default). Never click the bobber.
- Bind "Fish, then reel in" (Key Bindings > Glass Pearls): press it to cast, press it again on the
  splash to reel in. While you fish, the game's own Interact Key is on and reaches the bobber.
- Optionally, while you fish: the splash louder (other sounds down, a volume setting) and NPC names
  hidden.
- Everything is put back when you stop; none of your own settings is saved or rewritten.

### Social

**Raid mark wheel** (on by default). A wheel of the eight raid marks at your cursor.
- Bind its key (Key Bindings > Glass Pearls), point at a unit (in the world, on its nameplate or on
  a group frame) and press it, or pick "Raid mark wheel" in a unit's right-click menu.
- Click a mark to set it (the same mark again removes it), the centre to clear it, outside or Esc to
  close. Out of combat; in a raid, as the leader or an assistant. Pings stay the game's own.

**Low-rank buffs** (on by default). When another player's Fortitude, Arcane Intellect, Mark of the
Wild, Thorns, Blessing, Divine Spirit or Shadow Protection lands on you at a lower rank than they
could cast, a chat line says so, once per person and buff a session.
- A lower rank on a lower-level player is the game's rule and never said; book ranks are never
  expected. Casters from level 60 by default (a setting).
- Optionally a polite whisper, only to your group, guild or friends.

**Trade summary** (off by default). After each completed trade, one line in your chat: "You gave 12g
to Name" or "You received 3g from Name" (or how your money changed, when both sides offered), and
the items each way. The last 10 are kept in its panel, on that character only.

**Invite from whispers** (off by default). When a Battle.net friend, a friend or a guild member
whispers you "inv" or "invite", you send them a group invite: a game whisper invites that character,
a Battle.net whisper the character they're playing here.
- Only when you're on your own, or lead the group (or assist in a raid), it has room and you're not in
  a battleground queue; it never turns a party into a raid. One request per person every 10 seconds.
- Optionally your Recent Allies too. Nothing is whispered back.

### Automation

**Auto gossip** (on by default). When an NPC has a single gossip option, it's picked for you (never
the hearthstone binding or the spirit healer, by default; a setting chooses).
- When you keep choosing the same option at an NPC, it offers to always pick it for you, on all
  your characters.
- Never in combat, with Shift held, or while the NPC has a quest for you; anything that costs money,
  binds your hearthstone or resets talents still asks you first.

**Social automation** (off by default). Answers Blizzard's popups for you, each with its own switch:
accepts a summon after 2 seconds (hold Shift to stay), a resurrection once you and your group are
out of combat, and a group invite from a friend, a guild mate or your group; optionally declines
duels from anyone you don't know. Never a group finder invite, a scenario summon or a resurrection
with sickness.

## Using it

- `/gpearls` opens the options window: each feature's checkbox, and a gear for its own options.
  Esc > Options > AddOns > Glass Pearls has a button to it too.
- `/gpearls <pearl> on/off` switches one; `/gpearls list` lists them.
- `/gpearls sync`: your settings follow you across your own WoW accounts on the same Battle.net
  account, automatically (Settings in the window turns it off).
- `/gpearls version`: the addon's version and the client build, for a bug report.
- `/gpearls help` for every command.

Each pearl's own command shows what it reads or did; `test` also shows its alert, toast or wheel so
you can place it:

| Pearl | Command |
|---|---|
| Bags full helper | `/gpearls cheapest`: the item it would suggest now |
| Easy delete | `/gpearls easydelete`: what it last filled in or skipped |
| Faster loot | `/gpearls fastloot`: its last pass, and what was left to the game |
| Quest loot sparkle | `/gpearls sparkle`; `sparkle restore` (while off) puts your settings back |
| Sell junk & repair | `/gpearls sell`: what would be sold; `sell <item>`, `keep <item>`, `forget <item>` manage the lists |
| Restock | `/gpearls restock`: at a merchant, what it would buy there and why not |
| Fixate alert | `/gpearls fixate`, `fixate test` |
| Buff alerts | `/gpearls buffs`, `buffs test` |
| Uncrushable | `/gpearls uncrushable`: whether you are uncrushable, and the numbers |
| Paladin tank reminders | `/gpearls paladintank`, `paladintank test` |
| Low spell ranks | `/gpearls ranks`: check your action bars now |
| Training reminder | `/gpearls training`, `training test` |
| Train all | `/gpearls trainall`: what it would learn at this trainer |
| Instance gear reminders | `/gpearls instancegear`, `instancegear test` |
| Hunter pet care | `/gpearls petcare`, `petcare test`; `never <item>`, `forget <item>` manage the list |
| Easy fishing | `/gpearls fishing`; `fishing reset` removes what it changed |
| Raid mark wheel | `/gpearls markwheel`, `markwheel test` |
| Low-rank buffs | `/gpearls lowbuffs`: what it said this session |
| Trade summary | `/gpearls trades`: the last trades on this character |
| Invite from whispers | `/gpearls whisperinvite`: the last requests and what was done |
| Auto gossip | `/gpearls gossip`: the NPC's options; `always <id>`, `forget <id>` |
| Social automation | `/gpearls social`: what it answered or left to you |

It wears WoW Forever's own look; with Glass UI installed, it follows Glass UI's glass.

## Built with

- [LibGlass-1.0](https://github.com/Spotnick2/LibGlass): the Glass suite's material.
- [LibAccountSync-1.0](https://github.com/Spotnick2/LibAccountSync): messages between your own
  accounts, with ownership proven before anything is sent or accepted.
- [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) (BSD) and CallbackHandler-1.0
  (BSD): the map pins.

All are embedded; nothing to install separately. The training reminder's trainer lists come from
[WhatsTraining](https://www.curseforge.com/wow/addons/whats-training) by Sveng (MIT): thanks.

## Licence

MIT.
