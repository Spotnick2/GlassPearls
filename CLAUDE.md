# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassPearls is a **quality-of-life addon for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and
conventions as the sibling Forever addons: `..\GlassChat` (the template for this repo's tooling,
tests and CI, and the pilot consumer of LibAccountSync) and `..\GlassMail` (the closest in size and
shape). When this file doesn't cover something, check how those handle it before you invent a new
idiom.

**Goal:** many small quality-of-life touches in one addon, each one a **pearl**: a small,
independent feature the player switches on or off on its own. It wears WoW Forever's own look by
default and Glass UI's glass when Glass UI is installed (owner). The milestones, the plan and the
day-one checklist are [docs/PLAN.md](docs/PLAN.md).

**Status: M1 in progress** (docs/PLAN.md): the options window and the look (#3) and settings sync
(#4) and the first pearl, the bags-full helper (#6), are built, the second, map landmarks (#10), and the
third, low spell ranks (#12), the fourth, junk selling and repair (#15), the fifth, the fixate alert (#17), and the sixth,
uncrushable (#19), the seventh, buff alerts (#21), the eighth, the paladin tank reminders (#22), the ninth, the training reminder (#27), the tenth, restock (#14), the eleventh, the raid mark wheel (#34), the twelfth, auto gossip (#47), the thirteenth, faster loot (#36), the fourteenth, low-rank buffs (#42), the fifteenth, instance gear reminders (#43), and the sixteenth, hunter pet care (#38); the day-one
probe (#5) follows. Nothing
has been measured in game for this addon: the client is unavailable until 2026-11-04, so every
client claim is on the day-one checklist in docs/PLAN.md.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Libs\LibAccountSync-1.0\LibAccountSync-1.0.xml`
→ `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua` → `Libs\HereBeDragons-2.0\HereBeDragons-2.0.lua` →
`Libs\HereBeDragons-2.0\HereBeDragons-Pins-2.0.lua` → `Compat.lua` → `Theme.lua` → `UI.lua` →
`AccountSync.lua` → `Pearls.lua` → `SettingsSync.lua` → `Core\ToolItems.lua` → `Core\Bags.lua` →
`Core\Merchant.lua` → `Core\AuraAlert.lua` → `Core\Notice.lua` →
`Data\Landmarks.lua` → `Data\SpellRanks.lua` → `Data\AuraDurations.lua` → `Data\Training.lua` → `Data\Restock.lua` → *(pearl files: `Pearls\BagsFullFrame.lua` →
`Pearls\BagsFull.lua` → `Pearls\Landmarks.lua` → `Pearls\SpellRanksFrame.lua` →
`Pearls\SpellRanks.lua` → `Pearls\JunkFrame.lua` → `Pearls\Junk.lua` → `Pearls\FixateFrame.lua` →
`Pearls\Fixate.lua` → `Pearls\Uncrushable.lua` → `Pearls\BuffsFrame.lua` → `Pearls\Buffs.lua` → `Pearls\PaladinTank.lua` → `Pearls\TrainingFrame.lua` →
`Pearls\Training.lua` → `Pearls\RestockFrame.lua` → `Pearls\Restock.lua` → `Pearls\MarkWheelFrame.lua` →
`Pearls\MarkWheel.lua` → `Pearls\AutoGossipFrame.lua` → `Pearls\AutoGossip.lua` → `Pearls\FastLootFrame.lua` →
`Pearls\FastLoot.lua` → `Pearls\LowBuffs.lua` → `Pearls\InstanceGearFrame.lua` → `Pearls\InstanceGear.lua` →
`Pearls\PetCareFrame.lua` → `Pearls\PetCare.lua`)* →
`Options.lua` → `GlassPearls.lua`. Pearls load after
everything they may use (they register sets with settings sync at file scope; test_toc checks the
order) and before the options window and bootstrap.

- **`Libs\`**: two kinds. **Externals** (LibGlass-1.0, LibAccountSync-1.0): `.pkgmeta` pins,
  gitignored, never committed. **Vendored** (HereBeDragons-2.0 + Pins 2.18-release, CallbackHandler-1.0
  minor 8): committed **unmodified** with their notices, for the map landmarks' pins. Update one only
  by copying the new release over it whole (`References\Addons\Libraries\HereBeDragons`); test_toc
  checks the versions, the notices and that nothing is both.
- **`Compat.lua`**: `GlassPearls.API`, the only route to client APIs that moved or may be absent:
  `IsSecret`, `RegisterEvents` (reports failures), `NoteCombat` / `InCombat`, `Fail(key, err)` (the
  **one** failure recorder, read by `/gpearls failures`), `AddOnVersion`, `ClientBuild`,
  `SafeFrame` (a template and whether it applied, read raw); `MEASURED_ON_BUILD`. A subset of
  GlassMail's; lift more from there when a pearl needs it.
- **`Theme.lua`**: the look, fixed once at `ADDON_LOADED`. **WoW Forever by default**
  (`DialogBorderDarkTemplate`, Blizzard's fonts and widgets); **glass only from Glass UI**: with
  `## OptionalDeps: GlassUI`, when its suite speaks API 1 and "Use Glass UI appearance" is on, it
  builds the answered preset and the suite's body and accent, and reports (`live = false`,
  `declined` when turned off, `reason` on a failed build). The model is `..\Stakeout\Theme.lua`;
  the contract is `..\GlassUI\docs\SUITE.md`. No glass of our own choosing (owner). Helpers:
  `Window`, `Reading`, `Control`, `Accent` (`AccentRGB` for a texture's tint), `NewGlass`; `Active`,
  `Following`, `Glass`.
- **`UI.lua`**: the shared widgets (`Label`, `Header`, `Tooltip`, `Button`, `Check`, `Gear`,
  `Radios`, `Number`, `Search`, `SetList`: a paged list of one sync set), Blizzard templates in both looks; a
  value control returns a `refresh`.
- **`Pearls.lua`**: the registry. `Pearls.Register{ key, name, desc, default, category, section,
  Enable, Disable, defaults, configure, help, onReset, onSettingChanged }` (the last after any
  change of its settings, from any route, sync included: for a pearl that must rebuild); `IsOn`, `IsLive`, `NeedsReload`,
  `PendingReload`, `Set`, `List`, `Categories` (in `CATEGORIES` order), `InCategory`, `Search`,
  `Setting` / `SetSetting` / `ResetSettings` (a pearl's own settings in
  `GlassPearlsDB.settings[key]`), `StartAll` (at login). Only what differs from a default is saved.
  `Enable` / `Disable` / `configure` / `onReset` run under `pcall`: a pearl that throws is recorded
  and the others keep running.
- **`AccountSync.lua`**: `GlassPearls.AccountSync`, one LibAccountSync-1.0 snapshot instance on
  the wire tag `"GlassPearls"` (**permanent: never change it**). `AS.On(kind, fn)`,
  `AS.Send(kind, body)`, `IsEnabled` / `SetEnabled`, `Lines()` for `/gpearls sync`. Payloads are
  `"<kind>\n<body>"`; handlers validate the body and never run it. The store is
  `GlassPearlsSyncDB`, its own SavedVariable, because it holds the household key: never fold it
  into `GlassPearlsDB` or anything exported. Asks the library for the 32 KB ceiling
  (`maxPayload`). Its purpose here is keeping settings in sync across the owner's accounts.
- **`SettingsSync.lua`**: that sync (#4), automatic. A pure core (`SS.Core`: `Compare`, `Encode`,
  `Decode` (strict, all or nothing), `Merge`, `Stamp`, `Clean`) over a registry and a store, and
  a live layer on GlassPearls. **Per-key last-writer-wins**: a local change stamps its key
  `{ t = GetServerTime(), o = this character's GUID, s = saved counter }`, ordered t, o, s
  everywhere. What travels: every pearl's on/off (`on.<key>`), each pearl's settings
  (`<key>.<name>`: booleans, integers with `ranges`, strings with `choices`), `core.glassui`, and
  sets (`RegisterSet`, `SetAdd`/`SetRemove`/`SetHas`/`SetMembers`/`SetClear`) with per-member
  stamps and **permanent tombstones**. Keys from a newer version are kept, merged and relayed,
  never applied, and adopted once known. Choices saved before a key synced (an upgrade) are
  **seeded** at start with a stamp at time 1, so they travel but lose to any real edit. Sends:
  change (2 s debounce), login (+5 s), a new or returning peer (60 s check), retries with backoff.
  Delivery is per peer through `onResult`: only "sent" ends the backoff; a pending handshake
  (`Send` returns 0) or a later "failed" retries once per attempt, and a failed peer is forgotten
  so its next appearance sends again; turning sharing back on sends at once. Replies only when
  holding something newer. Receiving applies
  through the same setters with stamping suppressed. A fixed byte budget per part (see the file's
  header; `test_sync_budget` fills every part). Up to `SETS_MAX` (10) sets share the `SET_MAX` (200)
  entries, and the registry holds up to `KNOWN_MAX` (160) keys (sets raised from 4, #15, and to 10
  with the keys from 128, #53; entries lowered from 300 after v0.1.0-alpha1, #29, to give the known
  keys room). The format's decoder rejects more of any of them (alpha1 more than 160 values or 8
  sets), so change them only before a release or with a format change. The store is `GlassPearlsDB.sync`; integers are
  written with `%.0f` (Lua 5.1's `%d` is 32-bit on Windows).
- **`Core\ToolItems.lua`**: **generated** by `Tools\gen_tools.py` from the client's ItemSparse and
  TotemCategory tables (`References\Forever\db`, the `wago-tools` skill): every item the client
  marks as a tool (`TotemCategoryID > 0`: picks, knives, hammers, spanners, rods, shaman totems,
  the philosopher's stone). Never edit it; re-run the script on a new build.
- **`Core\Bags.lua`**: bag facts for any pearl. `Slot`, `Snapshot`, `Fits(itemID, qty, snap)` →
  true / false / **nil when it can't be told** (GlassMail's measured room rules: a partial stack is
  room, a matching specialty bag takes its family, bags 0-4), `FreeGeneral`, `SetItems`,
  `ItemFacts`, `Eligible(slot, opts)` and `Candidates(opts)`: what may be destroyed, on **known data
  only** (anything uncached, unread or secret makes a stack ineligible), cheapest first by
  `sellPrice × stackCount`, greys first when asked. `Snapshot(true)` is **strict** for an automatic
  action: a bag whose family can't be read, or a stack whose lock can't (`Slot`'s `lockKnown`),
  offers no room. `Take(itemID, qty, snap)` is `Fits` that also reserves the room it found
  (partial stacks, then a matching specialty bag, then general), leaving `snap` as it was on
  false or nil (#36).
- **`Core\Merchant.lua`**: the merchant session for any pearl (#15, #14): `IsOpen`,
  `Session` (a counter per visit), `On(key, fn)` (registers `MERCHANT_SHOW` / `MERCHANT_CLOSED` when
  the first pearl listens; a repeated close is told once), `Current(s)`, `After(delay, s, fn)` (only
  if visit `s` is still open), and one pearl's outcome for a visit that another waits for:
  `Report(key, s, outcome)` (the first counts; another or a closed visit's is ignored) and
  `Await(key, s, seconds, fn)` (told the report, or "skip" after `seconds`; nothing once closed).
  Deliberately small: what a pearl does at a merchant stays in it.
- **`Pearls\Junk.lua`**: sell junk & repair (#15, pearl `junk`, Loot & Bags > Merchant, on by
  default). Junk, on known data only (bags 0-4): greys with a price, and the sell list (sync set
  `junk.sell`) up to rare. Never: the keep list (`junk.keep`), quest items, tools, equipment-set
  items, the Hearthstone, refundable purchases (`C_Item.CanBeRefunded`, even listed); the grey rule
  skips unbound grey gear and greys with a use. At `MERCHANT_SHOW` (+0.2 s; Shift skips the visit;
  never in combat): cheapest first, **one sale in flight**, each re-read just before (same GUID, ID,
  count, link, still junk) and confirmed after (slot empty or the buyback page grew; 1 s without
  stops). Refusals by `GetGameMessageInfo` name (`ERR_VENDOR_DOESNT_BUY`, `ERR_TOO_MUCH_GOLD`;
  localized text as fallback), only while one of ours is in flight. Buyback-safe: the room left on
  the page, a promise conditioned on the player selling nothing meanwhile, and a best-effort link
  check before each sale and at the end. Money is reported as the change observed per phase,
  never attributed. Repair after selling settles: guild funds first (`RepairAllItems(true)`, which
  can take the player's money for what the allowance doesn't cover), then the player's money for
  what's left once the first settled (the cost read again changed, on
  `UPDATE_INVENTORY_DURABILITY`, within 2 s), or "my money only"; `[noautorepair]` in the guild
  info, or an unreadable one, never charges the guild. Commands `/gpearls sell [item]`, `keep`,
  `forget` (the pearl key `junk` is its on/off). It reports each visit's outcome
  (`Merchant.Report`) for restock: "skip" when a sale or repair may still land (a run ended
  unconfirmed, by the buyback check, refused or by combat; an unconfirmed repair; combat; switched
  off mid-visit), "ready" otherwise, from every terminal path. Unmeasured until day one.
- **`Core\AuraAlert.lua`**: what the aura-alert pearls share (#21). `AA.Read(id)`: one player aura by
  ID inside one pcall, answering present (plain table and fields, with its source unit), absent (nil
  AND `C_Secrets.ShouldSpellAuraBeSecret(id)` plainly false) or unknown. `AA.Sounds.New(failKey)`:
  the client's aura sounds (register out of combat or held, remove some or all, refusals recorded).
  `AA.Source(unit)`: a plain, non-empty name or nil. `AA.Entry.New(ids)`: one alert's evidence,
  per ID an aura answer and an overlay answer kept apart; an ID is present (aura present or overlay
  shown), gone, or unknown; the entry shows while any ID is present and clears once every ID that
  made it show is gone; an unknown read keeps a known expiration (the countdown runs on); expiry is
  evidence, never a forced clear. Fixate uses its read and sounds.
- **`Core\Notice.lua`**: the centre text any pearl shows (`Notice.Show(text)`): our own,
  click-through, `CENTER` +200 under the fixate alert, held 6 s then faded, replaced by a new one;
  never Blizzard's raid warning, whose `AddMessage` runs `UpdateCenterScreenAnchors` and moves the
  private-aura anchor.
- **`Data\AuraDurations.lua`**: **generated** by `Tools\gen_durations.py` (SpellMisc → SpellDuration):
  each watched aura's full duration in seconds, for the approximate (`~`) timer.
- **`Pearls\Buffs.lua`**: buff alerts (#21, pearl `buffs`, Combat > Alerts, on by default):
  Clearcasting, Innervate, Power Infusion and the Blessings of Protection, Sacrifice and Freedom
  (`B.ENTRIES`, by ID, each with its own switch and sound). Evidence from `AA.Read` and from
  Blizzard's proc overlay (`SPELL_ACTIVATION_OVERLAY_SHOW` / `_HIDE` with a plain listed ID; a
  HIDE without one hides every overlay). Time left exact from a plain read, `~` from
  `AuraDurations` when only an overlay says so; "from <name>" when the aura names its source (not
  for self). `/gpearls buffs` reports, `buffs test` places. Unverified in combat until day one.
  Blizzard's Cooldown Manager tracks some of these for your own class: compare on day one.
- **`Pearls\BuffsFrame.lua`**: its frame (a row of slots, icon, client name, time, from, pulse;
  below the fixate alert, never overlapping) and its panel.
- **`Pearls\PaladinTank.lua`**: paladin tank reminders (#22, pearl `paladintank`, Combat > Tanking, on
  by default). Only a paladin (classFile) who knows Righteous Fury (25780 or rune 407627); other
  classes register nothing. **Out of combat**, with a shield (option: without): "Righteous Fury is
  off" (both IDs proven absent), "ends in 0:45" under 60 s (gone at 0 without claiming off), and
  "Salvation is on you" (Forever renamed it: 1038 "Salvation", 25895 "Mass Salvation") with its
  exact time left and who cast it. Unknown reads change nothing (last observed); a death forgets;
  hidden in combat, where Blizzard's Cooldown Manager is the pointer. No client sounds.
- **`Data\Training.lua`**: **generated** by `Tools\gen_training.py` (never edit it): what each class
  trainer teaches, from WhatsTraining's curated Forever lists (`References\Addons\Class\WhatsTraining`,
  by Sveng, MIT: read as text, never run), checked against the client's SpellName and SpellLevels
  (`Tools\training\report.txt`). Per class: entries `{ id, level, cost, req, talent, race, faction,
  skill }` and override groups. The client's own tables can't tell trainer spells from talents
  and quest rewards, which is why the curated list is the source.
- **`Pearls\Training.lua`**: the training reminder (#27, pearl `training`, Combat > Spells, on by
  default). On `PLAYER_LEVEL_UP` (held in combat), a toast: what the trainer now teaches (levels
  passed), what was already waiting, the other spec's waiting talent ranks, talent points, the
  cost. Listed only when **provably learnable**: level, every `req` known, the talent known, no
  `skill` (rogue poisons), itself provably unknown (`IsSpellKnown`, `IsSpellInSpellBook` without
  overrides, `IsPlayerSpell`, or a later member of its override or rank group); a read that throws
  or is secret is "can't tell", never listed. **Dual spec by remembering** (`charDB.training`): a
  spec group's talents and talent ranks recorded while it is active (Classic changes a spec's
  talents only while active), another group's waiting ranks shown "as last seen"; a group never
  seen says nothing. Talent points: `C_Traits.GetTreeCurrencyInfo` on the active config, only when
  plain, whole and at most 51 (so the Legacy talent "Talented" counts). Spell tooltips through
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell)` (once; it checks `IsOn`):
  the next ranks, from the trainer list. Unmeasured until day one.
- **`Pearls\TrainingFrame.lua`**: its toast (icon rows with the rank in the corner, text lines, OK,
  gone after 30 s unless the mouse is on it, position per character) and its panel.
- **`Data\Restock.lua`**: **generated** by `Tools\gen_restock.py` (never edit it) from the client's
  Item, ItemSparse, ItemXItemEffect, ItemEffect, SpellEffect, SpellMisc, SpellDuration,
  SpellReagents, SkillLineAbility and SpellLevels tables: food (use spell aura 84) and water (85; alcohol has
  neither; the Manna Biscuits trigger both), `value` = the total restored (points × duration / 5 s,
  as the tooltips say), `bop` (bind on pickup: Forever's level-1 copies of high-end food are),
  `conjured`; ammo (2 arrows, 3 bullets) with its level; per class the reagents its own spells
  consume, only from the audited allowlist `Tools\restock\reagents.csv` (default targets), rune
  copies dropped; `higher`: the poison recipes' higher ranks (by the numeral in the name, checked
  against their levels), since the Poisons line isn't in `Data\SpellRanks.lua`.
  `Tools\restock\report.txt` lists the vendor lines' order, the poison ranks and every drop.
- **`Pearls\Restock.lua`**: restock (#14, pearl `restock`, Loot & Bags > Merchant, on by default).
  At a merchant, after the junk seller reports "ready" (`Merchant.Await`, 10 s; "skip" or nothing
  means no restock this visit; 0.3 s after the show when Junk is off), never with Shift or in
  combat. `R.Plan`: an offer is a merchant item in the data, plain, priced below Blizzard's high
  price line, no extended cost or currency, purchasable, usable, in stock (`C_MerchantFrame
  .GetItemInfo`: price per pack of `stackCount`; `GetMerchantItemInfo` is gone); food and water (mana
  classes) the usable offer that restores most, never bind on pickup; ammo for a hunter's bow,
  crossbow or gun, the highest level; reagents of this class whose spell at its **highest known
  rank** consumes them, never while Buffy restocks them (read in a pcall; unreadable: its fixed
  list). Owned counts only **as good or better** (conjured included); `R.Count` reads every slot of
  bags 0-4, locked ones too, and is nil (the line skipped) if one can't be read. Wanted in whole
  packs rounded up. `R.Run`: one purchase in flight, each step reading the offer, the settings (a
  kind switched off ends its line, a lower target counts, by hand or by sync), the recount, room
  (`Bags.Fits`, fresh) and both limits (`budget`% of the money at the start, `maxSpend` gold; spent
  = the larger of the confirmed prices and the money observed gone) again; a chunk is whole packs,
  at most the merchant's max stack; confirmed only when the count reaches before + chunk within 2 s,
  anything else stops the run. "Ask first" (`mode`) shows the lines and buys from Buy's click, the
  shown counts as the most. Settings: the four kinds, three targets, mode, two limits, and one
  synced integer per allowlisted reagent (`r<itemID>`). Unmeasured until day one.
- **`Pearls\RestockFrame.lua`**: its "ask first" window (beside Blizzard's merchant frame, read for
  its position) and its panel (the kinds and targets, mode, limits, this class's reagents).
- **`Pearls\FastLoot.lua`**: faster loot (#36, pearl `fastloot`, Loot & Bags > Loot, on by default).
  With auto loot on, takes every slot it safely can as the loot window opens. **One pass per loot
  session** (`LOOT_READY` / `LOOT_OPENED` to `LOOT_CLOSED`, a token per session), only when the
  event's payload says auto loot (a plain `false` is final; only a nil payload falls back to
  `GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")`, both plain), consumed
  before its first `LootSlot` (a `LOOT_READY` with no slots yet leaves it to `LOOT_OPENED`), never
  repeated or retried, never while the bags-full helper's own loot is pending
  (`GP.BagsFull.state.pending`, read only). Slot 1 up, each in one `pcall`; left to the client:
  cleared, locked (must read plainly false), a type not positively Money / Currency / Item, an item
  a group's method may send to a roll or a list (`C_PartyInfo.GetLootMethod`: Group,
  Needbeforegreed, Masterlooter at or above `GetLootThreshold()`; Freeforall, Roundrobin, Personal
  never; unknown or unreadable fails closed), an unreadable ID or quantity, or an item that may
  not fit (`Bags.Take` on a strict snapshot). Never touches `LootFrame`, the bind-on-pickup popup
  (`ConfirmLootSlot` never called) or the errors. **It keeps its session listeners after the first
  enable, also while off** (they only follow sessions then), so a window closed while off never
  leaves the next corpse with a consumed pass: don't "clean that up". The client's own auto loot is
  expected to run beside it: a day-one check. **Coin text** (setting `coins`, on): a coins-only
  pass floats up the sum of the positive `PLAYER_MONEY` changes seen while a `CHAT_MSG_MONEY` came
  (its text never read), shown only when the window closed, the message came and the sum is
  positive within 2 s; else it expires silently. Its record starts, provisional, before the first
  `LootSlot` (the game may credit the money inside the call) and is confirmed only for a coins-only pass. `/gpearls fastloot`: the last pass (loot calls
  made, what was left by reason). Unmeasured until day one.
- **`Pearls\FastLootFrame.lua`**: its coin text (click-through, at the cursor, rises and fades,
  `TrainingFrame.Money` for the coins) and its panel (the `coins` switch).
- **`Pearls\LowBuffs.lua`**: low-rank buffs (#42, pearl `lowbuffs`, Social > Group, on by default;
  its two-control panel in the same file). When another player's **single-target** buff lands on
  you at a lower rank than they could cast, a chat line says so, once per caster (GUID) and buff a
  session. `LB.WATCH`: the first ranks of Fortitude, Arcane Intellect, Mark of the Wild, Thorns,
  the Blessings of Might, Wisdom and Light, Divine Spirit and Shadow Protection (group buffs left
  out: the downrank rule is established for single-target ones); `SpellRankData.ranks[id]` is a
  positional `{ group, rank, level }`. **Expected rank**: the highest of the group the caster's
  class trainer lists (`TrainingData`: book ranks never), at most the caster's level minus a
  grace (0 below 10, 3 at 10-19, 2 to 49, 1 at 50-59, 0 at 60; a reference addon's, MIT) and at
  most **your level + 10** (the downrank rule: lower on a low-level player is correct). Only
  casters at or above `minLevel` (60, the owner); a caster seen at a higher level than before
  this session is never judged (sticky, recorded before any other exit). **Detection, out of
  combat only**: `UNIT_AURA` (payload untouched) queues one check a frame later; each watched ID
  is uninitialized, absent or present; a baseline (Enable, `PLAYER_ENTERING_WORLD`,
  `PLAYER_REGEN_ENABLED`) makes all uninitialized and reads at once; only absent → present is
  judged, everything about the caster read in that same check (`sourceUnit`, plain `UnitGUID`,
  `UnitIsPlayer`, not you by `UnitIsUnit`, `UnitLevel`, `UnitClass`, `GetUnitName(unit, false)`:
  the first name and surname on Camelot). **Whisper** (setting `whisper`, off): only to people
  you positively know (`UnitInParty`, `UnitInRaid` a positive index, `UnitIsInMyGuild`,
  `C_FriendList.IsFriend(guid)`), once per caster a session, 10 s apart, consumed at the attempt,
  never queued; refused in combat, dead, in an instance, under `InChatMessagingLockdown`, or
  unless the chat add-on restriction is plainly `Inactive`; `C_ChatInfo.SendChatMessage` in a
  pcall. `/gpearls lowbuffs`: the last 10 flags and skip counts. Unmeasured until day one.
- **`Pearls\InstanceGear.lua`**: instance gear reminders (#43, pearl `instancegear`, Combat > Instances, on
  by default). `IG.CASES`, one small table (keys and resistance gear will need their own design): the
  Argent Dawn trinket (setting `argentdawn`) in Scholomance 289 and Stratholme 329 (`GetInstanceInfo`'s
  8th return, `instanceType` plainly not `"none"`: it answers the continent outdoors), below Exalted with
  faction 529 (`C_Reputation.GetFactionDataByID(529).reaction`, plain integer 1-8; setting `exalted`:
  also at Exalted), when none of 23206, 23207, 19812, 13209, 12846 (every trinket whose spell allows
  Scourgestones; the Seal and Rune not in ItemSparse yet) is in slot 13 or 14. Then the first carried
  (`C_Item.GetItemCount`, which counts carried **and worn**, read only once nothing listed is worn) gives
  "Equip your <name>", else the first banked (`GetItemCount(id, true)` minus that) gives "is in your
  bank", else silence. Every unreadable read is silence; an unreadable count skips that item, never
  zero. **One check per entry**: `PLAYER_ENTERING_WORLD` opens an entry (a duplicate while one is open is
  ignored) and schedules a check 5 s later only when `isReloadingUi` is plainly false;
  `PLAYER_LEAVING_WORLD` and `Disable` close it, and a check runs only for the open entry's token, reading
  everything again. A chat line (the client's item and faction names, with fallbacks) and the centre
  text. `/gpearls instancegear [test]`: what it reads here (counts labelled "carried + worn" and "with
  bank"). Unmeasured until day one.
- **`Pearls\InstanceGearFrame.lua`**: its panel (the centre text is `Core\Notice.lua`).
- **`Pearls\PetCare.lua`**: hunter pet care (#38, pearl `petcare`, Combat > Pets, on by default). **Hunters
  only** (`UnitClass` classFile): any other class registers nothing, hooks nothing, builds nothing.
  - **Feeding** (`feed`, `feedAt` = `content` | `unhappy`): a live hunter pet (`HasPetUI`'s second return)
    whose `C_PetInfo.GetPetHappiness` is plainly at or below the threshold, out of combat. One drop:
    the chat line once (`PET_HAPPINESS1-3`; "no eligible food: n left out by your never-feed list, n not
    loaded yet", never "nothing to eat" when food was only left out), the window until happy, the pet
    gone, combat (offered again after) or Close (dismissed for the drop). Re-armed when the happiness
    reads plainly above, or a new pet (GUID) appears.
  - **The food** (`PC.Candidates`): bags 0-4, `CanPetEatItem` plainly true, not in the sync set
    `petcare.never`, cached (`Bags.ItemFacts` with a plain level; else `RequestLoadItemDataByID` once and
    `GET_ITEM_INFO_RECEIVED` chooses again), lock plainly false. A heuristic: within 10 levels of the
    pet, the cheapest per item first, else the highest level; ties by bag and slot.
  - **`PC.CanFeed`** (the Feed button's click): the pearl and window, `GetCursorInfo` empty,
    `SpellIsTargeting` plainly false, a live hunter pet still at or below the threshold (`PC.Mood()`
    "hungry": the test window never feeds a Happy pet), the slot still holding the item unlocked, still
    edible and not never-listed, `C_Spell.IsSpellUsable(6991)` plainly true. Refused: chosen again.
  - **Pet checks** (`missing`, `passive`; when: `atFight`, `atReady`, `away`): "Your pet is dead", "You
    have no pet out", "Your pet is on Passive" (the token slot whose texture key is
    `"PET_PASSIVE_TEXTURE"`, active; a live hunter pet only), only for a hunter who plainly knows Call
    Pet (883); chat plus `GP.Notice`. `PC.Warning` reads only what it needs and **never refuses because
    combat was noted**: the fight start (inside `PLAYER_REGEN_DISABLED`) and a ready check in combat use
    it. **Away** (off): 10 s after `UNIT_PET("player")`, `UNIT_FLAGS("pet")`, PEW, `PLAYER_ALIVE`,
    `PLAYER_UNGHOST`, `PLAYER_CONTROL_GAINED` (a newer trigger replaces it; expired in combat, checked
    at `PLAYER_REGEN_ENABLED`; stale on leaving the world or switching off); missing or dead only, once
    per absence (re-armed by a live pet; never silences the other two); quiet when dead, on a taxi,
    mounted, feigning death, without full control, the pet possessed, or at the stable master (an
    unreadable one counts as quiet). Payloads compared only when plain. `/gpearls petcare [never | forget |
    test]`. Unmeasured until day one.
- **`Pearls\PetCareFrame.lua`**: its window (position per character, the Feed button, Never feed this,
  Close), the tooltip line and the bag marks, and its panel. **The Feed button** is a
  `SecureActionButtonTemplate` (with `UIPanelButtonTemplate`), the window's child: `type` "spell", 6991,
  and `target-bag` / `target-slot`, which Blizzard's `OnActionButtonClick` uses after the action **whatever
  the action was** (`SecureTemplates.lua:772`), so it is **disarmed (all four cleared) whenever no click
  is in progress**; both edges, `useOnKeyDown` false, the release's PreClick arms it (type last), PostClick
  disarms. The window is protected in combat through its child: shown and hidden only out of combat
  (hidden inside `PLAYER_REGEN_DISABLED`), never in `UISpecialFrames`. **Tooltip** (`food` = `tooltip` |
  `both`): one `TooltipDataProcessor` item post-call. **Bag marks** (`bags` | `both`): `hooksecurefunc`
  on each `ContainerFrameContainer.ContainerFrames` frame's and `ContainerFrameCombinedBags`'s
  `UpdateItems`, once; our own child frame per button in a weak table (nothing written on Blizzard's
  buttons; the button's bag and slot read every time, they're pooled); none created in combat (made
  after the fight).
- **`Pearls\AutoGossip.lua`**: auto gossip (#47, pearl `autogossip`, Automation > NPCs, on by
  default). **Gossip only**: nothing while the NPC has quest business. Scope: ordinary gossip with an
  NPC (`GOSSIP_SHOW`'s `textureKit` plainly nil, `UnitExists("npc")` plainly true; a refresh keeps
  the show's scope). A **page** (show, refresh; ended by every close) is decided once, a frame
  later (`C_Timer.After(0)`, so Blizzard's own frame goes first), unless anything selected on it
  meanwhile (`hooksecurefunc` on `C_GossipInfo.SelectOption` / `SelectOptionByIndex`; ours are
  marked before the call). Never in combat, with Shift, with quest business, past the chain's cap,
  or when Blizzard's own lone pick applies (`GossipFrameShared.lua:191`). Picks an option of the
  sync set `autogossip.always` (two on a page: nothing; `ForceGossip` doesn't block it), else the
  lone option by the `lone` setting (`off` | `services` | `most`, the default: never the binder or
  spirit healer icons | `any`; icons are the override first, binder 132052/136458 and healer
  132054 fixed, services fixed plus `GetFileIDFromPath` of Blizzard's gossip icon paths, unresolved
  means not admitted). The same decision runs again on fresh state and must give the same option;
  selected by ID (else index), **never with `confirmed`**. A **chain** (one conversation): 3
  automatic picks, never the same ID twice, none after a pick by index; ends at a plainly
  terminal close, the NPC plainly gone a second after a close, 60 s without a page, a loading
  screen, or switching off; its timers carry its token. **Learning** counts only a `PreClick` on
  Blizzard's own option buttons (`GossipFrame.GreetingPanel.ScrollBox`: scanned at each decision,
  plus `ScrollUtil.AddInitializedFrameCallback`; option rows only), and only on a positive sign:
  a new page or an allowlisted service window (`SERVICE_TYPES`: never Binder, TalentMaster,
  SpiritHealer...). Silence is never clean (10 s, then dropped); two clicks before a sign: neither.
  `CONFIRM_BINDER` / `_TALENT_WIPE` / `_XP_LOSS` mark the pending pick; `GOSSIP_CONFIRM` /
  `GOSSIP_ENTER_CODE` name the option and also take it off the always list. After `repeats` (3)
  picks, the prompt offers Always / Not now / Never (sync set `autogossip.never`), never for the
  binder, the healer, a confirmed option or a lone option the rule picks anyway. Counts, names
  and confirms are local (`GlassPearlsDB.autogossip`, counts at most 200). `/gpearls gossip
  [list | trace | always <id> | forget <id>]`: the page's options with their IDs and icons, for
  day one. Unmeasured until day one.
- **`Pearls\AutoGossipFrame.lua`**: its prompt (one at a time, 30 s, hidden for a fight and offered
  again after, position per character) and its panel (the lone radios, the offer switch, repeats,
  the two lists through `UI.SetList`).
- **`Pearls\MarkWheel.lua`**: the raid mark wheel (#34, pearl `markwheel`, Social > Group, on by
  default). Pings are the client's own (`Blizzard_PingUI`, its Ping key and wheel: only it can ping a
  world spot), so this is marks only, **out of combat only**. Opened by the key `GLASSPEARLS_MARKWHEEL`
  (root `Bindings.xml`, category "Glass Pearls", not in the TOC: the deploy copies it and the package
  check expects it) over a unit, or by an entry appended with `Menu.ModifyMenu` to the unit menus that
  carry Blizzard's Raid Target Icon (`M.MENUS`: not ENEMY_PLAYER on Camelot, not VEHICLE or BOSS),
  registered once at the first enable and kept (its calls during our registration, on a cached
  menu, are ignored). The mark is set by Blizzard's secure `raidtarget` action, never by our code:
  **one `SecureActionButtonTemplate` button** (parented to UIParent, `AnyDown`+`AnyUp`,
  `useOnKeyDown=false`), **disarmed whenever no click is in progress**; the down edge does nothing;
  the release's insecure PreClick checks lockdown, the pearl, the session and the cursor, then sets
  `unit`, `marker`, `action` (`toggle` / `clear`) and `type` last; PostClick closes, which disarms. An
  up with no down of ours is ignored. The unit is a **session** `{ token, guid, epoch }`: the key
  resolves the mouseover at once with `UnitIsUnit` over target, player, focus, group, pets and
  nameplates; a menu gives its token when built (other tokens refused). It holds while one epoch is
  unchanged (bumped by target, focus, pet, roster and world changes and by switching off; the open
  wheel's own plate removal closes it) and, when the GUID was plain at capture, while it reads the
  same (plain then secret is refused). Gates: combat, in a raid leader or assistant,
  `CanBeRaidTarget` not plainly false. Combat: closed inside `PLAYER_REGEN_DISABLED` (raw
  `InCombatLockdown()` still false); once locked nothing protected is touched and a separate frame
  finishes the cleanup at `PLAYER_REGEN_ENABLED`, on or off. Geometry: Blizzard's gamepad segments
  (`(g-1)*45` degrees from east), marks `M.MARKERS = { 2, 1, 8, 7, 6, 5, 4, 3 }` (skull at the top),
  Clear in the centre, outside cancels. `/gpearls markwheel [test]`. Unmeasured until day one.
- **`Pearls\MarkWheelFrame.lua`**: its art (never a parent or anchor of the button, click-through,
  in `UISpecialFrames`: hiding it ends the wheel), the open (0.15 s) and close (0.12 s) scale and
  alpha animations (a close hides only its own open), and its panel (the menu switch, the key, Test).
  WoW Forever: the gamepad radial art (`gamepad-radial-menu-wheelbg` / `-selected` /
  `-bottomtext`), the highlight turned `rad(angle - 270)` and offset as `GamepadRadial.lua:1111`
  does, scaled by the wheel atlas's width; glass: a LibGlass disc, the highlight in the suite's
  accent. An atlas only when `C_Texture.GetAtlasInfo` knows it; otherwise a plain disc and lines.
- **`Pearls\Fixate.lua`**: the fixate alert (#17, pearl `fixate`, Combat > Alerts, on by default).
  **Every client language: spell IDs only, never a name**; the alert's words are the client's
  (`C_Spell.GetSpellName` / `GetSpellTexture`). The IDs are the client's four spells named
  "Fixate" (`F.SPELLS`; add one found under another name by ID). Auras are secret in combat, so
  two paths: the **client's own sound** (`C_UnitAuras.AddAuraSound(Added, { unitToken = "player",
  spellID, ... })`, registered out of combat, removed when off; refused is recorded), and the
  **alert when the aura can be read**: `RegisterUnitEvent("UNIT_AURA", "player")` with its payload
  never touched, then `GetPlayerAuraBySpellID` inside one pcall answering **present** (a plain
  table), **absent** (nil AND `C_Secrets.ShouldSpellAuraBeSecret(id)` plainly false; a spell can be
  always secret) or **unknown**; shown on present, cleared on absent or its own countdown ending,
  never on unknown. `/gpearls fixate` reports what the client allowed per spell; `fixate test`
  places the alert. Unverified in combat until day one.
- **`Pearls\FixateFrame.lua`**: the alert (icon, the client's spell name, a countdown; click-through,
  draggable during a test, position per character) and its panel.
- **`Pearls\Uncrushable.lua`**: uncrushable (#19, pearl `uncrushable`, Combat > Tanking, on by default),
  the "Uncrush" macro's replacement. Blizzard's own Forever paper-doll math
  (`Camelot/PaperDollFrameStats.lua`): against a +3 boss, miss = `5 - ((level+3)*5 - defense) *
  0.04` clamped 0-100, dodge/parry/block each 0.6 lower and never below 0, block 0 without a
  shield; uncrushable at 100% (the 102.4% rule on equal-level numbers). Defense =
  `UnitDefenseSkill` base + modifier (combat ratings are always 0 here, which is why the macro was
  wrong). No crushing percentage is claimed, only the shortfall. An addon-owned line in the footer
  of `CharacterStatsPaneScrollBox` (Forever's stats pane), refreshed by a `hooksecurefunc` on
  `PaperDollFrame_UpdateStats` and the stat events (payloads untouched); shown with a shield
  (Blizzard's rule for its Block row; no measured spec), or always by option. `/gpearls
  uncrushable` prints it. Every value checked for secrecy.
- **`Pearls\JunkFrame.lua`**: its Configuration Panel (four switches, the two repair choices, the
  sell and keep lists).
- **`Pearls\BagsFull.lua`**: the bags-full helper (#6, pearl `bagsfull`, on by default). Shows when a
  loot row really doesn't fit, or after a full-bags error with no loot window ("make room").
  Offers grey (default) or grey and white items, never quest items, tools, equipment-set items,
  containers, reagents, ammunition, recipes, quivers, keys, fishing poles, white consumables or
  white items with a use, nor the never-suggest list (the sync set `bagsfull.keep`). The action runs
  inside the window button's click: the whole decision made again at the click (a stale window never
  deletes: loot closed, row looted, room appeared), grey in one click, white armed by a
  second within 3 s, the cursor and slot lock confirmed, `DeleteCursorItem`; refused (the cursor
  still holds it, or `ADDON_ACTION_FORBIDDEN`) puts the item back and switches to **by hand** for
  the session; the loot (`LootSlot`) only once the slot is confirmed empty (`Bags.Slot` says
  "empty", never "unreadable"), with the row still holding that
  item (`LOOT_CLOSED` cancels it). Unmeasured until day one: the delete and the loot path (probe).
- **`Data\Landmarks.lua`**: **generated** by `Tools\gen_landmarks.py` (never edit it): dungeon and
  raid entrances (doors shared by several are one entry), boat, zeppelin and tram stops, zone level
  ranges, and every zone map ID. Sources: the client's tables (`References\Forever\db`: AreaTrigger,
  TaxiPath / TaxiPathNode, UiMap*, LFGDungeons) where they have the answer, `Tools\landmarks\*.csv`
  (our verified list, with a confidence per entrance) otherwise, and the cached Wowhead zone pages
  for levels. Positions are **world coordinates in the client tables' order: x north, y west**.
  `Tools\landmarks\report.txt` lists what came from where.
- **`Pearls\Landmarks.lua`**: map landmarks (#10, pearl `landmarks`, Interface > Maps, on by
  default). Pins through the vendored HereBeDragons-Pins on the world map (zone and continent) and
  the minimap, a frame per display, **tooltip only** (clicks pass through: a waypoint would fight
  NodeRadar's). HereBeDragons' world x is west, y north: every world call passes our `(y, x)`.
  Flight points come from `C_TaxiMap.GetTaxiNodesForMap` per zone, with Blizzard's faction and
  undiscovered rules, and none on a world map where `ShouldMapShowTaxiNodes` says Blizzard draws
  them. The zone level line sits under Blizzard's area label (read for its position, never
  written), only when `C_Map.GetMapLevels` gives no range. Any setting change rebuilds.
  Unmeasured until day one: the icons, the positions marked "hand", the taxi API away from a
  flight master, Blizzard's label.
- **`Data\SpellRanks.lua`**: **generated** by `Tools\gen_ranks.py` (never edit it): every class
  spell that comes in ranks, `groups[g]` (IDs, lowest rank first) and `ranks[id] = { g, rank,
  level }`, from the client's SkillLine (class trees: category 7 with flag 0x400; pet lines lack
  it), SkillLineAbility (Season of Discovery rune copies, `AcquireMethod` 3, dropped), Spell
  (`Rank N`), SpellName and SpellLevels. Names group ranks **offline only**. Two spells sharing a
  name (Lightning Shield's buff and its bolt) are split by their description's first sentence;
  two IDs of one spell at one rank (Seal of Righteousness 1) both stay; `Tools\ranks\exclude.csv`
  drops groups whose ranks are different spells (Detect Invisibility). `Tools\ranks\report.txt`
  lists every decision.
- **`Pearls\SpellRanks.lua`**: low spell ranks (#12, pearl `spellranks`, Combat > Spells, on by
  default). A spell is low when a higher rank of its group is known (`C_SpellBook.IsSpellKnown`,
  else `IsPlayerSpell`) and casts as itself (`C_Spell.GetOverrideSpell` is it, or a higher rank of
  the group); kept spells (the sync set `spellranks.keep`) never are. **IDs only.** The scan reads
  the player's own pages (the main six, multi bars, stance bars; never the vehicle, override,
  temporary-shapeshift, extra or multicast pages, read at scan time); macros are listed, never
  edited; a low rank seen cast (`UNIT_SPELLCAST_SUCCEEDED`) is listed too. One debounced
  scheduler (login, learning, a spec swap plus a second pass); never in combat or with a class
  trainer open. **Update all** runs in our button's click, out of combat, cursor empty; after each
  `PlaceAction` it reads the slot and the cursor again: a slot read as the best rank counts, a spell
  of the group on the cursor is cleared, anything else is left and said, a failed placement is
  undone only into an empty slot, and the first unclean result stops the run. Unmeasured until
  day one: whether the client updates bars itself, `PlaceAction` from addon code, the page mapping.
- **`Pearls\SpellRanksFrame.lua`**: its popup (Keep, Later, Update all; position per character) and
  its Configuration Panel (when it checks, what it lists, Check now, the kept ranks).
- **`Pearls\BagsFullFrame.lua`**: its window (beside the loot window, or where the player dragged it,
  per character) and its Configuration Panel (quality scope, greys first, the never-suggest list).
- **`Options.lua`**: **our own options window**, on Leatrix Plus's layout (the owner's choice;
  `References\Addons\Miscellaneous\LeatrixPlus`, All Rights Reserved: the layout is the model,
  nothing is copied). Left: the name, the version, Home, each category that has pearls, Settings.
  Right: two columns of sections, a checkbox per pearl, a gear opening its Configuration Panel in
  the same window (Reset, Help, Back to Main Menu), `*` after a pearl without `Disable`, Reload
  while a change waits, a search box. Built on first open, re-read on every show; Esc through
  `table.insert(UISpecialFrames, ...)` (never reassign it). Reload calls `ReloadUI()` from its own
  click (unmeasured: if `ADDON_ACTION_FORBIDDEN` names it, "Type /reload" replaces the button).
  Plus a small Esc > Options > AddOns page with an "Open Glass Pearls" button.
- **`GlassPearls.lua`**: bootstrap (saved settings, the look at `ADDON_LOADED`, login build
  warning), `GP.Settings`, and `/gpearls` (`/glasspearls`): no argument toggles the window. A pearl's
  key with `on`/`off` switches it; a pearl command of the same name as its key takes every other
  argument (`/gpearls fixate`, `/gpearls fixate test`). Loads last.

### Adding a pearl

1. `Pearls\<Name>.lua`, starting `GlassPearls = GlassPearls or {}`, calling
   `GlassPearls.Pearls.Register{...}` at file scope and doing **nothing else until `Enable`**
   (no frames registered for events, no hooks). The key is the saved key: lower-case letters or
   digits, permanent. Give it a `category` from `Pearls.CATEGORIES` and a `section`.
2. List it in the TOC after `Pearls.lua` (test_toc checks the order); the deploy script follows
   the TOC.
3. Give it a `Disable` that undoes `Enable` where the client allows it. Where it can't (a
   `hooksecurefunc` can't be removed), omit `Disable` or make the hook check `Pearls.IsOn`; the
   window then shows `*` and Reload.
4. Options: `defaults` for its settings, read with `Pearls.Setting`, written with
   `Pearls.SetSetting`; `configure(panel, refreshers)` builds its panel from `GP.UI` widgets and
   adds each control's `refresh`; `help` for the Help button. Settings sync picks them up: give a
   string setting its `choices` and an integer one its `ranges`, or it won't travel. A list (a
   keep list) is a sync set: `SettingsSync.RegisterSet("<key>.<name>")` at file scope. Mind the
   budget: `test_sync_budget` fails if the known keys outgrow their 12 KB or the whole, every part
   full, its 31 KB, and the registry its 160 keys (with #38: 122 keys and 7 of 10 sets, known keys 9.0 KB,
   the whole about 28 KB; the 12 KB share is the real limit, about 40 more keys).
5. Slash commands of its own: `commands = { name = { help, run(arg) } }` (`/gpearls <name>`, listed
   by `/gpearls help`).
6. A test file `tests\test_<name>.lua` (the bags-full helper's four are the model), and a line in
   `CHANGELOG.md` under the next version.

## Forever basics (shared with the siblings)

- One plain `GlassPearls.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**).
  Never commit a literal version over `@project-version@`; the deploy script writes `dev` into its
  copy.
- One global namespace, `GlassPearls`; files start `GlassPearls = GlassPearls or {}` and alias it
  `local GP = GlassPearls`. A `_test` seam table exposes file-local internals to tests.
- **Extend Blizzard's UI; never replace it.** Only `hooksecurefunc`, `HookScript` and addon-owned
  frames. Never reassign a Blizzard global or method, never write a field onto a Blizzard frame.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- `ReloadUI()` is protected. Options use `Settings.RegisterCanvasLayoutCategory`.
- SavedVariables persist as of 70009; read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when
  they're absent, and **verify persistence only with a full client exit**.
- **IDs, never names**: never compare against or save an English display string (localized
  clients).

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field
  notes. Treat them as fact. New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\Forever\api\`: the API dumps; use the highest build (the root
  CLAUDE.md's rule). This repo was made against 1.60.1.70532. **Presence is not a contract.**
- `C:\Projects\WoW\References\Docs\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`: library rules.
  `..\LibGlass\README.md` and `..\LibAccountSync\README.md`: the two libraries' contracts.
- `C:\Projects\WoW\wow-ui-source` (branch `forever`): the client's own FrameXML; line numbers match
  in-game error traces.
- `C:\Projects\WoW\References\Addons\`: third-party addons as **behaviour references only**. Check
  each one's licence before reading closely, and never copy code from one that isn't permissive.
  This repo is MIT.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files, then every tests\test_*.lua (needs ..\LibGlass and ..\LibAccountSync, or $env:LIBGLASS / $env:LIBACCOUNTSYNC)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1                                                # copy the addon and both libraries into AddOns
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`
  (`-AddOnsPath` to change).
- In game: `/console scriptErrors 1` first, then `/reload`. A brand-new addon folder no longer
  needs a client restart, unless it brings new textures (owner, 2026-10-09; see the porting guide).
- The tests load the sibling library checkouts as they are and warn when one is off its `.pkgmeta`
  pin; CI fetches the pins (`tests\fetch_external.sh`) and also checks the packaged zip's exact
  contents.
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

GlassMail's harness, plus GlassChat's Battle.net stubs: `tests\wow_stubs.lua` (strict globals as
an allowlist of APIs verified in the dump, secrets as throwing `newproxy` values, event names
validated against the dump or `tests\events-70532.txt`, every widget method recorded, Battle.net
and ChatThrottleLib for LibAccountSync, `WoW.installGlassUI` for a scriptable Glass UI suite,
`WoW.missingTemplates` for a template the client lacks, `WoW.reloadForbidden` for a refused
`ReloadUI`, the world map, `C_Map` / `C_TaxiMap` / `C_Texture` and a recording HereBeDragons fake,
`WoW.installFakeHBD`, which the harness installs in place of the vendored copy, action slots,
macros, known spells, overrides and a spell on the cursor (`WoW.actions`, `WoW.known`,
`WoW.placeHook`, ...), and a merchant: selling, the buyback page, repair and guild funds
(`WoW.openMerchant`, `WoW.money`, `WoW.buyback`, `WoW.repairCost`, `WoW.guild`, `WoW.salesAsync`,
...) and its goods (`WoW.goods`, `BuyMerchantItem` into the bags, `WoW.buysAsync`, `WoW.buyShort`,
`WoW.buyRefuses`, `WoW.equipped`, `WoW.loadedAddOns`), and player auras with the client's aura sounds and per-spell secrecy (`WoW.auras`,
`WoW.spellAuraSecret`, `WoW.auraSounds`; `GetAuraDataBySpellName` throws, so no name lookup
survives a test), and the character panel's stats (`WoW.stats`, `CharacterStatsPaneScrollBox`,
`PaperDollFrame_UpdateStats`), and the raid mark wheel's: units and marks (`WoW.units`, `WoW.marks`,
`UnitIsUnit`, `SetRaidTarget` from the secure action only, else `WoW.forbidden`), a
`SecureActionButtonTemplate` dispatch modelled on Blizzard's (`WoW.click`, `WoW.secureActions`,
both edges and the CVars), protected frames refusing to show, hide or move in combat (`WoW.blocked`),
the cursor (`WoW.mouse`, `WoW.uiScale`), `Menu.ModifyMenu` with its synchronous call on a cached
menu (`WoW.openMenu`, `WoW.menuButton`), Blizzard's gossip frame for auto gossip (`WoW.openGossip`,
`WoW.playerPicks`, `WoW.closeGossip`, its own lone pick in either order, pooled option buttons,
`WoW.gossipOnSelect` for events inside a select), faster loot's loot window (`WoW.openLoot(rows, { autoloot,
noReady, emptyReady, noOpened })`, locked, quality and money rows, `WoW.lootMethod`, `WoW.lootThreshold`,
`WoW.modified`, unreadable bag families and locks), low-rank buffs' casters and chat (`WoW.unitLevels`,
`WoW.unitClasses`, `WoW.players`, `WoW.fullNames`, `WoW.partyMembers`, `WoW.raidIndex`, `WoW.guildMembers`,
`WoW.friends`, `WoW.sentChat`, `WoW.chatLockdown`, `WoW.chatRestriction`, `WoW.auraReads` per ID), instance gear's instance, standing and counts (`WoW.instance`, `WoW.factions`,
`WoW.itemCounts` with what `WoW.equipped` wears, `WoW.itemCountThrows`), pet care's pet, pet bar and food (`WoW.pet`,
`WoW.petExistsSecret`, `WoW.petBar`, `WoW.edible`, `WoW.onTaxi`, `WoW.mounted`, `WoW.feign`, `WoW.fullControl`,
`WoW.spellUsable`), Feed Pet's item targeting through the secure `spell` action and its `target-bag` /
`target-slot` block (`WoW.spellTargeting`, `WoW.fed`), Blizzard's bag frames (`WoW.containerFrames`,
`ContainerFrameCombinedBags`, `WoW.showBag`; `WoW.hooked` counts each secure hook), a clock (`WoW.advance`), and atlases with sizes (`WoW.atlases`; `SetAtlas` returns
nothing, as on the client)), `tests\harness.lua` (`check`, `eq`, `loadAddon` with an `opts.before` hook for
registering test pearls, `opts.pearls = false` to leave the shipped pearls out of a framework
test, `newChat`, `chatHas`). Bags, items, the cursor and the loot window are modelled too
(`WoW.bags`, `WoW.items`, `WoW.openLoot`, `WoW.deleteForbidden`, ...; the block's header lists them). A stub is added only for something in the 70532
dump (documented functions or the `_G` walk) or Blizzard's source, and its comment says which.

**The unit tests are the main proof until 2026-11-04** (owner): one test file per concern, every
new assertion mutation-tested (break the behaviour, confirm it goes red; list them in the PR).
Offline tests can't cover taint, real secrets or rendering; that's PearlsProbe (#5) and the
day-one checklist.

## Workflow and releasing

- Every change goes through a GitHub issue → branch off `main` → PR with `Closes #N`. Never
  commit to `main`. `luac -p` clean and tests green before committing; check the PR's
  `package-check` run after pushing.
- **Never merge a PR without the owner's approval** (owner, 2026-10-25). The one exception: a
  documentation-only PR where a review would add nothing, which may be merged and reported. A PR
  touching `.github/workflows/`, the TOC or any Lua is never that.
- **Plans** get an adversarial review before coding (the `codex-consult` skill). Verify its
  claims; push back on complexity.
- **Releasing** follows `C:\Projects\WoW\References\Docs\RELEASING.md`; `package-check.yml` and
  `tests/release_files.sh` are its templates (only the `REPO-SPECIFIC` steps are this repo's).
  - CurseForge project **1764704** builds a release from every tag through its webhook and
    `.pkgmeta`. No CurseForge key lives in the repo, and the packager never uploads from CI.
  - The tag's run publishes CI's own checked zip as a GitHub Release (with `release.json`) and
    uploads it to Wago Addons, project **`kGr9LxKy`** (https://addons.wago.io/addons/kGr9LxKy),
    with the `WAGO_API_TOKEN` repo secret (set 2026-10-25).
  - The TOC carries both IDs (`X-Curse-Project-ID`, `X-Wago-ID`); test_toc checks them.
  - The notes are the tag's `## vX.Y.Z` section of `CHANGELOG.md`, which always has one: the
    release-files step reads the newest heading on every run and fails without one.
  - `README.curseforge.md` (gitignored) is the CurseForge and Wago description, pasted by hand.

## Conventions

- **Right-size for a single maintainer.** Each pearl stays small; the simplest thing that works,
  no speculative abstraction. A pearl that outgrows this addon becomes its own.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
