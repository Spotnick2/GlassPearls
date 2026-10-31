# Glass Pearls: plan

## M0: scaffold (done, 2026-10-25)

Repo, TOC, `.pkgmeta` with LibGlass r11 and LibAccountSync r5 pinned, CI (tests at the pins,
packager dry run, exact zip contents, GitHub Release and Wago upload on a tag), deploy script, the
pearl registry, `/gpearls`, the own-account link. Release setup in #1/#2 (CurseForge 1764704,
Wago `kGr9LxKy`).

## M1: the bags-full helper and the foundations it needs (v0.1.0)

Reviewed adversarially with Codex before coding (7 rounds, consensus on 2026-10-25). Built blind:
the client is unavailable until 2026-11-04, so every client claim is checked against the 70532 API
dump and `wow-ui-source`, covered by unit tests, and listed below for day one. **No v0.1.0 tag
until PearlsProbe's steps 1-3 pass** and the code is adjusted to what they show.

| Issue | What | State |
|---|---|---|
| #3 | The options window (Leatrix Plus's layout) and the look: WoW Forever by default, Glass UI's when present | done |
| #4 | Settings follow you across your accounts (automatic, per-key last-writer-wins) | done |
| #5 | PearlsProbe: what the client must confirm on day one | next (built after #6, owner 2026-10-25) |
| #6 | Bags full helper (pearl `bagsfull`) | built; its action waits for the probe |
| #10 | Map landmarks (pearl `landmarks`): entrances, boats, zeppelins, the tram, flight points, zone levels | built; its positions and icons wait for day one |
| #12 | Low spell ranks (pearl `spellranks`): the bar scan, the cast warning, Update all | built; the update path waits for day one |
| #15 | Sell junk & repair (pearl `junk`), guild funds first | built; selling and guild repair wait for day one |
| #17 | Fixate alert (pearl `fixate`), any client language | built; both paths wait for day one |
| #19 | Uncrushable (pearl `uncrushable`): the character panel line and `/gpearls uncrushable` | built; the numbers and placement wait for day one |
| #21 | Buff alerts (pearl `buffs`): Clearcasting, Innervate, Power Infusion, the Blessings, with time left | built; the overlay and combat paths wait for day one |
| #22 | Paladin tank reminders (pearl `paladintank`): Righteous Fury off, Salvation on you | built; the IDs and the Cooldown Manager wait for day one |
| #27 | Training reminder (pearl `training`): a level-up toast, next ranks in spell tooltips, talent points, the other spec | built; the trainer match, the tooltip and dual spec wait for day one |
| #14 | Restock (pearl `restock`): food, water, ammunition and class reagents at a merchant, after the junk seller | built; the purchase API, the events and the refusal names wait for day one |
| #34 | Raid mark wheel (pearl `markwheel`): the eight marks at the cursor, from a key or a unit's menu; pings stay the client's own | built; the secure click, the menu entry and the art wait for day one |
| #47 | Auto gossip (pearl `autogossip`): lone options by a setting, and the options you keep choosing; gossip only | built; the icons, the event order, the button hook and the picks wait for day one |
| #36 | Faster loot (pearl `fastloot`): every slot that safely fits, as the loot window opens; the coins-only text | built; the race with the client's auto loot, the events and the loot methods wait for day one |
| #42 | Low-rank buffs (pearl `lowbuffs`): a single-target buff on you at a lower rank than its caster could cast; the opt-in whisper to people you know | built; the source units, the downrank rule and the whisper wait for day one |
| #43 | Instance gear reminders (pearl `instancegear`): the Argent Dawn trinket in Scholomance and Stratholme | built; the instance and standing reads, the bank count and the event order wait for day one |
| #38 | Hunter pet care (pearl `petcare`): the feeding reminder and Feed button, what the pet eats, the missing, dead or Passive checks | built; the Feed button, the bag marks, the Passive read and the level band wait for day one |
| #41 | Junk spotlight (pearl `junkspot`, off by default): what the junk seller may sell, marked in the bags and tooltips | built; the marks beside pet care's and the tooltip owner wait for day one |
| GlassUI#163 | Glass UI lists Glass Pearls as a dynamic member | Glass UI's session |

## Waiting for the client (day one: 2026-11-04)

Each line is a claim the code relies on that only the live client can settle.

**The scaffold and the window (#3)**
- [ ] Loads clean (`/console scriptErrors 1`, `/reload`, `/gpearls failures` says none).
- [ ] `/gpearls` opens the window; Esc closes it; it drags; it opens in combat.
- [ ] The Forever look: `DialogBorderDarkTemplate` renders as Blizzard's dark dialog (screenshot).
- [ ] The search box (`SearchBoxTemplate`) shows "Search options" and its clear button.
- [ ] The gear texture (`Interface\WorldMap\GEAR_64GREY`) shows beside a pearl with options.
- [ ] **Reload: `ReloadUI()` from the button's own click reloads, or raises
      `ADDON_ACTION_FORBIDDEN`** (the porting guide calls it protected; Leatrix Plus's Forever build
      calls it from a click). If refused, the button gives way to "Type /reload" (built, tested).
- [ ] With Glass UI (after GlassUI#163): glass windows, `/glassui suite` lists Glass Pearls as
      following; unticking "Use Glass UI appearance" + reload gives the Forever look, listed as declined.
- [ ] The Esc > Options > AddOns page shows on its first visit and its button opens the window.
- [ ] `GlassPearlsDB`, `GlassPearlsCharDB`, `GlassPearlsSyncDB` are written after a full client exit.
- [ ] The client build is still 1.60.1.70532; if not, a new dump (`forever-api-dump` skill).

**Settings sync (#4)** (needs two of your accounts online on the same Battle.net account)
- [ ] `/gpearls sync` on both: the link sees the other account ("Battle.net: usable", a trusted peer).
- [ ] Switch a pearl or change a setting on one: it changes on the other within a few seconds,
      and `/gpearls sync` there says "last received … from <name>, 1 applied".
- [ ] Log the second account in after a change made while it was away: it catches up at login.
- [ ] Change different settings on both while one is offline, bring it back: both keep both changes.
- [ ] Sharing off on one (Settings): nothing is sent or applied either way.
- [ ] A near-full snapshot (a long keep list, #6) sends without a hitch (hashing ~130 ms, LibAccountSync README).

**The bags-full helper (#6)** (fill your bags with a few grey and white items first)
- [ ] **`DeleteCursorItem` from the window's button deletes the grey item** (one click), or
      `ADDON_ACTION_FORBIDDEN` names it: then "by hand" mode must show and the item stay in the bag.
      The reference addons call it from their own clicks; probe step 1 measures it first.
- [ ] **The loot follows** (`LootSlot` after `BAG_UPDATE_DELAYED`): the ring lands in the freed slot.
      If refused, the loot window stays and the player clicks the row (change it to "highlight the row").
- [ ] The full-bags error names (`GetGameMessageInfo`) for a corpse, a herb or ore node, a quest
      object and a quest reward; add them to `BF.FULL_ERRORS` (only `ERR_INV_FULL` is in so far).
- [ ] Loot that fits on a partial stack or in a herb / mining bag: no prompt.
- [ ] A white item: the first click says "Click again to destroy", the second destroys.
- [ ] The window sits right of the loot window; dragged, it stays where it was put after a /reload.
- [ ] Tooltips on both cards (Blizzard's bag and loot tooltips).
- [ ] The X: the item isn't offered again, on another character, and after a sync on another account.
- [ ] Auto-loot on: the helper still shows for the rows that didn't fit.
- [ ] Combat: it hides and comes back after.

**Map landmarks (#10)** (`Tools\landmarks\report.txt` lists each position's source and confidence)
- [ ] HereBeDragons-Pins loads from our copy (no Lua error; `/gpearls failures` names no `pearl landmarks`).
- [ ] **The icons sit where they belong** on the zone and the continent maps, and the minimap: walk
      or fly past a few "hand" entrances first (Blackrock Mountain, Dire Maul, Zul'Gurub, Onyxia's
      Lair, the four new Forever dungeons) and a few "client" ones; correct `entrances.csv` and
      regenerate. A swapped axis would put everything mirrored across the zone: check one first.
- [ ] Docks: Menethil, Auberdine's three piers, Ratchet, Booty Bay, the zeppelin towers, the
      Deeprun Tram ends, Stormwind Harbor, Tanaris and the Riverglades.
- [ ] The icons: which of the atlases (`Dungeon`, `Raid`, `TransportShip`, `TransportZeppelin`,
      `TransportTram`, `TaxiNode_Neutral`) the client has, and how the file fallback looks (screenshot).
- [ ] Tooltips: names (localized from `GetLFGDungeonInfo` when it gives them), level colours like
      Blizzard's zone label, "(Horde only)" on the other faction's zeppelins, the destinations.
- [ ] Clicks pass through to the map (zoom out with a right-click on an icon still works);
      NodeRadar's waypoints untouched.
- [ ] **Flight points away from a flight master:** does `C_TaxiMap.GetTaxiNodesForMap` answer
      in the open world? Where `ShouldMapShowTaxiNodes` is true, Blizzard's own pins must show and
      ours not (no doubles). Undiscovered ones greyed; `TAXI_NODE_STATUS_CHANGED` after learning one.
- [ ] **The zone level line:** hover a zone on the Kalimdor and Eastern Kingdoms maps: its range
      just under Blizzard's name (or its description line), only when Blizzard shows none
      (`C_Map.GetMapLevels`). Check where the
      area label provider's `Label` really is (`WorldMapFrame.dataProviders`).
- [ ] Switching it off in the window removes every pin at once; on again brings them back.

**Low spell ranks (#12)** (a shaman or any class with ranked spells; a second spec for the swap)
- [ ] **Does learning a rank update the active bars by itself?** And does it leave the other
      spec's bars on the old rank (the owner's case)? Learn a rank, look at both specs' bars.
- [ ] **Update all**: `PlaceAction` from our button's click places the rank, without
      `ADDON_ACTION_FORBIDDEN` (`/gpearls failures`), and the old rank lands on the cursor and is
      cleared. If refused, the popup's "by hand" line must show and nothing change.
- [ ] `C_Spell.PickupSpell(rank1)` picks up exactly rank 1 (not upgraded by the client).
- [ ] `GetActionInfo` gives each rank's own ID; `IsSpellKnown` is true for a lower rank once a
      higher one is learned; `GetOverrideSpell` on a talent-modified spell.
- [ ] The pages: the stance and form bars (warrior, druid) are scanned and labelled; nothing on a
      vehicle or possess bar is ever listed; the slot ceiling (180) holds.
- [ ] `GetMacroSpell` for a `#showtooltip` macro: the macro row appears.
- [ ] The cast warning: `UNIT_SPELLCAST_SUCCEEDED`'s spell ID in combat (plain or secret); casts
      from a key, a macro, an item, a proc, a triggered or channelled spell. Any that fire on
      their own go on a suppression list.
- [ ] The spec swap: `ACTIVE_TALENT_GROUP_CHANGED` and the bars' reload timing (is the second
      pass at 6 s enough?).
- [ ] A class trainer holds the check until its window closes; a profession trainer doesn't.
- [ ] The popup in both looks (screenshot); Keep survives a sync to the other account.

**Sell junk & repair (#15)** (bags with greys, a listed white, a refundable purchase; a guild with repair rights)
- [ ] **Selling from a timer at a merchant**: `C_Container.UseContainerItem` from our `MERCHANT_SHOW`
      timer sells, no `ADDON_ACTION_FORBIDDEN` (`/gpearls failures`). One sale at a time: fast
      enough? Does the slot read empty by `BAG_UPDATE_DELAYED` (the confirmation), and within 1 s?
- [ ] The refusal names: a merchant that doesn't buy (`ERR_VENDOR_DOESNT_BUY`?) and the gold cap
      (`ERR_TOO_MUCH_GOLD`?), through `GetGameMessageInfo`.
- [ ] Not sold: unbound grey gear, a grey with a use, a refundable purchase (`C_Item.CanBeRefunded`),
      a quest item, the Hearthstone. Items that report a price and can't be sold: add them to
      `J.UNSELLABLE`.
- [ ] Buyback-safe with 10 already on the page: two sold, the cheapest; all recoverable after.
- [ ] Blizzard's own Sell All Junk button is on the merchant window (Mainline frame) and ours
      doesn't fight it.
- [ ] **Guild repair**: with the allowance covering it ("Repaired with guild funds."); with it short
      (does `RepairAllItems(true)` take the rest from you, or repair nothing?); what
      `GetGuildBankWithdrawMoney` / `GetGuildBankMoney` read before the bank is opened.
- [ ] `UPDATE_INVENTORY_DURABILITY` after a repair, and the cost read again (the settle rule).
- [ ] Shift held as the merchant opens skips both; the money lines match what the money did.

**Fixate alert (#17)** (somewhere a mob fixates: find one; `/gpearls fixate` before and after)
- [ ] **`AddAuraSound` from addon code**: `/gpearls fixate` says "the client plays it" for the four
      spells (an ID back), and the raid-warning sound (file 567397) **plays in combat** when a
      fixate lands. Refused: the status says so and the alert plays Glass Pearls' own sound.
- [ ] `ShouldSpellAuraBeSecret` for the four, in and out of combat (`/gpearls fixate` shows it);
      `GetPlayerAuraBySpellID` in combat: present, or unknown?
- [ ] For each fixate met: the aura's actual ID on the player (add any other to `F.SPELLS`), its
      caster (`GetAuraCasterGUID` when readable), and the mob's threat and target values
      alongside (to judge a targeting fallback later).
- [ ] On a non-English client (or with the game's language switched): the alert's headline is the
      local spell name.
- [ ] The alert in both looks (screenshot); `/gpearls fixate test` drags and remembers.

**Uncrushable (#19)** (a warrior or paladin with a shield; ideally a known uncrushable set)
- [ ] `UnitDefenseSkill`, `GetDodgeChance`, `GetParryChance`, `GetBlockChance` match the
      character sheet; the line's total matches a hand calculation (miss + dodge + parry + block
      against a +3 boss); a known uncrushable tank reads Uncrushable.
- [ ] Are stats secret in combat (`C_Secrets.ShouldUnitStatsBeSecret`)? The line says "stats
      unavailable in combat" then, never a number.
- [ ] The line in the stats pane's footer (screenshot, both looks): readable, not over the
      scroll bar, hidden on the pet pane; its tooltip.
- [ ] What `C_SpecializationInfo.GetSpecialization()` / `GetSpecializationRoleEnum` return (for a
      tank-spec option later).

**Buff alerts (#21)** (a druid, mage or shaman for Clearcasting; a friend to Innervate, Power Infusion and Bless you)
- [ ] `/gpearls buffs` per ID: the aura's secrecy in and out of combat, whether
      `IsSpellOverlayed` answers, and the client's sound registered or refused.
- [ ] **Blizzard's proc overlay**: does `SPELL_ACTIVATION_OVERLAY_SHOW` / `_HIDE` fire for
      Clearcasting (and the others), with a plain spell ID, and is it the aura's ID? Its timing
      against the proc being consumed.
- [ ] A buff from another player: "from <name>"; self-cast: none. The times: exact when read,
      `~` when overlay-only, matching the buff.
- [ ] Which ID an item or set proc gives (Wit's End, the T2 / Scarlet Enclave sets).
- [ ] `AddAuraSound` for a helpful aura plays (in combat too).
- [ ] The buff row and the fixate alert together on screen (screenshot), both looks.
- [ ] **Blizzard's Cooldown Manager** (Edit Mode): what it tracks of these for your class, and
      whether it makes some entries redundant (the owner hasn't used it before: adjust as we go).

**Paladin tank reminders (#22)** (a paladin with a shield; another paladin to cast Salvation)
- [ ] The IDs a paladin really has: Righteous Fury 25780 or the rune 407627; Salvation 1038, Mass
      Salvation 25895 (`/gpearls paladintank` shows the last reads).
- [ ] Out of combat: "is off" when Fury is off, gone when it's on; "ends in" under a minute (does
      Fury have a duration here?); Salvation's time left and its caster.
- [ ] Hidden in combat, back after; after a death it waits for a proven read.
- [ ] **The Cooldown Manager** (Edit Mode): Righteous Fury and Salvation tracked, an On Aura Removed
      alert for Fury that fires in combat. Adjust the pearl's pointer to what it really offers.
- [ ] Placement with the other alerts (screenshot), both looks.

**Training reminder (#27)** (any class, a few levels from the next trainer spells)
- [ ] Level up: the toast's new and waiting spells match the class trainer's list; learning one at
      the trainer takes it off the open toast.
- [ ] Spell tooltips in the spellbook (and on the action bars): the next ranks and their levels.
- [ ] Talent points: the count is right (`C_Traits` tree currency), also at levels 5-9 with the
      Legacy talent Talented (1225474: talent points from level 5 instead of 10; learned at the
      class trainer or in the talent tree, owner 2026-10-29): a level-up toast at 5-9 shows them.
- [ ] Dual spec (Forever has it, owner 2026-10-29; the measurement at 70245 found one spec
      group): the other spec's waiting talent ranks, as last seen, and are ranks
      learned in one spec known in the other?
- [ ] Righteous Fury: WhatsTraining says trainer level 10, the client's SpellLevels 16. Which?
- [ ] Placement (screenshot), both looks.

**Restock (#14)** (a mage and a hunter, a food and drink vendor, a reagent vendor, a bowyer)
- [ ] `BuyMerchantItem(index, n)`: is `n` in items (Blizzard's "buy multiple" says so)? A pack item
      (vials, 5 per pack) bought 10 at a time? A request above `GetMerchantItemMaxStack`?
- [ ] After a purchase: `BAG_UPDATE_DELAYED` arrives, and the count is complete by then (within 2 s).
- [ ] The refusal names through `GetGameMessageInfo`: not enough money, bags full, sold out (a
      limited-stock item), and whether `ERR_ITEM_MAX_COUNT` exists.
- [ ] Forever loads Mainline's merchant frame (`C_MerchantFrame.GetItemInfo`); `MERCHANT_HIGH_PRICE_COST`.
- [ ] Ammo: equipped arrows stay in the quiver (the ammo slot points at them), so the bag count covers it.
- [ ] The junk seller then restock in one visit: the order, the money line of each.
- [ ] Value order in game (water, bread); the Manna Biscuit counting as both; the defaults and limits feel right.
- [ ] Buffy installed: its reagents left to it while its restock is on, bought when off.
- [ ] Ask first: the window beside the merchant (screenshot), both looks.

**Raid mark wheel (#34)** (solo, then a party, then a raid as a member and as an assistant)
- [ ] The key (Key Bindings > Glass Pearls) opens the wheel over a mob in the world, a player, yourself
      and a party frame; with nameplates on and with them off (off: a mob not targeted is refused,
      "target it or show its nameplate").
- [ ] Are an NPC's GUIDs secret out of combat? (Decides whether the GUID check helps for mobs; the
      epoch covers them either way.)
- [ ] A click on a mark marks the unit (Blizzard's `raidtarget` action), the same mark again removes
      it, the centre clears it, outside or Esc closes. No `ADDON_ACTION_FORBIDDEN`. Exactly one
      action per click, with `ActionButtonUseKeyDown` on and off.
- [ ] The menu entry shows on yourself, your target, focus, party and raid members and pets, not on
      an enemy player; it opens the wheel where the menu was, and the click that chose it marks
      nothing. **Blizzard's own Raid Target Icon and Set Focus entries still work** (no taint).
- [ ] The art: `gamepad-radial-menu-wheelbg`, `-selected`, `-bottomtext` and `Radial_Wheel_Icon_Close`
      exist; the highlight lines up with the segments and the icons (screenshot); `RAID_TARGET_1..8`
      exist (the label's names).
- [ ] The animations: open and close are smooth, centred on the cursor, in both looks.
- [ ] Combat: pulling with the wheel open closes it; the key in combat says why. In a raid as a
      plain member: refused; as an assistant: allowed.
- [ ] Blizzard's Ping key: bound by default? (The panel's note.)

**Auto gossip (#47)** (a vendor, an innkeeper, a flight master, a class trainer, a spirit healer, a
story NPC, a multi-page NPC)
- [ ] `/gpearls gossip` at each: the icons' fileIDs (the binder 132052/136458 and healer 132054
      refusals; the `services` icons and the four `Interface\GossipFrame\*GossipIcon` paths it
      resolves), `gossipOptionID` present or hidden, `selectOptionWhenOnlyOption` where.
- [ ] `/gpearls gossip trace`: the order of show, refresh, selects, confirmations,
      `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (its type) and closes (`interactionIsContinuing`), in
      particular at a binder, a talent master and a spirit healer against their confirmations; does
      Blizzard's lone pick come before our decision a frame later?
- [ ] A pick works from our handler (`SelectOption(id)`): no taint, no `ADDON_ACTION_FORBIDDEN`. A
      paid option still shows Blizzard's popup; binding and talent wipe are never answered by us.
- [ ] The PreClick hook: on the real gossip buttons (scrolled ones too), fired by a mouse click and
      by the gamepad; Blizzard's lone pick and a popup's Accept or Enter never count.
- [ ] The offer after the third pick, in both looks; never in combat; Always then picks it.
- [ ] Enter in a code popup, an innkeeper you're already bound at, a spirit healer alive and dead,
      a paid always option, a trainer's unlearn option, one option ID at two NPCs.
- [ ] A multi-page NPC stops after 3 automatic picks; quickly talking again after an ambiguous close.

**Faster loot (#36)** (solo, then a group with each loot method; a corpse with coins only)
- [ ] `LootSlot` from our handler: no `ADDON_ACTION_BLOCKED` or forbidden. Is it faster than the
      client's own auto loot, and does the race leave anything behind or raise errors?
- [ ] A trace: `LOOT_READY` / `LOOT_OPENED` / `LOOT_CLOSED` order and payloads (plain booleans? the
      auto-loot key gives `false`?), slot counts at each, lock states, clear events, bag updates;
      does `LOOT_READY` repeat for one corpse?
- [ ] On versus off, comparing final bags and the loot left: one free slot and two items (one a
      quest item); several rows of one stackable item and a partial stack; a matching specialty bag.
- [ ] Bind on pickup (several rows): the prompt as usual, never answered by us; accept, cancel,
      Escape with ordinary loot beside it.
- [ ] Every loot method: free-for-all, round-robin, group, need before greed, master, and an item
      left after everyone passes.
- [ ] Full bags: no "Inventory is full" spam from us, and the bags-full helper's destroy works beside it.
- [ ] Money, currency, fishing, containers from bags, skinning, mining and herbs; the gamepad's loot
      all; closing and reopening with loot outstanding; server throttling with no gaps.
- [ ] The coin text: the right amount at the corpse, rising and fading; `PLAYER_MONEY` and
      `CHAT_MSG_MONEY` within 2 s with the window closed, solo and for a group share.

**Low-rank buffs (#42)** (a level-60 priest, mage, druid and paladin on alts of 37, 38, 50 and 60)
- [ ] `sourceUnit` on a buff from a party member, a raid member, a targeted stranger, a stranger
      with only a nameplate, and a stranger with no token (unattributed: nothing said).
- [ ] The caster's `UnitGUID`, `UnitLevel`, `UnitClass`, `UnitIsPlayer` and `GetUnitName(unit, false)`
      plain out of combat; the name is the first name and surname.
- [ ] The downrank rule: a 60's Fortitude lands at rank 4 on a 37 and rank 5 on a 38, and nothing
      is said; a lower rank cast on a 60 is said once, and a recast says nothing more.
- [ ] The trainer ranks of Fortitude and the Blessings need no book on Forever.
- [ ] Buffs gained in combat are never judged after it; no read in combat.
- [ ] The whisper (opt-in): delivered to a party member by the `GetUnitName` form; refused in an
      instance; `InChatMessagingLockdown` and the chat restriction state in the open world; no
      taint, no forbidden action.

**Instance gear reminders (#43)** (a character below Exalted with the Argent Dawn and the Commission)
- [ ] `GetInstanceInfo()` in Scholomance and both sides of Stratholme: `instanceType` and
      `instanceID` (289 / 329), plain.
- [ ] `GetFactionDataByID(529).reaction`, plain, on a character who has met the Argent Dawn and one
      who hasn't.
- [ ] `GetInventoryItemID` on slots 13 and 14 with the Commission worn: nothing said.
- [ ] `GetItemCount(12846, true)` away from the bank with the Commission banked: counted after a
      full client exit and a fresh login? After a bank visit?
- [ ] The `PLAYER_ENTERING_WORLD` / `PLAYER_LEAVING_WORLD` order and payloads at login, a reload, an
      ordinary entry, a corpse return, a summon into the instance, a logout to character select, a
      disconnect and relogin.
- [ ] The reminder 5 s after the loading screen, once; none after a `/reload` inside.
- [ ] The centre text: its first show in combat, beside the fixate alert, the buff alerts and a moved
      raid warning frame.

**Hunter pet care (#38)** (a hunter with a pet; food in and out of its diet)
- [ ] `C_PetInfo.GetPetHappiness` and `HasPetUI` as happiness falls, plain; `UNIT_HAPPINESS`'s timing
      and payload.
- [ ] `CanPetEatItem` on foods in and out of the pet's diet, plain; the tooltip line.
- [ ] The Feed button: casts Feed Pet and feeds the chosen bag slot through `target-bag` /
      `target-slot` (does Feed Pet enter item targeting at once on this build?); no
      `ADDON_ACTION_BLOCKED`; the happiness rises. A failed cast; repeated clicks while feeding.
- [ ] The level band: food 10, 20 and 30+ levels below the pet: accepted? Happiness gained?
- [ ] The bag marks on Blizzard's bags, separate and combined; the `UI-PetHappiness` atlas. No taint:
      open the bags in combat after the hooks ran, and use an item from them in combat.
- [ ] `GetPetActionInfo`: the Passive token slot, `PET_PASSIVE_TEXTURE`, its `isActive`; readable
      inside `PLAYER_REGEN_DISABLED` and at a `READY_CHECK` in combat?
- [ ] The pet unit when dead: does `UnitExists("pet")` stay true with `UnitIsDead`? Does `UNIT_FLAGS`
      fire on its death? After a taxi, a loading screen and a resurrection: the 10 s check.
- [ ] "Away" stays quiet mounted, feigning death, under Eyes of the Beast and at the stable master;
      it warns once after Dismiss Pet.
- [ ] The window hidden as a fight starts; nothing refused (`ADDON_ACTION_BLOCKED`) with the Feed
      button its child.
- [ ] Taint checks: mind the measured `taintLog` bug (porting guide); compare with logging off and
      finish with it off.

**Junk spotlight (#41)** (greys, a listed white, a kept item, a quest item in the bags)
- [ ] The coins on Blizzard's bags, separate and combined, beside pet care's marks (a hunter); the
      `Coin-Gold` atlas; no taint (open the bags in combat after the hooks ran).
- [ ] The tooltip line on a bag item: `GameTooltip:GetOwner()` is the bag button and its `GetBagID` /
      `GetID` read; none on a merchant's, a link's or a comparison tooltip.
- [ ] A lock (picking an item up) hides its coin and putting it back restores it (`ITEM_LOCK_CHANGED`).

**The probe (#5):** its steps are added here by its PR.

## Candidate pearls after M1

Owner to fill in. For each: what it does, the client API it relies on (in the newest dump, and
measured with a ForeverProbe module where the dump can't say), its default, and whether it can
switch off live or needs a `/reload`.
